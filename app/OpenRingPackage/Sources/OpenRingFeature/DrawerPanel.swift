import SwiftUI

// MARK: - Drawer Panel
// A collapsible drawer with a dotted handle - content slides up/down within fixed space

public struct DrawerPanel<Content: View>: View {
    @Binding var isExpanded: Bool

    private let handleHeight: CGFloat = 28
    private let expandedHeight: CGFloat
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
            // Dotted drag handle - always visible
            dottedHandle

            // Content area - fixed height, content slides in/out
            ZStack(alignment: .top) {
                // Always reserve the space
                Color.clear
                    .frame(height: expandedHeight - handleHeight)

                // Content slides in from bottom
                if isExpanded {
                    content()
                        .frame(height: expandedHeight - handleHeight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .frame(height: expandedHeight)
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
    }

    // MARK: - Dotted Handle

    private var dottedHandle: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { _ in
                Circle()
                    .fill(.white.opacity(isExpanded ? 0.4 : 0.6))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(height: handleHeight)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.01)) // Invisible but tappable
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                isExpanded.toggle()
            }
        }
        // Visual cue - rotate dots or show arrow
        .overlay(alignment: .trailing) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.trailing, 12)
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

                    // Footer
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
