import SwiftUI

// MARK: - Ring Design System Colors (Dark Minimal)

public extension Color {
    /// Ring brand colors - Dark minimal palette
    enum Ring {
        // MARK: - Backgrounds (Pure black based)

        /// Primary background - pure black
        public static let background = Color(hex: "000000")

        /// Secondary background - very dark gray
        public static let backgroundSecondary = Color(hex: "0A0A0A")

        /// Tertiary background
        public static let backgroundTertiary = Color(hex: "141414")

        // MARK: - Surfaces (Cards, containers)

        /// Surface color for cards/overlays
        public static let surface = Color(hex: "1A1A1A")

        /// Surface hover state
        public static let surfaceHover = Color(hex: "252525")

        /// Surface pressed state
        public static let surfacePressed = Color(hex: "2F2F2F")

        // MARK: - Accent (Ring Blue - use sparingly)

        /// Primary accent - Ring Blue #1C96E8
        public static let accent = Color(hex: "1C96E8")

        /// Accent dimmed (for backgrounds)
        public static let accentDim = Color(hex: "1C96E8").opacity(0.15)

        // MARK: - Text

        /// Primary text - white
        public static let textPrimary = Color.white

        /// Secondary text - 60% white
        public static let textSecondary = Color.white.opacity(0.6)

        /// Tertiary text - 30% white
        public static let textTertiary = Color.white.opacity(0.3)

        // MARK: - Borders & Dividers

        /// Subtle border
        public static let border = Color.white.opacity(0.1)

        /// Active/focused border
        public static let borderActive = Color.white.opacity(0.2)

        // MARK: - Event Colors (Muted)

        /// Ring press event - uses accent
        public static let ring = accent

        /// Motion event - subtle gray
        public static let motion = Color.white.opacity(0.5)

        /// Package event - muted green
        public static let package = Color(hex: "30D158").opacity(0.8)

        // MARK: - Status Colors

        /// Error color
        public static let error = Color(hex: "FF453A")

        /// Success color
        public static let success = Color(hex: "30D158")

        /// Warning color
        public static let warning = Color(hex: "FFD60A")

        /// Live indicator - accent
        public static let live = accent

        // MARK: - Overlays

        /// Semi-transparent overlay for controls
        public static let overlay = Color.black.opacity(0.6)

        /// Lighter overlay
        public static let overlayLight = Color.black.opacity(0.4)
    }
}

// MARK: - Semantic Colors

public extension Color {
    enum Semantic {
        /// Primary text color
        public static let textPrimary = Color.primary

        /// Secondary text color (60% opacity)
        public static let textSecondary = Color.secondary

        /// Tertiary text color (30% opacity)
        public static let textTertiary = Color(light: Color.black.opacity(0.3), dark: Color.white.opacity(0.3))

        /// Divider color
        public static let divider = Color(light: Color.black.opacity(0.1), dark: Color.white.opacity(0.1))

        /// Hover background
        public static let hoverBackground = Color(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.08))

        /// Selected background
        public static let selectedBackground = Color.Ring.accent.opacity(0.15)
    }
}

// MARK: - Color Helpers

public extension Color {
    /// Create a color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }

    /// Create adaptive color for light/dark mode
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(dark)
            }
            return NSColor(light)
        })
    }
}

// MARK: - Preview

#if DEBUG
struct ColorsPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backgrounds")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                colorSwatch("Background", Color.Ring.background)
                colorSwatch("Secondary", Color.Ring.backgroundSecondary)
                colorSwatch("Surface", Color.Ring.surface)
                colorSwatch("Hover", Color.Ring.surfaceHover)
            }

            Divider().background(Color.Ring.border)

            Text("Accent & Status")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                colorSwatch("Accent", Color.Ring.accent)
                colorSwatch("Error", Color.Ring.error)
                colorSwatch("Success", Color.Ring.success)
                colorSwatch("Warning", Color.Ring.warning)
            }

            Divider().background(Color.Ring.border)

            Text("Text Colors")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                colorSwatch("Primary", Color.Ring.textPrimary)
                colorSwatch("Secondary", Color.Ring.textSecondary)
                colorSwatch("Tertiary", Color.Ring.textTertiary)
            }
        }
        .padding()
        .frame(width: 500)
        .background(Color.Ring.background)
    }

    func colorSwatch(_ name: String, _ color: Color) -> some View {
        VStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.Ring.border, lineWidth: 1)
                )
                .frame(width: 60, height: 40)
            Text(name)
                .font(.caption)
                .foregroundStyle(Color.Ring.textSecondary)
        }
    }
}

#Preview("Colors - Dark Minimal") {
    ColorsPreview()
        .preferredColorScheme(.dark)
}
#endif
