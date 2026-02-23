import CameraDomain
import Foundation

private final class OnvifMonitorCallbacks: @unchecked Sendable {
    private let onEvent: @Sendable (CameraEvent) -> Void
    private let onFailureThreshold: @Sendable (Error) -> Void

    init(onEvent: @escaping @Sendable (CameraEvent) -> Void, onFailureThreshold: @escaping @Sendable (Error) -> Void) {
        self.onEvent = onEvent
        self.onFailureThreshold = onFailureThreshold
    }

    func emitEvent(_ event: CameraEvent) {
        onEvent(event)
    }

    func emitFailure(_ error: Error) {
        onFailureThreshold(error)
    }
}

final class OnvifEventMonitor {
    private let config: TapoSetupConfig
    private let password: String

    private var monitoringTask: Task<Void, Never>?

    init(config: TapoSetupConfig, password: String) {
        self.config = config
        self.password = password
    }

    func start(
        onEvent: @escaping @Sendable (CameraEvent) -> Void,
        onFailureThreshold: @escaping @Sendable (Error) -> Void
    ) {
        stop()
        let config = self.config
        let password = self.password
        let callbacks = OnvifMonitorCallbacks(onEvent: onEvent, onFailureThreshold: onFailureThreshold)
        let operation: @Sendable () async -> Void = { [config, password, callbacks] in
            var backoffSeconds = 2
            var failureStreak = 0
            var lastSignature = ""
            var lastEventAt = Date.distantPast
            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.timeoutIntervalForRequest = 10
            sessionConfig.timeoutIntervalForResource = 15
            let session = URLSession(configuration: sessionConfig)

            // Create subscription before polling
            var subscriptionEndpoint: URL?
            do {
                subscriptionEndpoint = try await Self.createPullPointSubscription(
                    config: config,
                    password: password,
                    session: session
                )
                NSLog("📡 ONVIF subscription created: \(subscriptionEndpoint?.absoluteString ?? "nil")")
            } catch {
                NSLog("📡 ONVIF subscription failed: \(error.localizedDescription), falling back to base endpoint")
            }

            // Determine the polling endpoint
            let pullEndpoint = subscriptionEndpoint ?? Self.baseEventURL(config: config)

            var renewCounter = 0
            let renewInterval = 25 // Renew subscription every ~50 seconds (25 polls × 2s)

            while !Task.isCancelled {
                do {
                    // Periodically renew the subscription to prevent expiry
                    renewCounter += 1
                    if renewCounter >= renewInterval, let subEndpoint = subscriptionEndpoint {
                        renewCounter = 0
                        do {
                            try await Self.renewSubscription(
                                endpoint: subEndpoint,
                                config: config,
                                password: password,
                                session: session
                            )
                            NSLog("📡 ONVIF subscription renewed")
                        } catch {
                            NSLog("📡 ONVIF subscription renewal failed: \(error.localizedDescription)")
                            // Re-create subscription
                            do {
                                let newEndpoint = try await Self.createPullPointSubscription(
                                    config: config,
                                    password: password,
                                    session: session
                                )
                                subscriptionEndpoint = newEndpoint
                                NSLog("📡 ONVIF subscription re-created: \(newEndpoint?.absoluteString ?? "nil")")
                            } catch {
                                NSLog("📡 ONVIF subscription re-creation failed: \(error.localizedDescription)")
                            }
                        }
                    }

                    let xml = try await Self.pullMessages(
                        endpoint: pullEndpoint,
                        config: config,
                        password: password,
                        session: session
                    )
                    failureStreak = 0
                    backoffSeconds = 2

                    // Log truncated response for diagnostics
                    let truncated = String(xml.prefix(500))
                    NSLog("📡 ONVIF PullMessages response (\(xml.count) bytes): \(truncated)")

                    let mappedEvents = Self.mapEvents(
                        from: xml,
                        config: config,
                        lastSignature: &lastSignature,
                        lastEventAt: &lastEventAt
                    )

                    if mappedEvents.isEmpty {
                        NSLog("📡 ONVIF: No actionable events in response")
                    }

                    for event in mappedEvents {
                        NSLog("📡 ONVIF event detected: \(event.kind.displayName) from \(event.deviceName)")
                        callbacks.emitEvent(event)
                    }

                    try await Task.sleep(for: .seconds(2))
                } catch {
                    failureStreak += 1
                    NSLog("📡 ONVIF PullMessages error (streak: \(failureStreak)): \(error.localizedDescription)")
                    if failureStreak >= 3 {
                        callbacks.emitFailure(error)
                    }
                    try? await Task.sleep(for: .seconds(backoffSeconds))
                    backoffSeconds = min(backoffSeconds * 2, 30)
                }
            }
        }
        monitoringTask = Task.detached(operation: operation)
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // MARK: - ONVIF SOAP Requests

    /// Creates a PullPoint subscription with the camera's ONVIF event service
    private static func createPullPointSubscription(
        config: TapoSetupConfig,
        password: String,
        session: URLSession
    ) async throws -> URL? {
        guard let endpoint = baseEventURL(config: config) else {
            throw CameraProviderError.onvifUnavailable
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/soap+xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(username: config.username, password: password), forHTTPHeaderField: "Authorization")
        request.httpBody = """
        <?xml version="1.0" encoding="UTF-8"?>
        <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
                    xmlns:tev="http://www.onvif.org/ver10/events/wsdl"
                    xmlns:wsnt="http://docs.oasis-open.org/wsn/b-2">
          <s:Body>
            <tev:CreatePullPointSubscription>
              <tev:InitialTerminationTime>PT60S</tev:InitialTerminationTime>
            </tev:CreatePullPointSubscription>
          </s:Body>
        </s:Envelope>
        """.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CameraProviderError.onvifUnavailable
        }

        let body = String(decoding: data, as: UTF8.self)
        NSLog("📡 ONVIF CreatePullPointSubscription HTTP \(http.statusCode), body: \(String(body.prefix(500)))")

        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw CameraProviderError.authenticationFailed
            }
            throw CameraProviderError.onvifUnavailable
        }

        // Parse subscription endpoint from response
        return parseSubscriptionReference(from: body, config: config)
    }

    /// Renews an active PullPoint subscription to prevent expiry
    private static func renewSubscription(
        endpoint: URL,
        config: TapoSetupConfig,
        password: String,
        session: URLSession
    ) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/soap+xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(username: config.username, password: password), forHTTPHeaderField: "Authorization")
        request.httpBody = """
        <?xml version="1.0" encoding="UTF-8"?>
        <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
                    xmlns:wsnt="http://docs.oasis-open.org/wsn/b-2">
          <s:Body>
            <wsnt:Renew>
              <wsnt:TerminationTime>PT60S</wsnt:TerminationTime>
            </wsnt:Renew>
          </s:Body>
        </s:Envelope>
        """.data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CameraProviderError.onvifUnavailable
        }
    }

    /// Sends PullMessages to the subscription endpoint (or fallback base endpoint)
    private static func pullMessages(
        endpoint: URL?,
        config: TapoSetupConfig,
        password: String,
        session: URLSession
    ) async throws -> String {
        guard let endpoint = endpoint ?? baseEventURL(config: config) else {
            throw CameraProviderError.onvifUnavailable
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/soap+xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(username: config.username, password: password), forHTTPHeaderField: "Authorization")
        request.httpBody = """
        <?xml version="1.0" encoding="UTF-8"?>
        <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tev="http://www.onvif.org/ver10/events/wsdl">
          <s:Body>
            <tev:PullMessages>
              <tev:Timeout>PT5S</tev:Timeout>
              <tev:MessageLimit>10</tev:MessageLimit>
            </tev:PullMessages>
          </s:Body>
        </s:Envelope>
        """.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CameraProviderError.onvifUnavailable
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw CameraProviderError.authenticationFailed
            }
            throw CameraProviderError.onvifUnavailable
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Response Parsing

    /// Extracts the subscription reference URL from ONVIF CreatePullPointSubscription response
    private static func parseSubscriptionReference(from xml: String, config: TapoSetupConfig) -> URL? {
        // Look for <Address> inside <SubscriptionReference>
        let patterns = [
            "Address>",  // Matches <wsa:Address>, <a:Address>, <Address>
        ]

        let lower = xml
        for pattern in patterns {
            guard let startTag = lower.range(of: pattern) else { continue }
            let afterTag = lower[startTag.upperBound...]
            guard let endTag = afterTag.range(of: "</") else { continue }
            let address = String(afterTag[..<endTag.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: address), address.hasPrefix("http") {
                return url
            }
        }

        NSLog("📡 ONVIF: Could not parse subscription reference from response")
        return nil
    }

    // MARK: - Event Mapping

    static func mapEvents(
        from xml: String,
        config: TapoSetupConfig,
        lastSignature: inout String,
        lastEventAt: inout Date
    ) -> [CameraEvent] {
        let lower = xml.lowercased()
        var kinds: [CameraEventKind] = []

        if containsPositiveSignal(keywords: ["person", "human", "people"], in: lower) {
            kinds.append(.person)
        }
        if containsPositiveSignal(keywords: ["motion", "is_motion", "ismotion", "cellmotion"], in: lower) {
            kinds.append(.motion)
        }
        guard !kinds.isEmpty else {
            return []
        }

        // De-dupe bursty pull responses from ONVIF
        let signature = kinds.map(\.rawValue).joined(separator: ",")
        let now = Date()
        if signature == lastSignature && now.timeIntervalSince(lastEventAt) < 4 {
            NSLog("📡 ONVIF: Suppressed duplicate event burst (\(signature))")
            return []
        }
        lastSignature = signature
        lastEventAt = now

        return kinds.map { kind in
            CameraEvent(
                deviceId: config.deviceId,
                deviceName: config.deviceName,
                kind: kind,
                source: "onvif",
                detail: "ONVIF PullPoint event"
            )
        }
    }

    static func containsPositiveSignal(keywords: [String], in text: String) -> Bool {
        for keyword in keywords {
            var searchStart = text.startIndex
            while let range = text.range(of: keyword, range: searchStart..<text.endIndex) {
                let signalEnd = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
                let window = text[range.lowerBound..<signalEnd]
                if window.contains("true") || window.contains(">1<") {
                    return true
                }
                searchStart = range.upperBound
            }
        }
        return false
    }

    // MARK: - Helpers

    private static func baseEventURL(config: TapoSetupConfig) -> URL? {
        URL(string: "http://\(config.host):\(config.onvifPort)/onvif/event_service")
    }

    private static func basicAuthHeader(username: String, password: String) -> String {
        let credentials = "\(username):\(password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}
