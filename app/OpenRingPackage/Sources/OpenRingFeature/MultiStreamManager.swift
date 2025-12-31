import Foundation
import RingClient
@preconcurrency import WebRTC

/// Manages multiple simultaneous WebRTC streams for all cameras
@MainActor
public class MultiStreamManager: ObservableObject {

    public struct StreamInfo: Identifiable {
        public let id: Int  // Device ID
        public let deviceName: String
        public var session: LiveViewSession?
        public var videoTrack: RTCVideoTrack?
        public var audioTrack: RTCAudioTrack?
        public var state: LiveViewSession.State = .idle
        public var error: String?
    }

    @Published public var streams: [Int: StreamInfo] = [:]
    @Published public var isConnecting = false
    @Published public var activeDeviceId: Int?  // Currently active device (audio plays from this one)

    private var devices: [RingDevice] = []

    public init() {}

    /// Start streams for all provided devices
    public func startAllStreams(for devices: [RingDevice]) async {
        self.devices = devices
        isConnecting = true

        // Initialize stream info for all devices
        for device in devices {
            streams[device.id] = StreamInfo(
                id: device.id,
                deviceName: device.name
            )
        }

        // Start all streams concurrently
        await withTaskGroup(of: Void.self) { group in
            for device in devices {
                group.addTask {
                    await self.startStream(for: device)
                }
            }
        }

        isConnecting = false
    }

    /// Start a single stream
    private func startStream(for device: RingDevice) async {
        guard var streamInfo = streams[device.id] else { return }

        streamInfo.state = .connecting
        streams[device.id] = streamInfo

        do {
            let session = try await RingClient.shared.startLiveView(deviceId: device.id)

            streamInfo.session = session
            streams[device.id] = streamInfo

            // Set up callbacks
            await session.setCallbacks(
                onStateChange: { [weak self] state in
                    Task { @MainActor in
                        guard let self = self else { return }
                        if var info = self.streams[device.id] {
                            info.state = state
                            if case .failed(let msg) = state {
                                info.error = msg
                            }
                            self.streams[device.id] = info
                        }
                    }
                },
                onVideoTrack: { [weak self] track in
                    Task { @MainActor in
                        guard let self = self else { return }
                        if var info = self.streams[device.id] {
                            info.videoTrack = track
                            self.streams[device.id] = info
                            NSLog("📹 MultiStreamManager: Got video track for \(device.name)")
                        }
                    }
                },
                onAudioTrack: { [weak self] track in
                    Task { @MainActor in
                        guard let self = self else { return }
                        if var info = self.streams[device.id] {
                            info.audioTrack = track
                            // Mute if not the active device
                            let shouldMute = self.activeDeviceId != device.id
                            track.isEnabled = !shouldMute
                            self.streams[device.id] = info
                            NSLog("🔊 MultiStreamManager: Got audio track for \(device.name), muted=\(shouldMute)")
                        }
                    }
                }
            )

            // Start the session
            try await session.start()
            NSLog("📹 MultiStreamManager: Started stream for \(device.name)")

        } catch {
            NSLog("❌ MultiStreamManager: Failed to start stream for \(device.name): \(error)")
            if var info = streams[device.id] {
                info.state = .failed(error.localizedDescription)
                info.error = error.localizedDescription
                streams[device.id] = info
            }
        }
    }

    /// Stop all streams
    public func stopAllStreams() async {
        NSLog("📹 MultiStreamManager: Stopping all streams")
        for (deviceId, streamInfo) in streams {
            if let session = streamInfo.session {
                await session.stop()
            }
            streams[deviceId]?.videoTrack = nil
            streams[deviceId]?.session = nil
        }
        streams.removeAll()
    }

    /// Get video track for a specific device
    public func getVideoTrack(for deviceId: Int) -> RTCVideoTrack? {
        return streams[deviceId]?.videoTrack
    }

    /// Get connection state for a specific device
    public func getState(for deviceId: Int) -> LiveViewSession.State {
        return streams[deviceId]?.state ?? .idle
    }

    /// Get error message for a specific device
    public func getError(for deviceId: Int) -> String? {
        return streams[deviceId]?.error
    }

    /// Check if a device has an active video track
    public func hasVideoTrack(for deviceId: Int) -> Bool {
        return streams[deviceId]?.videoTrack != nil
    }

    // MARK: - Active Device (Audio Control)

    /// Set the active device - only this device's audio will play
    public func setActiveDevice(_ deviceId: Int) {
        guard activeDeviceId != deviceId else { return }

        NSLog("🔊 MultiStreamManager: Switching audio to device \(deviceId)")
        activeDeviceId = deviceId

        // Mute all other devices, unmute the active one
        for (id, streamInfo) in streams {
            if let audioTrack = streamInfo.audioTrack {
                let shouldEnable = (id == deviceId)
                audioTrack.isEnabled = shouldEnable
                NSLog("🔊   Device \(streamInfo.deviceName): audio \(shouldEnable ? "ON" : "OFF")")
            }
        }
    }

    /// Mute/unmute the active device's incoming audio
    public func setMuted(_ muted: Bool) {
        guard let activeId = activeDeviceId,
              let audioTrack = streams[activeId]?.audioTrack else { return }
        audioTrack.isEnabled = !muted
        NSLog("🔊 MultiStreamManager: Active device audio \(muted ? "MUTED" : "UNMUTED")")
    }

    // MARK: - Push-to-Talk

    /// Start talking on a specific device
    public func startTalking(for deviceId: Int) async {
        guard let session = streams[deviceId]?.session else {
            NSLog("🎤 MultiStreamManager: No session for device \(deviceId)")
            return
        }
        await session.startTalking()
    }

    /// Stop talking on a specific device
    public func stopTalking(for deviceId: Int) async {
        guard let session = streams[deviceId]?.session else {
            NSLog("🎤 MultiStreamManager: No session for device \(deviceId)")
            return
        }
        await session.stopTalking()
    }

    /// Check if currently talking on a device
    public func isTalking(for deviceId: Int) async -> Bool {
        guard let session = streams[deviceId]?.session else { return false }
        return await session.isTalking
    }
}
