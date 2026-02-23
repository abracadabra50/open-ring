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

        isConnecting = false
    }

    public func stopAllStreams() async {
        guard let provider else { return }
        for (id, info) in streams {
            if info.session != nil {
                await provider.stopLiveSession(deviceId: id)
            }
        }
        streams.removeAll()
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
        } catch {
            var info = streams[device.id] ?? StreamInfo(id: device.id, deviceName: device.name)
            info.state = .error(error.localizedDescription)
            info.error = error.localizedDescription
            streams[device.id] = info
        }
    }
}
