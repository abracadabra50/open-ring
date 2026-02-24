import Foundation

public enum CameraEventKind: String, Codable, CaseIterable, Sendable {
    case motion
    case person

    public var displayName: String {
        switch self {
        case .motion:
            return "Motion detected"
        case .person:
            return "Person detected"
        }
    }
}

public enum CameraConnectionState: Equatable, Sendable {
    case unconfigured
    case connecting
    case connected
    case offline
    case error(String)
}

public enum CameraStreamProfile: String, Codable, CaseIterable, Sendable {
    case main
    case sub

    public var displayName: String {
        switch self {
        case .main:
            return "Main stream"
        case .sub:
            return "Sub stream"
        }
    }
}

public struct CameraSetupSummary: Codable, Equatable, Sendable {
    public let host: String
    public let username: String
    public let rtspPort: Int
    public let onvifPort: Int
    public let profile: CameraStreamProfile

    public init(
        host: String,
        username: String,
        rtspPort: Int = 554,
        onvifPort: Int = 2020,
        profile: CameraStreamProfile = .main
    ) {
        self.host = host
        self.username = username
        self.rtspPort = rtspPort
        self.onvifPort = onvifPort
        self.profile = profile
    }
}

public struct CameraDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let model: String
    public let host: String
    public let isOnline: Bool
    public let supportsMotionEvents: Bool
    public let supportsPersonEvents: Bool

    public init(
        id: String,
        name: String,
        model: String,
        host: String,
        isOnline: Bool,
        supportsMotionEvents: Bool = true,
        supportsPersonEvents: Bool = true
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.host = host
        self.isOnline = isOnline
        self.supportsMotionEvents = supportsMotionEvents
        self.supportsPersonEvents = supportsPersonEvents
    }
}

public struct CameraEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let deviceId: String
    public let deviceName: String
    public let kind: CameraEventKind
    public let createdAt: Date
    public let source: String
    public let detail: String?

    public init(
        id: String = UUID().uuidString,
        deviceId: String,
        deviceName: String,
        kind: CameraEventKind,
        createdAt: Date = Date(),
        source: String,
        detail: String? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.kind = kind
        self.createdAt = createdAt
        self.source = source
        self.detail = detail
    }
}

public protocol CameraLiveSession: AnyObject, Sendable {
    var id: String { get }
    var streamURL: URL { get }
    var state: CameraConnectionState { get }
    func start() async throws
    func stop() async
}

public protocol CameraProvider: AnyObject, Sendable {
    var id: String { get }
    var displayName: String { get }

    func loadSetupSummary() async throws -> CameraSetupSummary?
    func saveSetup(
        host: String,
        username: String,
        password: String,
        cloudPassword: String,
        profile: CameraStreamProfile,
        rtspPort: Int,
        onvifPort: Int
    ) async throws
    func clearSetup() async throws
    func testConnection(
        host: String,
        username: String,
        password: String,
        cloudPassword: String,
        profile: CameraStreamProfile,
        rtspPort: Int,
        onvifPort: Int
    ) async throws

    func currentConnectionState() async -> CameraConnectionState
    func connect() async throws
    func disconnect() async
    func fetchDevices() async throws -> [CameraDevice]
    func fetchRecentEvents(limit: Int) async throws -> [CameraEvent]
    func startLiveSession(deviceId: String) async throws -> any CameraLiveSession
    func stopLiveSession(deviceId: String) async

    func startEventMonitoring(
        onEvent: @escaping @Sendable (CameraEvent) -> Void,
        onStatusChange: @escaping @Sendable (CameraConnectionState) -> Void
    ) async
    func stopEventMonitoring() async
}

/// Pan/tilt direction for PTZ-capable cameras.
/// Raw values represent the angle passed to the Tapo `movestep` command.
public enum PTZDirection: Int, Sendable {
    case right = 0
    case up = 90
    case left = 180
    case down = 270
}

public enum CameraProviderError: LocalizedError, Sendable {
    case notConfigured
    case authenticationFailed
    case networkUnavailable
    case streamStartFailed
    case onvifUnavailable
    case unsupported(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Camera is not configured yet."
        case .authenticationFailed:
            return "Camera authentication failed. Check username/password."
        case .networkUnavailable:
            return "Camera is unreachable on the local network."
        case .streamStartFailed:
            return "Failed to start RTSP live stream."
        case .onvifUnavailable:
            return "ONVIF event service is unavailable."
        case .unsupported(let message):
            return message
        case .unknown(let message):
            return message
        }
    }
}
