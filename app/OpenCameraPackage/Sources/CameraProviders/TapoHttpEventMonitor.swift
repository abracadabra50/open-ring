import CameraDomain
import CommonCrypto
import Foundation

/// Event monitor that uses the Tapo camera's proprietary HTTP API to poll for detection events.
/// Implements the secure nonce-based authentication protocol used by newer Tapo firmware.
final class TapoHttpEventMonitor {
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

        let callbacks = TapoHttpCallbacks(onEvent: onEvent, onFailureThreshold: onFailureThreshold)
        let operation: @Sendable () async -> Void = { [config, password, callbacks] in
            var failureStreak = 0
            var backoffSeconds = 2
            var lastSeenTimestamp: Int = 0

            let delegate = TapoInsecureSessionDelegate()
            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.timeoutIntervalForRequest = 10
            sessionConfig.timeoutIntervalForResource = 15
            let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)

            var authState: TapoAuthState?

            while !Task.isCancelled {
                do {
                    // Authenticate if needed
                    if authState == nil {
                        authState = try await TapoAuthenticator.authenticate(
                            config: config,
                            password: password,
                            session: session
                        )
                        NSLog("📡 Tapo HTTP: Authenticated (mode: \(authState!.isSecure ? "secure" : "simple"), stok acquired)")
                    }

                    guard let auth = authState else {
                        throw TapoHttpError.authFailed("No auth state available")
                    }

                    let events = try await Self.pollDetectionList(
                        config: config,
                        auth: auth,
                        session: session,
                        lastSeenTimestamp: lastSeenTimestamp
                    )

                    failureStreak = 0
                    backoffSeconds = 2

                    if events.isEmpty {
                        NSLog("📡 Tapo HTTP: No new detection events")
                    }

                    for event in events {
                        NSLog("📡 Tapo HTTP: \(event.cameraEvent.kind.displayName) at \(event.cameraEvent.deviceName)")
                        callbacks.emitEvent(event.cameraEvent)
                        if event.startTime > lastSeenTimestamp {
                            lastSeenTimestamp = event.startTime
                        }
                    }

                    try await Task.sleep(for: .seconds(5))

                } catch let error as TapoHttpError where error.isAuthError {
                    NSLog("📡 Tapo HTTP: Auth error, will re-authenticate: \(error.localizedDescription)")
                    authState = nil
                    try? await Task.sleep(for: .seconds(2))
                } catch TapoHttpError.temporaryLockout(let secondsRemaining) {
                    NSLog("📡 Tapo HTTP: Camera locked out for \(secondsRemaining)s, waiting...")
                    authState = nil
                    try? await Task.sleep(for: .seconds(secondsRemaining + 5))
                } catch {
                    failureStreak += 1
                    NSLog("📡 Tapo HTTP: Poll error (streak: \(failureStreak)): \(error.localizedDescription)")
                    if failureStreak >= 5 {
                        callbacks.emitFailure(error)
                    }
                    authState = nil
                    try? await Task.sleep(for: .seconds(backoffSeconds))
                    backoffSeconds = min(backoffSeconds * 2, 30)
                }
            }

            session.invalidateAndCancel()
        }
        monitoringTask = Task.detached(operation: operation)
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // MARK: - Event Polling

    /// Polls the camera's detection list for recent motion/person events
    private static func pollDetectionList(
        config: TapoSetupConfig,
        auth: TapoAuthState,
        session: URLSession,
        lastSeenTimestamp: Int
    ) async throws -> [TapoDetectionEvent] {
        let host = "\(config.host):443"
        guard let url = URL(string: "https://\(host)/stok=\(auth.stok)/ds") else {
            throw TapoHttpError.requestFailed("Invalid request URL")
        }

        let now = Int(Date().timeIntervalSince1970)
        let startTime = now - (10 * 60)
        let endTime = now + 60

        let innerPayload: [String: Any] = [
            "method": "multipleRequest",
            "params": [
                "requests": [
                    [
                        "method": "searchDetectionList",
                        "params": [
                            "playback": [
                                "search_detection_list": [
                                    "start_index": 0,
                                    "channel": 0,
                                    "start_time": startTime,
                                    "end_time": endTime,
                                    "end_index": 99
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let (data, _) = try await TapoAuthenticator.sendRequest(
            url: url,
            payload: innerPayload,
            auth: auth,
            session: session
        )

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TapoHttpError.requestFailed("Invalid JSON response")
        }

        if let errorCode = json["error_code"] as? Int, errorCode == -40401 {
            throw TapoHttpError.stokExpired
        }

        return Self.parseDetectionList(from: json, config: config, after: lastSeenTimestamp)
    }

    /// Parses detection events from the searchDetectionList response
    private static func parseDetectionList(
        from json: [String: Any],
        config: TapoSetupConfig,
        after lastSeenTimestamp: Int
    ) -> [TapoDetectionEvent] {
        guard let result = json["result"] as? [String: Any],
              let responses = result["responses"] as? [[String: Any]],
              let firstResponse = responses.first,
              let innerResult = firstResponse["result"] as? [String: Any],
              let playback = innerResult["playback"] as? [String: Any],
              let detections = playback["search_detection_list"] as? [[String: Any]] else {
            NSLog("📡 Tapo HTTP: No detection list in response")
            return []
        }

        var events: [TapoDetectionEvent] = []
        for detection in detections {
            guard let startTime = detection["start_time"] as? Int else { continue }
            guard startTime > lastSeenTimestamp else { continue }

            let eventType = detection["type"] as? String ?? ""
            let kind: CameraEventKind
            if eventType.lowercased().contains("person") || eventType.lowercased().contains("people") {
                kind = .person
            } else {
                kind = .motion
            }

            let event = TapoDetectionEvent(
                cameraEvent: CameraEvent(
                    deviceId: config.deviceId,
                    deviceName: config.deviceName,
                    kind: kind,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(startTime)),
                    source: "tapo-http",
                    detail: "Tapo HTTP API detection (\(eventType))"
                ),
                startTime: startTime
            )
            events.append(event)
        }

        return events
    }
}

// MARK: - Authentication State

/// Holds the session state after successful authentication
struct TapoAuthState {
    let stok: String
    let isSecure: Bool

    // Secure-mode encryption state (nil for simple mode)
    let lsk: Data?
    let ivb: Data?
    var seq: Int?
    let cnonce: String?
    let hashedPassword: String

    /// Standard HTTP headers for Tapo API requests
    var headers: [String: String] {
        var h = [
            "Content-Type": "application/json; charset=UTF-8",
            "User-Agent": "Tapo CameraClient Android",
            "requestByApp": "true"
        ]
        if let seq = seq {
            h["Seq"] = String(seq)
        }
        return h
    }
}

// MARK: - Authenticator

/// Handles the Tapo camera's multi-step authentication protocol
enum TapoAuthenticator {

    /// Authenticates with the camera, handling both simple and secure auth modes
    static func authenticate(
        config: TapoSetupConfig,
        password: String,
        session: URLSession
    ) async throws -> TapoAuthState {
        let host = "\(config.host):443"
        guard let url = URL(string: "https://\(host)") else {
            throw TapoHttpError.authFailed("Invalid host URL")
        }

        let hashedMD5 = TapoCrypto.md5Hash(password).uppercased()
        let hashedSHA256 = TapoCrypto.sha256Hash(password).uppercased()
        let cnonce = TapoCrypto.generateNonce()

        // Step 1: Probe for secure connection by sending encrypt_type=3
        let probePayload: [String: Any] = [
            "method": "login",
            "params": [
                "encrypt_type": "3",
                "username": config.username,
                "cnonce": cnonce
            ]
        ]

        let probeData = try JSONSerialization.data(withJSONObject: probePayload)
        var probeRequest = URLRequest(url: url)
        probeRequest.httpMethod = "POST"
        probeRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        probeRequest.setValue("Tapo CameraClient Android", forHTTPHeaderField: "User-Agent")
        probeRequest.setValue("true", forHTTPHeaderField: "requestByApp")
        probeRequest.httpBody = probeData

        let (probeRespData, _) = try await session.data(for: probeRequest)
        let probeRespStr = String(decoding: probeRespData, as: UTF8.self)
        NSLog("📡 Tapo HTTP: Full probe response: \(probeRespStr)")

        guard let probeJson = try? JSONSerialization.jsonObject(with: probeRespData) as? [String: Any] else {
            throw TapoHttpError.authFailed("Invalid probe response")
        }

        let errorCode = probeJson["error_code"] as? Int ?? 0
        NSLog("📡 Tapo HTTP: Probe response error_code=\(errorCode)")

        // Check for temporary lockout from too many failed attempts
        if let dataObj = probeJson["data"] as? [String: Any],
           let code = dataObj["code"] as? Int,
           code == -40404,
           let secLeft = dataObj["sec_left"] as? Int,
           secLeft > 0 {
            throw TapoHttpError.temporaryLockout(secondsRemaining: secLeft)
        }
        // Also check nested result.data format
        if let result = probeJson["result"] as? [String: Any],
           let dataObj = result["data"] as? [String: Any],
           let secLeft = dataObj["sec_left"] as? Int,
           secLeft > 0 {
            let code = dataObj["code"] as? Int ?? 0
            if code == -40404 {
                throw TapoHttpError.temporaryLockout(secondsRemaining: secLeft)
            }
        }

        // Check if secure auth is supported (error_code -40413 with nonce data)
        let isSecure = errorCode == -40413
            && (probeJson["result"] as? [String: Any])?["data"] != nil

        if isSecure {
            return try await authenticateSecure(
                url: url,
                probeJson: probeJson,
                cnonce: cnonce,
                hashedMD5: hashedMD5,
                hashedSHA256: hashedSHA256,
                config: config,
                session: session
            )
        } else {
            // Simple auth mode: send hashed password directly
            return try await authenticateSimple(
                url: url,
                hashedMD5: hashedMD5,
                config: config,
                session: session
            )
        }
    }

    /// Simple authentication: MD5 hashed password sent directly
    private static func authenticateSimple(
        url: URL,
        hashedMD5: String,
        config: TapoSetupConfig,
        session: URLSession
    ) async throws -> TapoAuthState {
        let loginPayload: [String: Any] = [
            "method": "login",
            "params": [
                "hashed": true,
                "password": hashedMD5,
                "username": config.username
            ]
        ]

        let loginData = try JSONSerialization.data(withJSONObject: loginPayload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Tapo CameraClient Android", forHTTPHeaderField: "User-Agent")
        request.setValue("true", forHTTPHeaderField: "requestByApp")
        request.httpBody = loginData

        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let stok = result["stok"] as? String else {
            throw TapoHttpError.authFailed("Simple auth failed: no stok in response")
        }

        NSLog("📡 Tapo HTTP: Simple auth succeeded")
        return TapoAuthState(
            stok: stok,
            isSecure: false,
            lsk: nil,
            ivb: nil,
            seq: nil,
            cnonce: nil,
            hashedPassword: hashedMD5
        )
    }

    /// Secure authentication: nonce challenge-response with AES-CBC encryption
    private static func authenticateSecure(
        url: URL,
        probeJson: [String: Any],
        cnonce: String,
        hashedMD5: String,
        hashedSHA256: String,
        config: TapoSetupConfig,
        session: URLSession
    ) async throws -> TapoAuthState {
        // Extract nonce and device_confirm from probe response
        guard let result = probeJson["result"] as? [String: Any],
              let responseData = result["data"] as? [String: Any],
              let nonce = responseData["nonce"] as? String,
              let deviceConfirm = responseData["device_confirm"] as? String else {
            throw TapoHttpError.authFailed("Probe response missing nonce/device_confirm")
        }

        NSLog("📡 Tapo HTTP: Received nonce challenge, validating device_confirm")

        // Determine which hash the camera expects (SHA256 or MD5)
        let (hashedPassword, validated) = validateDeviceConfirm(
            cnonce: cnonce,
            nonce: nonce,
            deviceConfirm: deviceConfirm,
            hashedMD5: hashedMD5,
            hashedSHA256: hashedSHA256
        )

        guard validated else {
            throw TapoHttpError.authFailed("device_confirm validation failed — incorrect password")
        }

        // Build digest password for second login
        let digestPasswd = TapoCrypto.sha256Hash(
            string: hashedPassword + cnonce + nonce
        ).uppercased()

        let fullDigest = digestPasswd + cnonce + nonce

        let loginPayload: [String: Any] = [
            "method": "login",
            "params": [
                "cnonce": cnonce,
                "encrypt_type": "3",
                "digest_passwd": fullDigest,
                "username": config.username
            ]
        ]

        let loginData = try JSONSerialization.data(withJSONObject: loginPayload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Tapo CameraClient Android", forHTTPHeaderField: "User-Agent")
        request.setValue("true", forHTTPHeaderField: "requestByApp")
        request.httpBody = loginData

        let (data, _) = try await session.data(for: request)
        let respBody = String(decoding: data, as: UTF8.self)
        NSLog("📡 Tapo HTTP: Secure login response: \(String(respBody.prefix(300)))")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loginResult = json["result"] as? [String: Any],
              let stok = loginResult["stok"] as? String else {
            // Check for user_group error
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let loginResult = json["result"] as? [String: Any],
               let userGroup = loginResult["user_group"] as? String,
               userGroup != "root" {
                throw TapoHttpError.authFailed("Non-root user group: \(userGroup)")
            }
            throw TapoHttpError.authFailed("Secure login failed: no stok in response")
        }

        let startSeq = loginResult["start_seq"] as? Int

        // Generate AES encryption keys from the nonce
        let lsk = TapoCrypto.generateEncryptionToken(
            tokenType: "lsk",
            cnonce: cnonce,
            nonce: nonce,
            hashedPassword: hashedPassword
        )
        let ivb = TapoCrypto.generateEncryptionToken(
            tokenType: "ivb",
            cnonce: cnonce,
            nonce: nonce,
            hashedPassword: hashedPassword
        )

        NSLog("📡 Tapo HTTP: Secure auth succeeded (seq: \(startSeq ?? -1))")
        return TapoAuthState(
            stok: stok,
            isSecure: true,
            lsk: lsk,
            ivb: ivb,
            seq: startSeq,
            cnonce: cnonce,
            hashedPassword: hashedPassword
        )
    }

    /// Validates device_confirm against both MD5 and SHA256 hashes to determine which password encoding to use
    private static func validateDeviceConfirm(
        cnonce: String,
        nonce: String,
        deviceConfirm: String,
        hashedMD5: String,
        hashedSHA256: String
    ) -> (hashedPassword: String, valid: Bool) {
        // Log values for debugging (truncated for security)
        NSLog("📡 Tapo HTTP: validate cnonce=\(cnonce.prefix(8))... nonce=\(nonce.prefix(8))...")
        NSLog("📡 Tapo HTTP: deviceConfirm length=\(deviceConfirm.count), prefix=\(deviceConfirm.prefix(16))...")
        NSLog("📡 Tapo HTTP: hashedSHA256=\(hashedSHA256.prefix(16))...")
        NSLog("📡 Tapo HTTP: hashedMD5=\(hashedMD5.prefix(16))...")

        let sha256Candidate = TapoCrypto.sha256Hash(
            string: cnonce + hashedSHA256 + nonce
        ).uppercased()
        let sha256Expected = sha256Candidate + nonce + cnonce
        NSLog("📡 Tapo HTTP: SHA256 candidate length=\(sha256Expected.count), prefix=\(sha256Expected.prefix(16))...")
        if deviceConfirm == sha256Expected {
            NSLog("📡 Tapo HTTP: SHA256 validation succeeded")
            return (hashedSHA256, true)
        }

        let md5Candidate = TapoCrypto.sha256Hash(
            string: cnonce + hashedMD5 + nonce
        ).uppercased()
        let md5Expected = md5Candidate + nonce + cnonce
        NSLog("📡 Tapo HTTP: MD5 candidate length=\(md5Expected.count), prefix=\(md5Expected.prefix(16))...")
        if deviceConfirm == md5Expected {
            NSLog("📡 Tapo HTTP: MD5 validation succeeded")
            return (hashedMD5, true)
        }

        // Log full comparison for debugging
        NSLog("📡 Tapo HTTP: MISMATCH — deviceConfirm=\(deviceConfirm)")
        NSLog("📡 Tapo HTTP: MISMATCH — sha256Expected=\(sha256Expected)")
        NSLog("📡 Tapo HTTP: MISMATCH — md5Expected=\(md5Expected)")

        return ("", false)
    }

    /// Sends an authenticated request, handling AES encryption for secure connections
    static func sendRequest(
        url: URL,
        payload: [String: Any],
        auth: TapoAuthState,
        session: URLSession
    ) async throws -> (Data, URLResponse) {
        var headers = auth.headers
        headers["Host"] = url.host.map { "\($0):443" }
        headers["Referer"] = "https://\(url.host ?? ""):443"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if auth.isSecure, let lsk = auth.lsk, let ivb = auth.ivb {
            // Encrypt the payload for secure connections
            let plaintext = try JSONSerialization.data(withJSONObject: payload)
            let encrypted = try TapoCrypto.aesEncrypt(data: plaintext, key: lsk, iv: ivb)
            let base64Encrypted = encrypted.base64EncodedString()

            let wrappedPayload: [String: Any] = [
                "method": "securePassthrough",
                "params": [
                    "request": base64Encrypted
                ]
            ]

            // Generate tag for integrity
            if let seq = auth.seq, let cnonce = auth.cnonce {
                let tag = TapoCrypto.generateTag(
                    hashedPassword: auth.hashedPassword,
                    cnonce: cnonce,
                    payload: wrappedPayload,
                    seq: seq
                )
                request.setValue(tag, forHTTPHeaderField: "Tapo_tag")
                request.setValue(String(seq), forHTTPHeaderField: "Seq")
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: wrappedPayload)

            let (data, response) = try await session.data(for: request)

            // Decrypt the response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any],
                  let encryptedResponse = result["response"] as? String,
                  let encryptedData = Data(base64Encoded: encryptedResponse) else {
                // Return raw data if decryption wrapper is not present
                return (data, response)
            }

            let decrypted = try TapoCrypto.aesDecrypt(data: encryptedData, key: lsk, iv: ivb)
            return (decrypted, response)
        } else {
            // Simple mode: send plaintext
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return try await session.data(for: request)
        }
    }
}

// MARK: - Crypto Utilities

enum TapoCrypto {

    /// MD5 hash returning hex string
    static func md5Hash(_ input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// SHA256 hash of a raw string, returning hex
    static func sha256Hash(_ input: String) -> String {
        sha256Hash(string: input)
    }

    /// SHA256 hash from a string, returning hex
    static func sha256Hash(string input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Generates a random 8-byte hex nonce
    static func generateNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// Generates AES encryption/IV tokens from the auth handshake
    static func generateEncryptionToken(
        tokenType: String,
        cnonce: String,
        nonce: String,
        hashedPassword: String
    ) -> Data {
        let hashedKey = sha256Hash(string: cnonce + hashedPassword + nonce).uppercased()
        let combined = tokenType + cnonce + nonce + hashedKey
        let data = Data(combined.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        // Return first 16 bytes for AES-128
        return Data(digest.prefix(16))
    }

    /// Generates the Tapo_tag header for request integrity verification
    static func generateTag(
        hashedPassword: String,
        cnonce: String,
        payload: [String: Any],
        seq: Int
    ) -> String {
        let tag1 = sha256Hash(string: hashedPassword + cnonce).uppercased()
        let payloadStr = (try? String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8)) ?? ""
        let tag2 = sha256Hash(string: tag1 + payloadStr + String(seq)).uppercased()
        return tag2
    }

    /// AES-128-CBC encryption with PKCS7 padding
    static func aesEncrypt(data: Data, key: Data, iv: Data) throws -> Data {
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var numBytesEncrypted: size_t = 0

        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { dataBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, kCCKeySizeAES128,
                        ivBytes.baseAddress,
                        dataBytes.baseAddress, data.count,
                        &buffer, bufferSize,
                        &numBytesEncrypted
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw TapoHttpError.requestFailed("AES encryption failed: \(status)")
        }

        return Data(buffer.prefix(numBytesEncrypted))
    }

    /// AES-128-CBC decryption with PKCS7 unpadding
    static func aesDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var numBytesDecrypted: size_t = 0

        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { dataBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, kCCKeySizeAES128,
                        ivBytes.baseAddress,
                        dataBytes.baseAddress, data.count,
                        &buffer, bufferSize,
                        &numBytesDecrypted
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw TapoHttpError.requestFailed("AES decryption failed: \(status)")
        }

        return Data(buffer.prefix(numBytesDecrypted))
    }
}

// MARK: - Supporting Types

/// Wraps a CameraEvent with the raw Tapo timestamp for watermark tracking
struct TapoDetectionEvent {
    let cameraEvent: CameraEvent
    let startTime: Int
}

/// Error types for Tapo HTTP API communication
enum TapoHttpError: LocalizedError {
    case authFailed(String)
    case stokExpired
    case requestFailed(String)
    case temporaryLockout(secondsRemaining: Int)

    var isAuthError: Bool {
        switch self {
        case .authFailed, .stokExpired:
            return true
        case .requestFailed, .temporaryLockout:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .authFailed(let detail):
            return "Tapo auth failed: \(detail)"
        case .stokExpired:
            return "Tapo session token expired"
        case .requestFailed(let detail):
            return "Tapo request failed: \(detail)"
        case .temporaryLockout(let seconds):
            return "Tapo camera locked out for \(seconds)s"
        }
    }
}

/// Callbacks wrapper for thread-safe event emission
private final class TapoHttpCallbacks: @unchecked Sendable {
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

/// URLSession delegate that trusts self-signed certificates for local camera communication
private final class TapoInsecureSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
