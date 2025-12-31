// DesignSystem - open-ring Design Tokens & Components
//
// Usage:
//   import DesignSystem
//
// Colors:
//   Color.Ring.accent, Color.Ring.ring, Color.Ring.motion, Color.Ring.package
//   Color.Semantic.textPrimary, Color.Semantic.hoverBackground
//
// Typography:
//   Font.Ring.title, Font.Ring.headline, Font.Ring.body, Font.Ring.timestamp
//
// Spacing:
//   Spacing.xs (4), Spacing.sm (8), Spacing.md (12), Spacing.lg (16), Spacing.xl (24)
//
// Layout:
//   Layout.Popover.width, Layout.Video.cornerRadius, Layout.Timeline.rowHeight
//
// Components:
//   RingPrimaryButton, RingSecondaryButton, RingIconButton
//   EventIcon, StatusIndicator, LiveBadge

@_exported import SwiftUI

// Re-export all public types
public typealias DS = DesignSystem

public enum DesignSystem {
    public static let version = "0.1.0"
}
