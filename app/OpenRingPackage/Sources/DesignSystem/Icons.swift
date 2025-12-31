import SwiftUI

// MARK: - Ring Icon System (SF Symbols)

public enum RingIcon: String {
    // Event types
    case ring = "bell.fill"
    case motion = "figure.walk"
    case package = "shippingbox.fill"

    // Actions
    case live = "video.fill"
    case snooze = "moon.fill"
    case settings = "gearshape"
    case detach = "pip.enter"
    case close = "xmark"
    case camera = "camera.fill"
    case mute = "speaker.slash.fill"
    case unmute = "speaker.wave.2.fill"

    // Status
    case online = "checkmark.circle.fill"
    case offline = "xmark.circle.fill"
    case warning = "exclamationmark.triangle.fill"

    // Navigation
    case chevronRight = "chevron.right"
    case chevronDown = "chevron.down"

    // Misc
    case refresh = "arrow.clockwise"
    case download = "arrow.down.circle"
    case share = "square.and.arrow.up"
    case copy = "doc.on.doc"
    case empty = "tray"

    public var name: String { rawValue }
}

// MARK: - Event Icon View

public struct EventIcon: View {
    public enum EventType {
        case ring
        case motion
        case package

        var icon: RingIcon {
            switch self {
            case .ring: return .ring
            case .motion: return .motion
            case .package: return .package
            }
        }

        var color: Color {
            switch self {
            case .ring: return .Ring.ring
            case .motion: return .Ring.motion
            case .package: return .Ring.package
            }
        }
    }

    private let type: EventType
    private let size: CGFloat

    public init(_ type: EventType, size: CGFloat = Layout.Timeline.iconSize) {
        self.type = type
        self.size = size
    }

    public var body: some View {
        Image(systemName: type.icon.name)
            .font(.system(size: size))
            .foregroundStyle(type.color)
    }
}

// MARK: - Status Indicator

public struct StatusIndicator: View {
    public enum Status {
        case live
        case online
        case offline
        case warning

        var color: Color {
            switch self {
            case .live: return .Ring.live
            case .online: return .Ring.success
            case .offline: return .Ring.motion
            case .warning: return .Ring.error
            }
        }
    }

    private let status: Status
    private let size: CGFloat
    @State private var isPulsing = false

    public init(_ status: Status, size: CGFloat = 8) {
        self.status = status
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .scaleEffect(status == .live && isPulsing ? 1.1 : 1.0)
            .opacity(status == .live && isPulsing ? 0.8 : 1.0)
            .onAppear {
                if status == .live {
                    withAnimation(
                        .easeInOut(duration: RingAnimation.pulseDuration)
                        .repeatForever(autoreverses: true)
                    ) {
                        isPulsing = true
                    }
                }
            }
    }
}

// MARK: - Live Badge

public struct LiveBadge: View {
    public init() {}

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            StatusIndicator(.live)
            Text("LIVE")
                .font(.Ring.mono)
                .foregroundStyle(Color.Ring.live)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.Ring.live.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#if DEBUG
struct IconsPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Event Icons")
                .font(.headline)

            HStack(spacing: Spacing.lg) {
                VStack {
                    EventIcon(.ring)
                    Text("Ring").font(.caption)
                }
                VStack {
                    EventIcon(.motion)
                    Text("Motion").font(.caption)
                }
                VStack {
                    EventIcon(.package)
                    Text("Package").font(.caption)
                }
            }

            Divider()

            Text("Status Indicators")
                .font(.headline)

            HStack(spacing: Spacing.lg) {
                HStack(spacing: Spacing.xs) {
                    StatusIndicator(.live)
                    Text("Live")
                }
                HStack(spacing: Spacing.xs) {
                    StatusIndicator(.online)
                    Text("Online")
                }
                HStack(spacing: Spacing.xs) {
                    StatusIndicator(.offline)
                    Text("Offline")
                }
            }
            .font(.caption)

            Divider()

            Text("Live Badge")
                .font(.headline)

            LiveBadge()
        }
        .padding()
        .frame(width: 300)
    }
}

#Preview("Icons") {
    IconsPreview()
}
#endif
