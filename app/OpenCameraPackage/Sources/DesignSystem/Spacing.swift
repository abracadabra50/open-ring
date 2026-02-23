import SwiftUI

// MARK: - Ring Spacing System (4pt grid)

public enum Spacing {
    /// 4pt - tight padding
    public static let xs: CGFloat = 4

    /// 8pt - list item gaps
    public static let sm: CGFloat = 8

    /// 12pt - section padding
    public static let md: CGFloat = 12

    /// 16pt - card padding
    public static let lg: CGFloat = 16

    /// 24pt - major sections
    public static let xl: CGFloat = 24

    /// 32pt - extra large gaps
    public static let xxl: CGFloat = 32
}

// MARK: - Layout Constants

public enum Layout {
    /// Popover dimensions
    public enum Popover {
        public static let width: CGFloat = 400
        public static let maxHeight: CGFloat = 600
        public static let cornerRadius: CGFloat = 12
        public static let padding: CGFloat = Spacing.lg
    }

    /// Video area
    public enum Video {
        public static let aspectRatio: CGFloat = 16 / 9
        public static let cornerRadius: CGFloat = 8
        public static let margin: CGFloat = Spacing.md
    }

    /// Floating window
    public enum FloatingWindow {
        public static let defaultWidth: CGFloat = 480
        public static let defaultHeight: CGFloat = 270
        public static let minWidth: CGFloat = 320
        public static let minHeight: CGFloat = 180
        public static let cornerRadius: CGFloat = 12
        public static let shadowRadius: CGFloat = 40
        public static let shadowOpacity: CGFloat = 0.3
        public static let shadowOffset = CGSize(width: 0, height: -10)
    }

    /// Timeline
    public enum Timeline {
        public static let leftGutter: CGFloat = 48
        public static let iconSize: CGFloat = 16
        public static let rowHeight: CGFloat = 36
        public static let rowGap: CGFloat = 2
    }

    /// Buttons
    public enum Button {
        public static let cornerRadius: CGFloat = 6
        public static let horizontalPadding: CGFloat = Spacing.sm
        public static let verticalPadding: CGFloat = 6
        public static let iconButtonSize: CGFloat = 28
        public static let iconSize: CGFloat = 14
    }

    /// Menubar icon
    public enum MenubarIcon {
        public static let size: CGFloat = 18
    }
}

// MARK: - Animation Constants

public enum RingAnimation {
    /// Default ease timing
    public static let defaultDuration: Double = 0.2

    /// Spring animation for popovers/windows
    public static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Fast fade for hovers
    public static let hoverDuration: Double = 0.15

    /// Live indicator pulse
    public static let pulseDuration: Double = 1.0
}


// MARK: - View Extensions

public extension View {
    /// Apply standard card padding
    func cardPadding() -> some View {
        self.padding(Spacing.lg)
    }

    /// Apply section padding
    func sectionPadding() -> some View {
        self.padding(Spacing.md)
    }

    /// Apply standard corner radius
    func standardCornerRadius() -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: Layout.Popover.cornerRadius))
    }

    /// Apply video corner radius
    func videoCornerRadius() -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: Layout.Video.cornerRadius))
    }
}
