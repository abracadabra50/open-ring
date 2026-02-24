import CameraDomain
import Foundation

/// Sends one-shot control commands (privacy mode, PTZ) to the Tapo camera.
///
/// Maintains its own independent auth session so command `seq` counters
/// never collide with the event-polling loop in `TapoHttpEventMonitor`.
final class TapoCommandService {
    private let config: TapoSetupConfig
    private let password: String

    private var authState: TapoAuthState?
    private let session: URLSession

    init(config: TapoSetupConfig, password: String) {
        self.config = config
        self.password = password

        let delegate = TapoCommandSessionDelegate()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 10
        sessionConfig.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Privacy Mode (Lens Mask)

    /// Sets the camera's privacy mode (lens mask) on or off.
    ///
    /// pytapo method: `setLensMaskConfig`
    /// Payload: `{"lens_mask": {"lens_mask_info": {"enabled": "on"/"off"}}}`
    func setPrivacyMode(enabled: Bool) async throws {
        let payload: [String: Any] = [
            "method": "setLensMaskConfig",
            "params": [
                "lens_mask": [
                    "lens_mask_info": [
                        "enabled": enabled ? "on" : "off"
                    ]
                ]
            ]
        ]

        let (data, _) = try await sendCommand(payload)
        try validateResponse(data, context: "setPrivacyMode")
    }

    /// Queries the current privacy mode (lens mask) state.
    ///
    /// pytapo method: `getLensMaskConfig`
    /// Payload: `{"lens_mask": {"name": ["lens_mask_info"]}}`
    func getPrivacyMode() async throws -> Bool {
        let payload: [String: Any] = [
            "method": "getLensMaskConfig",
            "params": [
                "lens_mask": [
                    "name": ["lens_mask_info"]
                ]
            ]
        ]

        let (data, _) = try await sendCommand(payload)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let lensMask = result["lens_mask"] as? [String: Any],
              let info = lensMask["lens_mask_info"] as? [String: Any],
              let enabled = info["enabled"] as? String else {
            throw TapoHttpError.requestFailed("Failed to parse privacy mode response")
        }

        return enabled == "on"
    }

    // MARK: - Pan / Tilt

    /// Moves the camera motor one step in the given direction.
    ///
    /// pytapo method: `DO` with `motor.movestep`
    /// Payload: `{"method": "do", "motor": {"movestep": {"direction": "<angle>"}}}`
    func moveMotorStep(direction: PTZDirection) async throws {
        let payload: [String: Any] = [
            "method": "do",
            "motor": [
                "movestep": [
                    "direction": String(direction.rawValue)
                ]
            ]
        ]

        let (data, _) = try await sendCommand(payload)
        try validateResponse(data, context: "moveMotorStep(\(direction))")
    }

    /// Moves the camera motor to an absolute x/y position.
    ///
    /// pytapo method: `DO` with `motor.move`
    /// Payload: `{"method": "do", "motor": {"move": {"x_coord": "<x>", "y_coord": "<y>"}}}`
    func moveMotor(x: Int, y: Int) async throws {
        let payload: [String: Any] = [
            "method": "do",
            "motor": [
                "move": [
                    "x_coord": String(x),
                    "y_coord": String(y)
                ]
            ]
        ]

        let (data, _) = try await sendCommand(payload)
        try validateResponse(data, context: "moveMotor(\(x),\(y))")
    }

    // MARK: - Internal

    /// Authenticates if needed, then sends the command via `TapoAuthenticator.sendRequest`.
    private func sendCommand(_ payload: [String: Any]) async throws -> (Data, URLResponse) {
        if authState == nil {
            authState = try await TapoAuthenticator.authenticate(
                config: config,
                password: password,
                session: session
            )
            NSLog("🎮 TapoCommand: Authenticated (mode: \(authState!.isSecure ? "secure" : "simple"))")
        }

        let host = "\(config.host):443"
        guard let url = URL(string: "https://\(host)/stok=\(authState!.stok)/ds") else {
            throw TapoHttpError.requestFailed("Invalid command URL")
        }

        do {
            return try await TapoAuthenticator.sendRequest(
                url: url,
                payload: payload,
                auth: &authState!,
                session: session
            )
        } catch let error as TapoHttpError where error.isAuthError {
            // Session expired — re-authenticate once and retry
            NSLog("🎮 TapoCommand: Auth expired, re-authenticating...")
            authState = try await TapoAuthenticator.authenticate(
                config: config,
                password: password,
                session: session
            )
            guard let retryURL = URL(string: "https://\(host)/stok=\(authState!.stok)/ds") else {
                throw TapoHttpError.requestFailed("Invalid command URL after re-auth")
            }
            return try await TapoAuthenticator.sendRequest(
                url: retryURL,
                payload: payload,
                auth: &authState!,
                session: session
            )
        }
    }

    /// Validates a Tapo API response, checking for error codes.
    private func validateResponse(_ data: Data, context: String) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("🎮 TapoCommand: \(context) — non-JSON response")
            return
        }

        if let errorCode = json["error_code"] as? Int {
            if errorCode == -40401 {
                authState = nil
                throw TapoHttpError.stokExpired
            }
            if errorCode != 0 {
                throw TapoHttpError.requestFailed("\(context) failed with error_code \(errorCode)")
            }
        }

        NSLog("🎮 TapoCommand: \(context) succeeded")
    }
}

/// URLSession delegate that trusts self-signed certificates for local camera communication.
private final class TapoCommandSessionDelegate: NSObject, URLSessionDelegate {
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
