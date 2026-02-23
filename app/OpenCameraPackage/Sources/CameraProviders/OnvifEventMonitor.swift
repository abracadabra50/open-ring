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
            sessionConfig.timeoutIntervalForRequest = 6
            sessionConfig.timeoutIntervalForResource = 8
            let session = URLSession(configuration: sessionConfig)
            while !Task.isCancelled {
                do {
                    let xml = try await Self.pullMessages(
                        config: config,
                        password: password,
                        session: session
                    )
                    failureStreak = 0
                    backoffSeconds = 2

                    let mappedEvents = Self.mapEvents(
                        from: xml,
                        config: config,
                        lastSignature: &lastSignature,
                        lastEventAt: &lastEventAt
                    )
                    for event in mappedEvents {
                        callbacks.emitEvent(event)
                    }

                    try await Task.sleep(for: .seconds(2))
                } catch {
                    failureStreak += 1
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

    private static func pullMessages(
        config: TapoSetupConfig,
        password: String,
        session: URLSession
    ) async throws -> String {
        guard let endpoint = URL(string: "http://\(config.host):\(config.onvifPort)/onvif/event_service") else {
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
              <tev:Timeout>PT2S</tev:Timeout>
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

    private static func basicAuthHeader(username: String, password: String) -> String {
        let credentials = "\(username):\(password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private static func mapEvents(
        from xml: String,
        config: TapoSetupConfig,
        lastSignature: inout String,
        lastEventAt: inout Date
    ) -> [CameraEvent] {
        let lower = xml.lowercased()
        var kinds: [CameraEventKind] = []

        if containsPositiveSignal(keywords: ["person", "human"], in: lower) {
            kinds.append(.person)
        }
        if containsPositiveSignal(keywords: ["motion", "is_motion", "ismotion"], in: lower) {
            kinds.append(.motion)
        }
        guard !kinds.isEmpty else {
            return []
        }

        // De-dupe bursty pull responses from ONVIF.
        let signature = kinds.map(\.rawValue).joined(separator: ",")
        let now = Date()
        if signature == lastSignature && now.timeIntervalSince(lastEventAt) < 4 {
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

    private static func containsPositiveSignal(keywords: [String], in text: String) -> Bool {
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
}
