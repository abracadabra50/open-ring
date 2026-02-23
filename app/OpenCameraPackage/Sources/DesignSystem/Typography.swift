import SwiftUI

// MARK: - Ring Typography System

public extension Font {
    enum Ring {
        /// Title - SF Pro 13pt Semibold (popover headers)
        public static let title = Font.system(size: 13, weight: .semibold)

        /// Headline - SF Pro 12pt Medium (section headers)
        public static let headline = Font.system(size: 12, weight: .medium)

        /// Body - SF Pro 12pt Regular (primary text)
        public static let body = Font.system(size: 12, weight: .regular)

        /// Caption - SF Pro 11pt Regular (secondary info)
        public static let caption = Font.system(size: 11, weight: .regular)

        /// Timestamp - SF Mono 11pt Regular (times, IDs)
        public static let timestamp = Font.system(size: 11, weight: .regular, design: .monospaced)

        /// Mono - SF Mono 11pt Medium (device names in events)
        public static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)

        /// Small - SF Pro 10pt Regular (badges, minor labels)
        public static let small = Font.system(size: 10, weight: .regular)
    }
}

// MARK: - Text Styles

public struct RingText: View {
    public enum Style {
        case title
        case headline
        case body
        case caption
        case timestamp
        case mono

        var font: Font {
            switch self {
            case .title: return .Ring.title
            case .headline: return .Ring.headline
            case .body: return .Ring.body
            case .caption: return .Ring.caption
            case .timestamp: return .Ring.timestamp
            case .mono: return .Ring.mono
            }
        }

        var color: Color {
            switch self {
            case .title, .headline, .body, .mono:
                return .Semantic.textPrimary
            case .caption, .timestamp:
                return .Semantic.textSecondary
            }
        }
    }

    private let text: String
    private let style: Style

    public init(_ text: String, style: Style = .body) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .font(style.font)
            .foregroundStyle(style.color)
    }
}

// MARK: - Preview

#if DEBUG
struct TypographyPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Typography Scale")
                .font(.title2)
                .padding(.bottom, 8)

            Group {
                HStack {
                    Text("Title (13pt Semi)")
                        .frame(width: 140, alignment: .leading)
                        .font(.Ring.caption)
                        .foregroundStyle(.secondary)
                    Text("Front Door")
                        .font(.Ring.title)
                }

                HStack {
                    Text("Headline (12pt Med)")
                        .frame(width: 140, alignment: .leading)
                        .font(.Ring.caption)
                        .foregroundStyle(.secondary)
                    Text("Recent Events")
                        .font(.Ring.headline)
                }

                HStack {
                    Text("Body (12pt Reg)")
                        .frame(width: 140, alignment: .leading)
                        .font(.Ring.caption)
                        .foregroundStyle(.secondary)
                    Text("Someone is at the door")
                        .font(.Ring.body)
                }

                HStack {
                    Text("Caption (11pt Reg)")
                        .frame(width: 140, alignment: .leading)
                        .font(.Ring.caption)
                        .foregroundStyle(.secondary)
                    Text("2 minutes ago")
                        .font(.Ring.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Timestamp (Mono)")
                        .frame(width: 140, alignment: .leading)
                        .font(.Ring.caption)
                        .foregroundStyle(.secondary)
                    Text("14:36")
                        .font(.Ring.timestamp)
                }

                HStack {
                    Text("Mono (11pt Med)")
                        .frame(width: 140, alignment: .leading)
                        .font(.Ring.caption)
                        .foregroundStyle(.secondary)
                    Text("RING")
                        .font(.Ring.mono)
                }
            }
        }
        .padding()
        .frame(width: 350)
    }
}

#Preview("Typography") {
    TypographyPreview()
}
#endif
