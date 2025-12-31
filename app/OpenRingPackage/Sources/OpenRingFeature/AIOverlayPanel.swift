import SwiftUI
import RingClient
import DesignSystem
import AVKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - AI Overlay Panel
// Bottom panel: Timeline → Video playback → AI input → Response

public struct AIOverlayPanel: View {
    @Binding var queryText: String
    @Binding var response: String
    @Binding var isLoading: Bool
    @Binding var playingVideoURL: URL?
    @Binding var isLoadingVideo: Bool

    let events: [RingEvent]
    let onSubmit: () -> Void
    let onCapture: () -> Void
    let onEventTap: (RingEvent) -> Void

    @FocusState private var isInputFocused: Bool

    public init(
        queryText: Binding<String>,
        response: Binding<String>,
        isLoading: Binding<Bool>,
        playingVideoURL: Binding<URL?>,
        isLoadingVideo: Binding<Bool>,
        events: [RingEvent],
        onSubmit: @escaping () -> Void,
        onCapture: @escaping () -> Void,
        onEventTap: @escaping (RingEvent) -> Void
    ) {
        self._queryText = queryText
        self._response = response
        self._isLoading = isLoading
        self._playingVideoURL = playingVideoURL
        self._isLoadingVideo = isLoadingVideo
        self.events = events
        self.onSubmit = onSubmit
        self.onCapture = onCapture
        self.onEventTap = onEventTap
    }

    public var body: some View {
        VStack(spacing: Spacing.sm) {
            // 1. Event Timeline (always visible at top)
            MiniEventTimeline(
                events: events,
                onEventTap: onEventTap
            )

            // 2. Video playback area (when playing history)
            if isLoadingVideo {
                videoLoadingView
            } else if let videoURL = playingVideoURL {
                historyVideoPlayer(url: videoURL)
            }

            // 3. AI Input Bar
            inputBar

            // 4. Response area (scrollable, when we have a response)
            if !response.isEmpty || isLoading {
                responseArea
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.black)
    }

    // MARK: - Video Loading View

    private var videoLoadingView: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.white)
            Text("Loading video...")
                .font(.Ring.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - History Video Player

    private func historyVideoPlayer(url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onAppear {
                    // Auto-play
                    let player = AVPlayer(url: url)
                    player.play()
                }

            // Overlay buttons
            HStack(spacing: 6) {
                // Save button
                Button {
                    saveVideo(from: url)
                } label: {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Save video")

                // Close button
                Button {
                    playingVideoURL = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.8))
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(6)
        }
    }

    // MARK: - Save Video

    private func saveVideo(from url: URL) {
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.mpeg4Movie, .movie]
        savePanel.nameFieldStringValue = "ring_event_\(dateFormatter.string(from: Date())).mp4"
        savePanel.title = "Save Recording"
        savePanel.message = "Choose a location to save the Ring event recording"

        savePanel.begin { result in
            if result == .OK, let destinationURL = savePanel.url {
                do {
                    // Copy from temp location to user-chosen location
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    NSLog("📥 Saved video to: \(destinationURL.path)")
                } catch {
                    NSLog("❌ Failed to save video: \(error)")
                }
            }
        }
        #endif
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            // AI icon
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Color.Ring.accent)

            // Text input
            TextField("Ask your AI guard...", text: $queryText)
                .textFieldStyle(.plain)
                .font(.Ring.body)
                .foregroundStyle(.white)
                .focused($isInputFocused)
                .onSubmit {
                    if !queryText.isEmpty {
                        onSubmit()
                    }
                }

            // Capture button
            Button {
                onCapture()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Capture and analyze current frame")

            // Submit button
            if !queryText.isEmpty {
                Button {
                    onSubmit()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.Ring.accent)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Response Area (Scrollable)

    private var responseArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if isLoading {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)

                        Text("Thinking...")
                            .font(.Ring.body)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(response)
                        .font(.Ring.body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(Spacing.md)
        }
        .frame(maxHeight: 120)  // Limit height, scrollable
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Event Filter

enum EventFilter: String, CaseIterable {
    case all = "All"
    case ring = "Ring"
    case motion = "Motion"

    var iconName: String {
        switch self {
        case .all: return "bell.fill"
        case .ring: return "bell.badge.fill"
        case .motion: return "figure.walk"
        }
    }
}

// MARK: - Mini Event Timeline

public struct MiniEventTimeline: View {
    let events: [RingEvent]
    let onEventTap: (RingEvent) -> Void

    @State private var selectedFilter: EventFilter = .all

    private var filteredEvents: [RingEvent] {
        switch selectedFilter {
        case .all:
            return events
        case .ring:
            return events.filter { $0.kind == .ding }
        case .motion:
            return events.filter { $0.kind == .motion }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header with filter buttons
            HStack(spacing: Spacing.sm) {
                Text("Events")
                    .font(.Ring.caption)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                // Filter pills
                HStack(spacing: 4) {
                    ForEach(EventFilter.allCases, id: \.self) { filter in
                        FilterPill(
                            filter: filter,
                            isSelected: selectedFilter == filter,
                            count: countForFilter(filter)
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedFilter = filter
                            }
                        }
                    }
                }
            }

            // Horizontal scroll of event items
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if filteredEvents.isEmpty {
                        Text("No \(selectedFilter == .all ? "" : selectedFilter.rawValue.lowercased()) events")
                            .font(.Ring.caption)
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filteredEvents, id: \.id) { event in
                            EventChip(event: event) {
                                onEventTap(event)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func countForFilter(_ filter: EventFilter) -> Int {
        switch filter {
        case .all: return events.count
        case .ring: return events.filter { $0.kind == .ding }.count
        case .motion: return events.filter { $0.kind == .motion }.count
        }
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let filter: EventFilter
    let isSelected: Bool
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Image(systemName: filter.iconName)
                    .font(.system(size: 9))
                if isSelected {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(isSelected ? Color.Ring.accent : .white.opacity(0.5))
            .padding(.horizontal, isSelected ? 8 : 6)
            .padding(.vertical, 4)
            .background(isSelected ? Color.Ring.accent.opacity(0.2) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event Chip (Compact)

private struct EventChip: View {
    let event: RingEvent
    let onTap: () -> Void

    private var label: String {
        switch event.kind {
        case .ding: return "Ring"
        case .motion: return "Motion"
        case .onDemand: return "Live"
        }
    }

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(event.createdAt)
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else {
            return "\(Int(interval / 86400))d"
        }
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                Text(timeAgo)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(event.kind == .ding ? Color.Ring.accent : .white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(event.kind == .ding ? Color.Ring.accent.opacity(0.2) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct AIOverlayPanel_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black

            VStack {
                Spacer()

                AIOverlayPanel(
                    queryText: .constant("Who came today?"),
                    response: .constant("Two people visited today: a delivery person at 2:30 PM and your neighbor at 4:15 PM. The delivery person left a package at the door."),
                    isLoading: .constant(false),
                    playingVideoURL: .constant(nil),
                    isLoadingVideo: .constant(false),
                    events: [],
                    onSubmit: {},
                    onCapture: {},
                    onEventTap: { _ in }
                )
            }
            .padding()
        }
        .frame(width: 340, height: 400)
    }
}
#endif
