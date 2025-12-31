import SwiftUI
import DesignSystem
import RingClient
import AVKit
@preconcurrency import WebRTC

// MARK: - Live-First Popover View

public struct PopoverView: View {
    let devices: [RingDevice]
    let events: [RingEvent]
    @Binding var selectedDevice: RingDevice?
    let onRefresh: () -> Void

    @State private var showLiveView = true  // Start with live view by default
    @State private var hasAutoStarted = false
    @State private var streamStartId = UUID()  // Force stream restart on popover reopen
    @State private var playbackError: String?
    @State private var playingVideoURL: URL?
    @State private var playingEvent: RingEvent?
    @State private var isLoadingVideo = false
    @StateObject private var streamManager = MultiStreamManager()

    // AI Guard state
    @State private var aiQueryText = ""
    @State private var aiResponse: String = ""
    @State private var isAILoading = false
    @State private var showAIQuery = false
    @State private var hasAnthropicAPIKey = false

    // Drawer state
    @State private var isDrawerExpanded = true
    @AppStorage("drawerExpanded") private var drawerExpandedPref = true

    // Frame capture for live AI analysis
    @StateObject private var frameCaptureHandler = FrameCaptureHandler()

    // Window scale factor (persisted)
    @AppStorage("windowScale") private var windowScale: Double = 1.0
    private let minScale: Double = 0.75
    private let maxScale: Double = 2.0

    // Filter to only cameras and doorbells (not chimes)
    private var videoDevices: [RingDevice] {
        devices.filter { $0.deviceType != .chime }
    }

    public init(
        devices: [RingDevice],
        events: [RingEvent],
        selectedDevice: Binding<RingDevice?>,
        onRefresh: @escaping () -> Void
    ) {
        self.devices = devices
        self.events = events
        self._selectedDevice = selectedDevice
        self.onRefresh = onRefresh
    }

    // Drawer heights
    private let drawerHandleHeight: CGFloat = 28
    private let footerHeight: CGFloat = 36
    private var drawerExpandedHeight: CGFloat {
        // Panel needs: timeline ~50 + video ~120 + input ~50 + response ~120 = 340px max
        // But video only shows when playing, so base is ~220px
        playingVideoURL != nil || isLoadingVideo ? 320 : 200
    }

    // Calculate popover size - use max size (drawer expanded) since MenuBarExtra can't resize
    private var popoverSize: CGSize {
        let scale = CGFloat(windowScale)
        if showLiveView, let device = selectedDevice {
            // Always use expanded drawer height since window can't resize
            let drawerHeight: CGFloat = drawerExpandedHeight

            switch device.deviceType {
            case .doorbell:
                // Portrait doorbell: 340x500 video + drawer + footer
                return CGSize(width: 340 * scale, height: (500 + drawerHeight + footerHeight) * scale)
            case .camera:
                // Landscape camera: 480x270 video + drawer + footer
                return CGSize(width: 480 * scale, height: (270 + drawerHeight + footerHeight) * scale)
            default:
                return CGSize(width: 400 * scale, height: (300 + drawerHeight + footerHeight) * scale)
            }
        } else {
            // Default menu view
            return CGSize(width: 280 * scale, height: 500 * scale)
        }
    }

    // Scale functions
    private func scaleUp() {
        withAnimation(.easeOut(duration: 0.2)) {
            windowScale = min(maxScale, windowScale + 0.25)
        }
    }

    private func scaleDown() {
        withAnimation(.easeOut(duration: 0.2)) {
            windowScale = max(minScale, windowScale - 0.25)
        }
    }

    private func resetScale() {
        withAnimation(.easeOut(duration: 0.2)) {
            windowScale = 1.0
        }
    }

    // Video height (without AI panel, with scale applied)
    private var videoHeight: CGFloat {
        let scale = CGFloat(windowScale)
        guard let device = selectedDevice else { return 400 * scale }
        switch device.deviceType {
        case .doorbell:
            return 500 * scale
        case .camera:
            return 270 * scale
        default:
            return 300 * scale
        }
    }

    public var body: some View {
        ZStack {
            // Background extends beyond safe areas
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if showLiveView, let device = selectedDevice {
                    // Stacked layout: video on top, drawer, then footer
                    VStack(spacing: 0) {
                        // Live video with camera switching
                        MultiStreamVideoView(
                            device: device,
                            devices: videoDevices,
                            streamManager: streamManager,
                            captureHandler: frameCaptureHandler,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showLiveView = false
                                }
                            },
                            onSwitchDevice: { newDevice in
                                selectedDevice = newDevice
                            }
                        )
                        .frame(height: videoHeight)

                        // Collapsible drawer with AI Panel (always shown, but AI requires API key)
                        DrawerPanel(
                            isExpanded: $isDrawerExpanded,
                            expandedHeight: drawerExpandedHeight
                        ) {
                            AIOverlayPanel(
                                queryText: $aiQueryText,
                                response: $aiResponse,
                                isLoading: $isAILoading,
                                playingVideoURL: $playingVideoURL,
                                isLoadingVideo: $isLoadingVideo,
                                events: events,
                                onSubmit: { submitLiveAIQuery() },
                                onCapture: { captureLiveFrame() },
                                onEventTap: { event in playEvent(event) }
                            )
                        }

                        // Footer bar
                        footerBarView
                    }
                    .frame(width: popoverSize.width)
                } else {
                    // Fallback - shouldn't happen in live-first design
                    // Show loading/connecting state
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Loading...")
                            .font(.Ring.body)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, Spacing.md)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: popoverSize.width)
        .animation(.easeInOut(duration: 0.2), value: showLiveView)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isDrawerExpanded)
        .onChange(of: isDrawerExpanded) { _, newValue in
            drawerExpandedPref = newValue
        }
        .task(id: streamStartId) {
            // Start all streams when popover opens (task restarts when streamStartId changes)
            if !videoDevices.isEmpty {
                NSLog("🚀 Starting streams for \(videoDevices.count) devices")
                await streamManager.startAllStreams(for: videoDevices)
            }
        }
        .onAppear {
            // Force stream restart when popover reopens
            streamStartId = UUID()
            showLiveView = true
            hasAutoStarted = true

            // Restore drawer state from preference
            isDrawerExpanded = drawerExpandedPref

            // Check if Anthropic API key is configured
            Task {
                hasAnthropicAPIKey = (try? await KeychainManager.shared.getAnthropicAPIKey()) != nil
            }
        }
        .onChange(of: selectedDevice?.id) { _, newId in
            // If device is newly selected
            if newId != nil {
                showLiveView = true
            }
        }
        .onDisappear {
            // Stop all streams when popover closes
            Task {
                NSLog("👋 Stopping all streams")
                await streamManager.stopAllStreams()
            }
        }
    }

    // MARK: - Footer Bar with Settings, Branding, and Scale Controls

    @ViewBuilder
    private var footerBarView: some View {
            ZStack {
                // App name (absolutely centered)
                Text("open-ring")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))

                // Left/Right controls
                HStack {
                    // Settings button (left)
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings")

                    Spacer()

                    // Scale controls (right)
                    HStack(spacing: 4) {
                        // Scale down button
                        Button { scaleDown() } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(windowScale > minScale ? .white : .white.opacity(0.3))
                                .frame(width: 22, height: 22)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(windowScale <= minScale)

                        // Scale indicator (tap to reset)
                        Button { resetScale() } label: {
                            Text(String(format: "%.0f%%", windowScale * 100))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Click to reset to 100%")

                        // Scale up button
                        Button { scaleUp() } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(windowScale < maxScale ? .white : .white.opacity(0.3))
                                .frame(width: 22, height: 22)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(windowScale >= maxScale)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.4))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(height: footerHeight)
    }

    // MARK: - Live AI Commands

    private func submitLiveAIQuery() {
        guard !aiQueryText.isEmpty && !isAILoading else { return }

        isAILoading = true
        let question = aiQueryText
        let currentEvents = events

        // Route the command using AICommandRouter
        let command = AICommandRouter.route(question)

        Task {
            do {
                let frameData = frameCaptureHandler.captureFrame()
                let result = try await AICommandHandler.shared.execute(
                    command,
                    frameData: frameData,
                    events: currentEvents
                )

                await MainActor.run {
                    switch result {
                    case .text(let text):
                        self.aiResponse = text
                    case .showVideo(let event):
                        self.aiResponse = ""
                        playEvent(event)
                    case .error(let message):
                        self.aiResponse = "⚠️ \(message)"
                    }
                    isAILoading = false
                    aiQueryText = ""  // Clear input after submission
                }
            } catch {
                await MainActor.run {
                    self.aiResponse = "Error: \(error.localizedDescription)"
                    isAILoading = false
                }
            }
        }
    }

    private func captureLiveFrame() {
        guard !isAILoading else { return }

        NSLog("📸 captureLiveFrame: Starting capture")
        NSLog("📸 frameCaptureHandler.isReady: \(frameCaptureHandler.isReady)")
        isAILoading = true

        Task {
            guard let frameData = frameCaptureHandler.captureFrame() else {
                NSLog("📸 captureLiveFrame: No frame data available")
                await MainActor.run {
                    self.aiResponse = "⚠️ No video frame available. Please wait for the stream to start."
                    isAILoading = false
                }
                return
            }

            NSLog("📸 captureLiveFrame: Got frame data, size: \(frameData.count) bytes")

            do {
                NSLog("📸 captureLiveFrame: Sending to VisionAnalyzer...")
                let description = try await VisionAnalyzer.shared.analyze(frameData, prompt: nil)
                NSLog("📸 captureLiveFrame: Got response: \(description.prefix(100))...")
                await MainActor.run {
                    self.aiResponse = description
                    isAILoading = false
                }
            } catch {
                NSLog("📸 captureLiveFrame: Error: \(error.localizedDescription)")
                await MainActor.run {
                    self.aiResponse = "Error: \(error.localizedDescription)"
                    isAILoading = false
                }
            }
        }
    }

    // MARK: - Embedded Video Player

    private func embeddedVideoPlayer(url: URL) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            EmbeddedVideoPlayerView(url: url)
                .frame(width: 500, height: 380)
        }
        .frame(height: 380)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    // MARK: - Event Playback

    private func playEvent(_ event: RingEvent) {
        NSLog("📹 Attempting to play event: \(event.id) (\(event.kind.displayName))")
        isLoadingVideo = true
        playingEvent = event

        Task {
            do {
                let videoURL = try await RingClient.shared.getEventVideoURL(eventId: event.id)
                NSLog("📹 Got video URL: \(videoURL)")
                await MainActor.run {
                    isLoadingVideo = false
                    playingVideoURL = videoURL
                }
            } catch {
                NSLog("❌ Failed to get event video for \(event.id): \(error)")
                await MainActor.run {
                    isLoadingVideo = false
                    playingEvent = nil
                    playbackError = "Failed to load video"
                }
                // Auto-dismiss error after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if playbackError == "Failed to load video" {
                        playbackError = nil
                    }
                }
            }
        }
    }

}

// MARK: - Event Row

struct EventRow: View {
    let event: RingEvent
    let onPlay: (RingEvent) -> Void
    @State private var isHovering = false
    @State private var isLoading = false

    var body: some View {
        Button {
            guard !isLoading else { return }
            onPlay(event)
        } label: {
            HStack(spacing: Spacing.sm) {
                // Event icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.2))
                        .frame(width: 28, height: 28)

                    Image(systemName: iconName)
                        .font(.system(size: 12))
                        .foregroundStyle(iconColor)
                }

                // Event info
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.kind.displayName)
                        .font(.Ring.body)
                        .foregroundStyle(.white)

                    HStack(spacing: 4) {
                        Text(timeString)
                            .font(.Ring.caption)
                            .foregroundStyle(.white.opacity(0.5))

                        if let deviceName = event.deviceName {
                            Text("•")
                                .foregroundStyle(.white.opacity(0.3))
                            Text(deviceName)
                                .font(.Ring.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }

                Spacer()

                // Play button or loading indicator
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else if isHovering {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(isHovering ? .white.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }

    private var iconName: String {
        switch event.kind {
        case .ding: return "bell.fill"
        case .motion: return "figure.walk"
        case .onDemand: return "video.fill"
        }
    }

    private var iconColor: Color {
        switch event.kind {
        case .ding: return Color.Ring.accent
        case .motion: return .yellow
        case .onDemand: return .blue
        }
    }

    private var timeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: event.createdAt, relativeTo: Date())
    }
}

// MARK: - Embedded Video Player View (NSViewRepresentable)

struct EmbeddedVideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = false
        let player = AVPlayer(url: url)
        playerView.player = player
        player.play()
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // No updates needed
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

// MARK: - Preview

#if DEBUG
struct PopoverPreviewWrapper: View {
    @State private var selectedDevice: RingDevice? = nil

    var body: some View {
        PopoverView(
            devices: [],
            events: [],
            selectedDevice: $selectedDevice,
            onRefresh: {}
        )
    }
}

#Preview("Popover - Live") {
    PopoverPreviewWrapper()
        .preferredColorScheme(.dark)
}
#endif
