import CameraDomain
import Foundation

public struct TapoSetupConfig: Codable, Equatable, Sendable {
    public let host: String
    public let username: String
    public let profile: CameraStreamProfile
    public let rtspPort: Int
    public let onvifPort: Int

    public init(
        host: String,
        username: String,
        profile: CameraStreamProfile = .main,
        rtspPort: Int = 554,
        onvifPort: Int = 2020
    ) {
        self.host = host
        self.username = username
        self.profile = profile
        self.rtspPort = rtspPort
        self.onvifPort = onvifPort
    }

    public var deviceId: String {
        "tapo-c220-\(host)"
    }

    public var deviceName: String {
        "Tapo C220"
    }

    public var streamPath: String {
        switch profile {
        case .main:
            return "stream1"
        case .sub:
            return "stream2"
        }
    }

    public var rtspURL: URL? {
        URL(string: "rtsp://\(host):\(rtspPort)/\(streamPath)")
    }

    public var setupSummary: CameraSetupSummary {
        CameraSetupSummary(
            host: host,
            username: username,
            rtspPort: rtspPort,
            onvifPort: onvifPort,
            profile: profile
        )
    }
}

enum TapoConfigStore {
    private static let configKey = "tapo.setup.config"

    static func load() -> TapoSetupConfig? {
        guard let data = UserDefaults.standard.data(forKey: configKey) else {
            return nil
        }
        return try? JSONDecoder().decode(TapoSetupConfig.self, from: data)
    }

    static func save(_ config: TapoSetupConfig) throws {
        let data = try JSONEncoder().encode(config)
        UserDefaults.standard.set(data, forKey: configKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: configKey)
    }
}
