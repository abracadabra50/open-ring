import AVFoundation
import CameraDomain
import Foundation

#if canImport(VLCKitSPM)
import VLCKitSPM
#endif

public final class RtspPlayerSession: CameraLiveSession, @unchecked Sendable {
    public let id: String
    public let streamURL: URL
    public private(set) var state: CameraConnectionState = .connecting
    public private(set) var isMuted: Bool = true

    private let username: String
    private let password: String

    #if canImport(VLCKitSPM)
    private let mediaPlayer = VLCMediaPlayer()
    #else
    private let avPlayer = AVPlayer()
    #endif

    public init(id: String, streamURL: URL, username: String, password: String) {
        self.id = id
        self.streamURL = streamURL
        self.username = username
        self.password = password
    }

    public func start() async throws {
        state = .connecting

        #if canImport(VLCKitSPM)
        let media = VLCMedia(url: streamURL)
        media.addOptions([
            "network-caching": 200,
            "rtsp-user": username,
            "rtsp-pwd": password,
            "clock-jitter": 0,
            "clock-synchro": 0,
        ])
        mediaPlayer.media = media
        setMuted(isMuted)
        mediaPlayer.play()
        setMuted(isMuted)
        state = .connected
        #else
        let item = AVPlayerItem(url: streamURL)
        avPlayer.replaceCurrentItem(with: item)
        setMuted(isMuted)
        avPlayer.play()
        setMuted(isMuted)
        state = .connected
        #endif
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        #if canImport(VLCKitSPM)
        mediaPlayer.audio?.isMuted = muted
        #else
        avPlayer.isMuted = muted
        #endif
    }

    public func stop() async {
        setMuted(true)
        #if canImport(VLCKitSPM)
        mediaPlayer.stop()
        #else
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        #endif
        state = .offline
    }

    #if canImport(VLCKitSPM)
    public var vlcMediaPlayer: VLCMediaPlayer {
        mediaPlayer
    }
    #else
    public var player: AVPlayer {
        avPlayer
    }
    #endif
}
