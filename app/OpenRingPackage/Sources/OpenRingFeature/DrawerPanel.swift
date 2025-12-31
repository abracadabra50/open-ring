import SwiftUI

// MARK: - Drawer Panel
// A collapsible drawer with a dotted drag handle that expands/collapses content

public struct DrawerPanel<Content: View>: View {
    @Binding var isExpanded: Bool
    @GestureState private var dragOffset: CGFloat = 0

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

    // Current visual height based on state and drag
    private var currentHeight: CGFloat {
        let baseHeight = isExpanded ? expandedHeight : handleHeight
        let offset = dragOffset

        // When collapsed, dragging down does nothing
        // When expanded, dragging up does nothing
        if isExpanded {
            // Can only drag down to collapse
            return max(handleHeight, baseHeight + min(0, offset))
        } else {
            // Can only drag up to expand
            return min(expandedHeight, baseHeight - max(0, offset))
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Dotted drag handle
            dottedHandle
                .gesture(dragGesture)

            // Collapsible content
            if isExpanded {
                content()
                    .frame(height: expandedHeight - handleHeight)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(height: currentHeight)
        .clipped()
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: - Dotted Handle

    private var dottedHandle: some View {
        VStack(spacing: 0) {
            // Dots
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle()
                        .fill(.white.opacity(0.4))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.vertical, 10)
        }
        .frame(height: handleHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let threshold: CGFloat = 50

                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if isExpanded {
                        // If expanded and dragged down significantly, collapse
                        if value.translation.height > threshold || velocity > 100 {
                            isExpanded = false
                        }
                    } else {
                        // If collapsed and dragged up significantly, expand
                        if value.translation.height < -threshold || velocity < -100 {
                            isExpanded = true
                        }
                    }
                }
            }
    }
}

// MARK: - Preview

#if DEBUG
struct DrawerPanel_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var isExpanded = false

        var body: some View {
            ZStack {
                Color.black

                VStack {
                    // Simulated video area
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Text("Video Area")
                                .foregroundStyle(.white.opacity(0.5))
                        )

                    // Drawer
                    DrawerPanel(isExpanded: $isExpanded, expandedHeight: 250) {
                        VStack(spacing: 12) {
                            Text("Events Timeline")
                                .foregroundStyle(.white)
                            Text("AI Input Bar")
                                .foregroundStyle(.white.opacity(0.7))
                            Text("Response Area")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.05))
                    }
                }
            }
            .frame(width: 340, height: 500)
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
#endif
