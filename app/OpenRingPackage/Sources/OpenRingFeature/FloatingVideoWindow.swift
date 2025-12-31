import SwiftUI
import DesignSystem
import AppKit

// MARK: - Floating Video Window

public struct FloatingVideoView: View {
    let deviceName: String
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var remainingTime: TimeInterval = 120 // 2 minutes
    @State private var isMuted = true

    public init(deviceName: String, onClose: @escaping () -> Void) {
        self.deviceName = deviceName
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            // Video content (placeholder)
            LinearGradient(
                colors: [Color.black, Color.black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Center play indicator when not live
            Image(systemName: "play.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))

            // Overlay controls
            VStack {
                // Top bar (always visible with live badge)
                topBar

                Spacer()

                // Bottom controls (on hover)
                if isHovering {
                    bottomControls
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Layout.FloatingWindow.cornerRadius))
        .shadow(
            color: .black.opacity(Layout.FloatingWindow.shadowOpacity),
            radius: Layout.FloatingWindow.shadowRadius,
            x: Layout.FloatingWindow.shadowOffset.width,
            y: Layout.FloatingWindow.shadowOffset.height
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: RingAnimation.defaultDuration)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            LiveBadge()

            Spacer()

            // Timer
            Text(timeString)
                .font(.Ring.mono)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(.black.opacity(0.5))
                .clipShape(Capsule())
        }
        .padding(Spacing.md)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack {
            // Device name
            Text(deviceName)
                .font(.Ring.headline)
                .foregroundStyle(.white)

            Spacer()

            // Control buttons
            HStack(spacing: Spacing.sm) {
                // Mute toggle
                Button {
                    isMuted.toggle()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var timeString: String {
        let minutes = Int(remainingTime) / 60
        let seconds = Int(remainingTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Floating Window Controller

@MainActor
public final class FloatingWindowController: NSObject {
    private var window: NSWindow?

    public static let shared = FloatingWindowController()

    private override init() {
        super.init()
    }

    public func show(deviceName: String) {
        if window != nil {
            close()
        }

        let contentView = FloatingVideoView(deviceName: deviceName) { [weak self] in
            self?.close()
        }

        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Layout.FloatingWindow.defaultWidth,
                height: Layout.FloatingWindow.defaultHeight
            ),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.hasShadow = false // We draw our own shadow

        // Set minimum size
        window.minSize = NSSize(
            width: Layout.FloatingWindow.minWidth,
            height: Layout.FloatingWindow.minHeight
        )

        // Position in bottom-right corner
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowOrigin = NSPoint(
                x: screenFrame.maxX - Layout.FloatingWindow.defaultWidth - 20,
                y: screenFrame.minY + 20
            )
            window.setFrameOrigin(windowOrigin)
        }

        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    public func close() {
        window?.close()
        window = nil
    }

    public var isVisible: Bool {
        window?.isVisible ?? false
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Floating Video") {
    FloatingVideoView(deviceName: "Front Door") {}
        .frame(
            width: Layout.FloatingWindow.defaultWidth,
            height: Layout.FloatingWindow.defaultHeight
        )
}
#endif
