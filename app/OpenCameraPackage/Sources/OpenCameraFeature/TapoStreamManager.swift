import CameraDomain
import CameraProviders
import Foundation

@MainActor
public final class TapoStreamManager: ObservableObject {
    public struct StreamInfo: Identifiable {
        public let id: String
        public let deviceName: String
        public var session: RtspPlayerSession?
        public var state: CameraConnectionState = .connecting
        public var error: String?
    }

    @Published public var streams: [String: StreamInfo] = [:]
    @Published public var isConnecting = false
    @Published public private(set) var isMuted = true
    @Published public private(set) var activeDeviceId: String?

    private var provider: (any CameraProvider)?

    public init() {}

    public func configure(provider: any CameraProvider) {
        self.provider = provider
    }

    public func startAllStreams(for devices: [CameraDevice]) async {
        guard let provider else { return }
        guard !devices.isEmpty else { return }

        isConnecting = true
        for device in devices {
            streams[device.id] = StreamInfo(id: device.id, deviceName: device.name)
        }

        for device in devices {
            await startStream(device, provider: provider)
        }

        applyAudioPolicy()
        isConnecting = false
    }

    public func stopAllStreams() async {
        isMuted = true
        activeDeviceId = nil

        guard let provider else {
            streams.removeAll()
            return
        }

        for (deviceId, info) in streams {
            if info.session != nil {
                await provider.stopLiveSession(deviceId: deviceId)
            }
        }
        streams.removeAll()
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        applyAudioPolicy()
    }

    public func setActiveDevice(_ deviceId: String?) {
        activeDeviceId = deviceId
        applyAudioPolicy()
    }

    public func session(for deviceId: String) -> RtspPlayerSession? {
        streams[deviceId]?.session
    }

    public func state(for deviceId: String) -> CameraConnectionState {
        streams[deviceId]?.state ?? .connecting
    }

    public func error(for deviceId: String) -> String? {
        streams[deviceId]?.error
    }

    private func startStream(_ device: CameraDevice, provider: any CameraProvider) async {
        do {
            var info = streams[device.id] ?? StreamInfo(id: device.id, deviceName: device.name)
            info.state = .connecting
            streams[device.id] = info

            let liveSession = try await provider.startLiveSession(deviceId: device.id)
            guard let session = liveSession as? RtspPlayerSession else {
                throw CameraProviderError.streamStartFailed
            }

            info.session = session
            info.state = .connected
            streams[device.id] = info
            applyAudioPolicy()
        } catch {
            var info = streams[device.id] ?? StreamInfo(id: device.id, deviceName: device.name)
            info.state = .error(error.localizedDescription)
            info.error = error.localizedDescription
            streams[device.id] = info
        }
    }

    nonisolated static func resolvedMutedStates(
        deviceIds: [String],
        isMuted: Bool,
        activeDeviceId: String?
    ) -> [String: Bool] {
        if isMuted {
            return Dictionary(uniqueKeysWithValues: deviceIds.map { ($0, true) })
        }

        guard let activeDeviceId else {
            return Dictionary(uniqueKeysWithValues: deviceIds.map { ($0, true) })
        }

        return Dictionary(uniqueKeysWithValues: deviceIds.map { ($0, $0 != activeDeviceId) })
    }

    private func applyAudioPolicy() {
        let mutedByDeviceId = Self.resolvedMutedStates(
            deviceIds: Array(streams.keys),
            isMuted: isMuted,
            activeDeviceId: activeDeviceId
        )

        for (deviceId, info) in streams {
            guard let session = info.session, let muted = mutedByDeviceId[deviceId] else { continue }
            session.setMuted(muted)
        }
    }
}
