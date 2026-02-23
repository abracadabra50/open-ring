import AVKit
import CameraProviders
import SwiftUI

#if canImport(VLCKitSPM)
import VLCKitSPM
#endif

public struct RtspPlayerView: NSViewRepresentable {
    public let session: RtspPlayerSession

    public init(session: RtspPlayerSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> NSView {
        #if canImport(VLCKitSPM)
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        session.vlcMediaPlayer.drawable = view
        return view
        #else
        let playerView = AVPlayerView()
        playerView.player = session.player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspectFill
        return playerView
        #endif
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        #if canImport(VLCKitSPM)
        session.vlcMediaPlayer.drawable = nsView
        #else
        if let playerView = nsView as? AVPlayerView, playerView.player !== session.player {
            playerView.player = session.player
        }
        #endif
    }
}
