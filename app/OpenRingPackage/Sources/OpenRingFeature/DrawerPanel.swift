import SwiftUI

// MARK: - Drawer Panel
// A collapsible drawer with a 3x3 grid handle and curved bottom edges

public struct DrawerPanel<Content: View>: View {
    @Binding var isExpanded: Bool

    private let handleHeight: CGFloat = 20
    private let expandedHeight: CGFloat
    private let cornerRadius: CGFloat = 16
    private let content: () -> Content

    public init(
        isExpanded: Binding<Bool>,
        expandedHeight: CGFloat = 300,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isExpanded = isExpanded
        self.expandedHeight = expandedHeight
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Curved top edge with handle
            handleArea

            // Content area - only shows when expanded
            if isExpanded {
                content()
                    .frame(height: expandedHeight - handleHeight)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(height: isExpanded ? expandedHeight : handleHeight)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.3))
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cornerRadius,
                style: .continuous
            )
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: - Handle Area with 3x3 Grid

    private var handleArea: some View {
        VStack(spacing: 0) {
            // 3x3 dot grid - compact
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { col in
                            Circle()
                                .fill(.white.opacity(0.5))
                                .frame(width: 3, height: 3)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: handleHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            NSLog("🔔 Drawer handle tapped! Current state: \(isExpanded), toggling...")
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
            NSLog("🔔 Drawer new state: \(isExpanded)")
        }
    }
}

// MARK: - Preview

#if DEBUG
struct DrawerPanel_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var isExpanded = true

        var body: some View {
            ZStack {
                Color.black

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Text("Video Area")
                                .foregroundStyle(.white.opacity(0.5))
                        )

                    DrawerPanel(isExpanded: $isExpanded, expandedHeight: 200) {
                        VStack(spacing: 12) {
                            Text("Events Timeline")
                                .foregroundStyle(.white)
                            Text("AI Input Bar")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.05))
                    }

                    Text("Footer")
                        .frame(height: 36)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 340, height: 600)
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
#endif
