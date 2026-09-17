import SwiftUI
import DesignSystem
import RingClient
import AppKit

// MARK: - Pinned Video View

/// Live view shown in the pinned window; keeps its own camera selection
struct PinnedVideoView: View {
    @State var device: RingDevice
    let devices: [RingDevice]
    @ObservedObject var streamManager: MultiStreamManager
    let onClose: () -> Void
    let onDeviceChange: (RingDevice) -> Void

    var body: some View {
        MultiStreamVideoView(
            device: device,
            devices: devices,
            streamManager: streamManager,
            onClose: onClose,
            onSwitchDevice: { newDevice in
                device = newDevice
                onDeviceChange(newDevice)
            }
        )
    }
}

// MARK: - Floating Window Controller

/// Always-on-top window for a pinned camera. Shares the popover's streams, so pinning is instant
/// and the video keeps playing after the popover closes.
@MainActor
public final class FloatingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var streamManager: MultiStreamManager?

    public static let shared = FloatingWindowController()

    private override init() {
        super.init()
    }

    public func show(device: RingDevice, devices: [RingDevice], streamManager: MultiStreamManager) {
        close()

        // Register as a viewer before the popover goes away, so the streams never drop
        streamManager.attach(for: devices)
        self.streamManager = streamManager

        let size = Layout.Video.box(for: streamManager.videoSizes[device.id] ?? .zero)

        // Standard titled window: native drag, resize and close
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(rootView: PinnedVideoView(
            device: device,
            devices: devices,
            streamManager: streamManager,
            onClose: { [weak self] in self?.close() },
            onDeviceChange: { [weak window] in window?.title = $0.name }
        ))
        window.title = device.name
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(
            width: Layout.FloatingWindow.minWidth,
            height: Layout.FloatingWindow.minHeight
        )
        window.delegate = self

        // Position in bottom-right corner
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: screenFrame.maxX - window.frame.width - 20,
                y: screenFrame.minY + 20
            ))
        }

        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    public func close() {
        window?.close()
    }

    // Also runs for the title bar close button
    public func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
        streamManager?.detach()
        streamManager = nil
    }

    public var isVisible: Bool {
        window?.isVisible ?? false
    }
}
