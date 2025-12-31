import Foundation

// MARK: - Ring API Client

public actor RingClient {
    public static let shared = RingClient()

    // MARK: - API URLs

    private enum API {
        static let oauthToken = "https://oauth.ring.com/oauth/token"
        static let clientsAPI = "https://api.ring.com/clients_api/"
        static let devicesAPI = "https://api.ring.com/devices/v1/"
        static let snapshotsAPI = "https://app-snaps.ring.com/snapshots/"
    }

    // MARK: - State

    public enum AuthState: Sendable, Equatable {
        case unauthenticated
        case requiresTwoFactor(prompt: String)
        case authenticated(email: String)
        case expired
    }

    public private(set) var authState: AuthState = .unauthenticated
    public private(set) var currentEmail: String?

    private var accessToken: String?
    private var accessTokenExpiry: Date?
    private var pendingPassword: String?  // Store password for 2FA flow
    private let keychain = KeychainManager.shared
    private let session: URLSession

    // MARK: - Init

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Authentication

    /// Attempt to restore session from stored refresh token
    public func restoreSession() async throws -> Bool {
        NSLog("🔑 RingClient.restoreSession() called")

        let refreshToken: String?
        do {
            refreshToken = try await keychain.getRefreshToken()
            NSLog("🔑 Got refresh token: \(refreshToken != nil ? "yes (\(refreshToken!.prefix(10))...)" : "nil")")
        } catch {
            NSLog("🔑 Error getting refresh token: \(error)")
            authState = .unauthenticated
            return false
        }

        guard let refreshToken else {
            NSLog("🔑 No refresh token found")
            authState = .unauthenticated
            return false
        }

        do {
            NSLog("🔑 Authenticating with refresh token...")
            let response = try await authenticate(refreshToken: refreshToken)
            NSLog("🔑 Authentication successful!")
            try await storeTokens(response)
            authState = .authenticated(email: currentEmail ?? "Unknown")
            return true
        } catch {
            NSLog("🔑 Authentication failed: \(error)")
            authState = .expired
            return false
        }
    }

    /// Login with email and password
    public func login(email: String, password: String) async throws {
        currentEmail = email
        pendingPassword = password  // Store for 2FA flow

        do {
            let response = try await authenticate(email: email, password: password)
            try await storeTokens(response)
            pendingPassword = nil  // Clear on success
            authState = .authenticated(email: email)
        } catch let error as RingAuthError {
            if case .requiresTwoFactor(let prompt) = error {
                // Keep pendingPassword stored for 2FA submission
                authState = .requiresTwoFactor(prompt: prompt)
            } else {
                pendingPassword = nil  // Clear on other errors
            }
            throw error
        }
    }

    /// Submit 2FA code
    public func submitTwoFactorCode(_ code: String) async throws {
        guard let email = currentEmail else {
            throw RingAuthError.notLoggedIn
        }
        guard let password = pendingPassword else {
            throw RingAuthError.notLoggedIn  // Password should be stored from login attempt
        }

        // Re-authenticate with the 2FA code - Ring API requires password again
        let response = try await authenticate(email: email, password: password, twoFactorCode: code)
        try await storeTokens(response)
        pendingPassword = nil  // Clear after successful auth
        authState = .authenticated(email: email)
    }

    /// Logout and clear tokens
    public func logout() async throws {
        try await keychain.clearAll()
        accessToken = nil
        accessTokenExpiry = nil
        currentEmail = nil
        pendingPassword = nil
        authState = .unauthenticated
    }

    // MARK: - Token Management

    private func storeTokens(_ response: AuthTokenResponse) async throws {
        try await keychain.saveRefreshToken(response.refreshToken)
        try await keychain.saveAccessToken(response.accessToken, expiresIn: response.expiresIn)
        accessToken = response.accessToken
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(response.expiresIn))
    }

    private func getValidAccessToken() async throws -> String {
        // Check if we have a valid cached token
        if let token = accessToken,
           let expiry = accessTokenExpiry,
           expiry > Date().addingTimeInterval(60) { // 1 minute buffer
            return token
        }

        // Try to get from keychain
        if let token = try await keychain.getAccessToken() {
            accessToken = token
            return token
        }

        // Need to refresh
        guard let refreshToken = try await keychain.getRefreshToken() else {
            authState = .unauthenticated
            throw RingAuthError.notLoggedIn
        }

        let response = try await authenticate(refreshToken: refreshToken)
        try await storeTokens(response)
        return response.accessToken
    }

    // MARK: - Auth Request

    private func authenticate(
        email: String? = nil,
        password: String? = nil,
        refreshToken: String? = nil,
        twoFactorCode: String? = nil
    ) async throws -> AuthTokenResponse {
        var body: [String: String] = [
            "client_id": "ring_official_android",
            "scope": "client"
        ]

        if let refreshToken {
            body["grant_type"] = "refresh_token"
            body["refresh_token"] = refreshToken
        } else if let email, let password {
            body["grant_type"] = "password"
            body["username"] = email
            body["password"] = password
        } else {
            throw RingAuthError.invalidCredentials
        }

        var request = URLRequest(url: URL(string: API.oauthToken)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "2fa-support")
        request.setValue(twoFactorCode ?? "", forHTTPHeaderField: "2fa-code")
        request.setValue("android:com.ringapp", forHTTPHeaderField: "User-Agent")

        let hardwareId = try await keychain.getHardwareId()
        request.setValue(hardwareId, forHTTPHeaderField: "hardware_id")

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RingAuthError.networkError
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            return try decoder.decode(AuthTokenResponse.self, from: data)

        case 400:
            // Invalid 2FA code or credentials
            if let errorResponse = try? JSONDecoder().decode(Auth2FAResponse.self, from: data) {
                if errorResponse.error?.contains("Verification Code") == true {
                    throw RingAuthError.invalidTwoFactorCode
                }
            }
            throw RingAuthError.invalidCredentials

        case 412:
            // 2FA required
            let decoder = JSONDecoder()
            if let twoFAResponse = try? decoder.decode(Auth2FAResponse.self, from: data) {
                let prompt: String
                if let state = twoFAResponse.tsvState, let phone = twoFAResponse.phone {
                    prompt = "Enter the code sent to \(phone) via \(state)"
                } else {
                    prompt = "Enter the verification code sent to your phone/email"
                }
                throw RingAuthError.requiresTwoFactor(prompt: prompt)
            }
            throw RingAuthError.requiresTwoFactor(prompt: "Enter verification code")

        case 401:
            throw RingAuthError.invalidCredentials

        case 429:
            throw RingAuthError.rateLimited

        default:
            throw RingAuthError.networkError
        }
    }

    // MARK: - API Requests

    private func apiRequest<T: Decodable>(
        url: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> T {
        let token = try await getValidAccessToken()

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("android:com.ringapp", forHTTPHeaderField: "User-Agent")

        let hardwareId = try await keychain.getHardwareId()
        request.setValue(hardwareId, forHTTPHeaderField: "hardware_id")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RingAPIError.networkError
        }

        print("📡 API \(url) -> \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200...299:
            // Handle empty responses (for PUT commands that return no body)
            if data.isEmpty || (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let empty = EmptyResponse() as? T {
                    return empty
                }
            }

            let decoder = JSONDecoder()
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                print("❌ Decode error: \(error)")
                if let json = String(data: data, encoding: .utf8) {
                    print("📄 Raw response: \(json.prefix(500))")
                }
                throw error
            }

        case 401:
            // Token expired, try to refresh
            authState = .expired
            throw RingAPIError.unauthorized

        case 404:
            throw RingAPIError.notFound

        case 429:
            throw RingAPIError.rateLimited

        default:
            throw RingAPIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Devices

    public func fetchDevices() async throws -> [RingDevice] {
        let response: DevicesResponse = try await apiRequest(
            url: API.clientsAPI + "ring_devices"
        )
        print("📱 Devices breakdown:")
        print("   - Doorbots: \(response.doorbots?.count ?? 0)")
        print("   - Authorized doorbots: \(response.authorizedDoorbots?.count ?? 0)")
        print("   - Stickup cams: \(response.stickupCams?.count ?? 0)")
        print("   - Chimes: \(response.chimes?.count ?? 0)")
        print("   - Total: \(response.allDevices.count)")
        return response.allDevices
    }

    // MARK: - Device Controls

    /// Toggle the floodlight on a device (for devices with floodlights)
    public func setFloodlight(deviceId: Int, enabled: Bool) async throws {
        let endpoint = enabled ? "floodlight_light_on" : "floodlight_light_off"
        let url = API.clientsAPI + "doorbots/\(deviceId)/\(endpoint)"

        let _: EmptyResponse = try await apiRequest(url: url, method: "PUT")
        NSLog("💡 Floodlight \(enabled ? "ON" : "OFF") for device \(deviceId)")
    }

    /// Activate or deactivate the siren on a device
    public func setSiren(deviceId: Int, enabled: Bool) async throws {
        let endpoint = enabled ? "siren_on" : "siren_off"
        let url = API.clientsAPI + "doorbots/\(deviceId)/\(endpoint)"

        let _: EmptyResponse = try await apiRequest(url: url, method: "PUT")
        NSLog("🔊 Siren \(enabled ? "ON" : "OFF") for device \(deviceId)")
    }

    /// Enable or disable motion detection on a device
    public func setMotionDetection(deviceId: Int, enabled: Bool) async throws {
        let url = API.clientsAPI + "doorbots/\(deviceId)"
        let body: [String: Any] = [
            "doorbot": [
                "settings": [
                    "motion_detection_enabled": enabled
                ]
            ]
        ]

        let _: EmptyResponse = try await apiRequest(url: url, method: "PUT", body: body)
        NSLog("👁 Motion detection \(enabled ? "ENABLED" : "DISABLED") for device \(deviceId)")
    }

    // MARK: - Events

    public func fetchEvents(deviceId: Int, limit: Int = 50) async throws -> [RingEvent] {
        let url = API.clientsAPI + "doorbots/\(deviceId)/history?limit=\(limit)"
        // History endpoint returns array directly
        let events: [RingEvent] = try await apiRequest(url: url)
        return events
    }

    public func fetchAllRecentEvents(limit: Int = 50) async throws -> [RingEvent] {
        // Fetch events from all devices and combine them
        let devices = try await fetchDevices()
        var allEvents: [RingEvent] = []

        for device in devices {
            do {
                let url = API.clientsAPI + "doorbots/\(device.id)/history?limit=\(limit)"
                let events: [RingEvent] = try await apiRequest(url: url)
                allEvents.append(contentsOf: events)
            } catch {
                print("⚠️ Failed to fetch events for device \(device.id): \(error)")
                // Continue with other devices
            }
        }

        // Sort by date, newest first
        return allEvents.sorted { $0.createdAt > $1.createdAt }
    }

    /// Get video URL for a specific event
    public func getEventVideoURL(eventId: String) async throws -> URL {
        let token = try await getValidAccessToken()
        let hardwareId = try await keychain.getHardwareId()

        // Download the video directly from the recording endpoint
        let downloadURL = URL(string: API.clientsAPI + "dings/\(eventId)/recording")!
        var request = URLRequest(url: downloadURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("video/mp4", forHTTPHeaderField: "Accept")
        request.setValue("android:com.ringapp", forHTTPHeaderField: "User-Agent")
        request.setValue(hardwareId, forHTTPHeaderField: "hardware_id")

        NSLog("📹 Downloading recording for event: \(eventId)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RingAPIError.networkError
        }

        NSLog("📹 Recording download: status=\(httpResponse.statusCode), bytes=\(data.count)")

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw RingAPIError.unauthorized
            } else if httpResponse.statusCode == 404 {
                throw RingAPIError.recordingNotFound
            }
            throw RingAPIError.serverError(httpResponse.statusCode)
        }

        // Verify we got video data (should start with mp4 header or be > 10KB)
        guard data.count > 10000 else {
            NSLog("❌ Recording too small: \(data.count) bytes")
            throw RingAPIError.recordingNotFound
        }

        // Save to temp file with unique name
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "ring_event_\(eventId).mp4"
        let tempFile = tempDir.appendingPathComponent(filename)

        // Remove existing file if any
        try? FileManager.default.removeItem(at: tempFile)

        try data.write(to: tempFile)
        NSLog("📹 Saved video to: \(tempFile)")

        return tempFile
    }

    // MARK: - Snapshots

    public func getSnapshot(deviceId: Int) async throws -> Data {
        let token = try await getValidAccessToken()
        let hardwareId = try await keychain.getHardwareId()

        let url = URL(string: API.snapshotsAPI + "next/\(deviceId)?extras=force")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Accept")
        request.setValue("android:com.ringapp", forHTTPHeaderField: "User-Agent")
        request.setValue(hardwareId, forHTTPHeaderField: "hardware_id")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RingAPIError.snapshotFailed
        }

        return data
    }
}

// MARK: - Errors

public enum RingAuthError: Error, LocalizedError, Sendable {
    case invalidCredentials
    case requiresTwoFactor(prompt: String)
    case invalidTwoFactorCode
    case notLoggedIn
    case rateLimited
    case networkError

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .requiresTwoFactor(let prompt):
            return prompt
        case .invalidTwoFactorCode:
            return "Invalid verification code"
        case .notLoggedIn:
            return "Not logged in"
        case .rateLimited:
            return "Too many requests. Please wait and try again."
        case .networkError:
            return "Network error. Check your connection."
        }
    }
}

public enum RingAPIError: Error, LocalizedError, Sendable {
    case unauthorized
    case notFound
    case rateLimited
    case serverError(Int)
    case networkError
    case snapshotFailed
    case recordingNotFound

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Session expired. Please log in again."
        case .notFound:
            return "Resource not found"
        case .rateLimited:
            return "Too many requests. Please wait."
        case .recordingNotFound:
            return "Recording not available"
        case .serverError(let code):
            return "Server error (\(code))"
        case .networkError:
            return "Network error"
        case .snapshotFailed:
            return "Failed to get snapshot"
        }
    }
}

// MARK: - Live View

extension RingClient {
    /// Start a live view session for a device
    public func startLiveView(deviceId: Int) async throws -> LiveViewSession {
        let token = try await getValidAccessToken()
        let hardwareId = try await keychain.getHardwareId()

        return LiveViewSession(
            deviceId: deviceId,
            accessToken: token,
            hardwareId: hardwareId
        )
    }
}
