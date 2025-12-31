import SwiftUI
import RingClient
@preconcurrency import WebRTC
import DesignSystem

// MARK: - Multi Stream Video View
// Displays video from pre-established streams, enabling instant camera switching

public struct MultiStreamVideoView: View {
    let device: RingDevice
    let devices: [RingDevice]
    @ObservedObject var streamManager: MultiStreamManager
    var captureHandler: FrameCaptureHandler?
    let onClose: () -> Void
    let onSwitchDevice: (RingDevice) -> Void

    @State private var isMuted = false
    @State private var isTalking = false
    @State private var dragOffset: CGFloat = 0
    @State private var hasVideo = false  // Track video availability for reactivity
    @State private var isHovering = false  // Auto-hide overlay when not hovering

    // Device control states
    @State private var isFloodlightOn = false
    @State private var isSirenActive = false
    @State private var isControlLoading = false  // Show loading during API calls

    // Zoom state
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomOffset: CGSize = .zero
    @State private var lastDragOffset: CGSize = .zero

    // Focus state for keyboard
    @FocusState private var isViewFocused: Bool

    // Zoom limits
    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 4.0

    // Get current device index for indicator dots
    private var currentIndex: Int {
        devices.firstIndex(where: { $0.id == device.id }) ?? 0
    }

    // Check if we can navigate
    private var canGoBack: Bool { currentIndex > 0 }
    private var canGoForward: Bool { currentIndex < devices.count - 1 }

    // Get current video track from stream manager
    private var videoTrack: RTCVideoTrack? {
        streamManager.getVideoTrack(for: device.id)
    }

    // Get current connection state
    private var connectionState: LiveViewSession.State {
        streamManager.getState(for: device.id)
    }

    // Get error message
    private var errorMessage: String? {
        streamManager.getError(for: device.id)
    }

    public var body: some View {
        ZStack {
            // Video background
            Color.black

            // Video content or placeholder with zoom applied
            // Use combined id to force recreation when track becomes available
            if let track = videoTrack {
                WebRTCVideoView(
                    videoTrack: track,
                    isPortrait: device.deviceType == .doorbell,
                    captureHandler: captureHandler
                )
                .scaleEffect(zoomScale)
                .offset(zoomOffset)
                .id("\(device.id)_hasVideo")
                .gesture(zoomPanGesture)
                #if os(macOS)
                .onScrollWheel { delta in
                    // Vertical scroll = zoom
                    if abs(delta.y) > 0.5 {
                        withAnimation(.easeOut(duration: 0.1)) {
                            let zoomDelta = delta.y > 0 ? 0.1 : -0.1
                            zoomScale = min(maxZoom, max(minZoom, zoomScale + zoomDelta))
                            if zoomScale <= 1.0 {
                                zoomOffset = .zero
                                lastDragOffset = .zero
                            }
                        }
                    }
                }
                #endif
            } else {
                connectionPlaceholder
                    .id("\(device.id)_noVideo")
            }

            // Zoom indicator (when zoomed in, auto-hide with overlay)
            if zoomScale > 1.0 {
                zoomIndicator
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
            }

            // Overlay controls (auto-hide when not hovering)
            VStack {
                // Top bar
                topBar

                Spacer()
                    .allowsHitTesting(false)  // Allow touches to pass through to arrows

                // Camera indicator dots
                if devices.count > 1 {
                    cameraIndicatorDots
                        .padding(.bottom, Spacing.sm)
                }

                // Bottom controls
                if videoTrack != nil {
                    bottomControls
                }
            }
            .opacity(isHovering || videoTrack == nil ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)

            // Camera switching arrows (auto-hide when not hovering)
            if devices.count > 1 {
                cameraSwitchingOverlay
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        // Only use swipe gesture when not zoomed (zoom has its own pan gesture)
        .gesture(
            zoomScale == 1.0 ?
            DragGesture(minimumDistance: 50)
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = 0
                    }
                    // Swipe threshold: 50px
                    if value.translation.width < -50 && canGoForward {
                        switchToDevice(at: currentIndex + 1)
                    } else if value.translation.width > 50 && canGoBack {
                        switchToDevice(at: currentIndex - 1)
                    }
                }
            : nil
        )
        // Force view update when streams dictionary changes
        .onChange(of: streamManager.streams.count) { _, _ in
            updateVideoState()
        }
        // Also watch for connecting state changes (which happen before video arrives)
        .onChange(of: streamManager.isConnecting) { _, _ in
            updateVideoState()
        }
        .onAppear {
            hasVideo = streamManager.hasVideoTrack(for: device.id)
            // Set this device as active for audio
            streamManager.setActiveDevice(device.id)
            // Auto-focus on appear for keyboard navigation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isViewFocused = true
            }
        }
        // Reset zoom and switch audio when changing devices
        .onChange(of: device.id) { _, newId in
            withAnimation(.easeOut(duration: 0.2)) {
                zoomScale = 1.0
                zoomOffset = .zero
            }
            // Switch audio to the new device
            streamManager.setActiveDevice(newId)
        }
        // Periodic check for video track (backup for cases where onChange doesn't fire)
        .task(id: device.id) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                let nowHasVideo = streamManager.hasVideoTrack(for: device.id)
                if nowHasVideo != hasVideo {
                    await MainActor.run {
                        hasVideo = nowHasVideo
                        NSLog("📹 MultiStreamVideoView: Video track detected for \(device.name)")
                    }
                }
            }
        }
        // Use hasVideo in id to force view recreation
        .id("\(device.id)_\(hasVideo)")
        // Make focusable with binding for auto-focus
        .focusable()
        .focused($isViewFocused)
        .focusEffectDisabled()
        // Keyboard arrow key support
        .onKeyPress(.leftArrow) {
            if canGoBack {
                NSLog("⬅️ Left arrow KEY pressed")
                switchToDevice(at: currentIndex - 1)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if canGoForward {
                NSLog("➡️ Right arrow KEY pressed")
                switchToDevice(at: currentIndex + 1)
                return .handled
            }
            return .ignored
        }
        // Zoom keyboard shortcuts
        .onKeyPress(.init("+")) {
            zoomIn()
            return .handled
        }
        .onKeyPress(.init("=")) {
            zoomIn()
            return .handled
        }
        .onKeyPress(.init("-")) {
            zoomOut()
            return .handled
        }
        .onKeyPress(.init("0")) {
            resetZoom()
            return .handled
        }
        // Cmd+1/2/3/4 to switch cameras directly (via modifier to reduce type-check complexity)
        .cameraSwitchingShortcuts(devices: devices) { index in
            switchToDevice(at: index)
        }
    }

    // MARK: - Camera Switching Overlay

    private var cameraSwitchingOverlay: some View {
        HStack {
            // Left arrow
            if canGoBack {
                arrowButton(direction: .left)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()
                .allowsHitTesting(false)

            // Right arrow
            if canGoForward {
                arrowButton(direction: .right)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
    }

    private enum ArrowDirection { case left, right }

    private func arrowButton(direction: ArrowDirection) -> some View {
        Button {
            let targetIndex = direction == .left ? currentIndex - 1 : currentIndex + 1
            NSLog("🔄 Arrow tapped: \(direction), switching to device \(targetIndex)")
            switchToDevice(at: targetIndex)
        } label: {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.6))
                    .frame(width: 44, height: 44)

                Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    // MARK: - Camera Indicator Dots

    private var cameraIndicatorDots: some View {
        HStack(spacing: 6) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, dev in
                Circle()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .overlay(
                        // Show connecting indicator
                        Group {
                            if streamManager.getState(for: dev.id) == .connecting ||
                               streamManager.getState(for: dev.id) == .creatingOffer ||
                               streamManager.getState(for: dev.id) == .negotiating {
                                Circle()
                                    .stroke(Color.Ring.accent, lineWidth: 1)
                                    .frame(width: 10, height: 10)
                            }
                        }
                    )
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 4)
        .background(.black.opacity(0.3))
        .clipShape(Capsule())
    }

    private func switchToDevice(at index: Int) {
        guard index >= 0 && index < devices.count else { return }
        let newDevice = devices[index]
        onSwitchDevice(newDevice)
    }

    private func updateVideoState() {
        let nowHasVideo = streamManager.hasVideoTrack(for: device.id)
        if nowHasVideo != hasVideo {
            hasVideo = nowHasVideo
            NSLog("📹 MultiStreamVideoView: Video state updated for \(device.name): \(hasVideo)")
        }
    }

    // MARK: - Zoom Functions

    private func zoomIn() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoomScale = min(maxZoom, zoomScale + 0.5)
        }
    }

    private func zoomOut() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoomScale = max(minZoom, zoomScale - 0.5)
            if zoomScale <= 1.0 {
                zoomOffset = .zero
                lastDragOffset = .zero
            }
        }
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoomScale = 1.0
            zoomOffset = .zero
            lastDragOffset = .zero
        }
    }

    // Pan gesture for when zoomed in
    private var zoomPanGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale > 1.0 else { return }
                zoomOffset = CGSize(
                    width: lastDragOffset.width + value.translation.width,
                    height: lastDragOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastDragOffset = zoomOffset
            }
    }

    // MARK: - Push-to-Talk Button

    private var pushToTalkButton: some View {
        ZStack {
            // Pulsing ring when talking
            if isTalking {
                Circle()
                    .stroke(Color.Ring.accent, lineWidth: 3)
                    .frame(width: 66, height: 66)
                    .opacity(isTalking ? 0.5 : 0)
                    .scaleEffect(isTalking ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isTalking)
            }

            // Main button
            Circle()
                .fill(isTalking ? Color.Ring.accent : Color.Ring.accent.opacity(0.8))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: isTalking ? "waveform" : "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .scaleEffect(isTalking ? 1.1 : 1.0)
                .shadow(color: isTalking ? Color.Ring.accent.opacity(0.6) : .clear, radius: 8)
        }
        .animation(.easeInOut(duration: 0.15), value: isTalking)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isTalking {
                        startTalking()
                    }
                }
                .onEnded { _ in
                    stopTalking()
                }
        )
        .help("Hold to talk")
    }

    private func startTalking() {
        isTalking = true
        Task {
            await streamManager.startTalking(for: device.id)
        }
    }

    private func stopTalking() {
        isTalking = false
        Task {
            await streamManager.stopTalking(for: device.id)
        }
    }

    // MARK: - Zoom Indicator

    private var zoomIndicator: some View {
        VStack {
            Spacer()
            HStack {
                // Zoom level badge
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                    Text(String(format: "%.1fx", zoomScale))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6))
                .clipShape(Capsule())

                // Reset zoom button
                Button {
                    resetZoom()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.leading, Spacing.md)
            .padding(.bottom, 100)  // Above bottom controls
        }
    }

    // MARK: - Connection Placeholder

    private var connectionPlaceholder: some View {
        VStack(spacing: Spacing.md) {
            switch connectionState {
            case .idle, .connecting:
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Connecting...")
                    .font(.Ring.body)
                    .foregroundStyle(.white.opacity(0.7))

            case .creatingOffer, .negotiating:
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Establishing stream...")
                    .font(.Ring.body)
                    .foregroundStyle(.white.opacity(0.7))

            case .connected:
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Loading video...")
                    .font(.Ring.body)
                    .foregroundStyle(.white.opacity(0.7))

            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.yellow)

                Text(errorMessage ?? "Connection failed")
                    .font(.Ring.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

            case .disconnected:
                Image(systemName: "video.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.5))

                Text("Disconnected")
                    .font(.Ring.body)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Live badge
            if case .connected = connectionState, videoTrack != nil {
                LiveBadge()
            } else if streamManager.isConnecting {
                // Show connecting badge
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                    Text("CONNECTING")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.8))
                .clipShape(Capsule())
            }

            HStack(spacing: 6) {
                Text(device.name)
                    .font(.Ring.headline)
                    .foregroundStyle(.white)

                // Battery indicator (only for wireless devices)
                if let battery = device.batteryLevel {
                    HStack(spacing: 3) {
                        Image(systemName: batteryIcon(for: battery))
                            .font(.system(size: 12))
                        Text("\(battery)%")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(batteryColor(for: battery))
                }
            }

            Spacer()

            // Device control buttons
            deviceControlButtons

            // Close button
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.95), .black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Battery Helpers

    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 0..<20: return "battery.0percent"
        case 20..<50: return "battery.25percent"
        case 50..<75: return "battery.50percent"
        case 75..<100: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func batteryColor(for level: Int) -> Color {
        switch level {
        case 0..<20: return .red
        case 20..<50: return .orange
        default: return .green
        }
    }

    // MARK: - Device Control Buttons

    private var deviceControlButtons: some View {
        HStack(spacing: 8) {
            // Floodlight button (only for devices with lights)
            if device.hasFloodlight {
                Button {
                    toggleFloodlight()
                } label: {
                    Image(systemName: isFloodlightOn ? "lightbulb.fill" : "lightbulb")
                        .font(.system(size: 14))
                        .foregroundStyle(isFloodlightOn ? .yellow : .white)
                        .frame(width: 28, height: 28)
                        .background(isFloodlightOn ? Color.yellow.opacity(0.3) : .black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isControlLoading)
                .help(isFloodlightOn ? "Turn off light" : "Turn on light")
            }

            // Siren button (only for devices with sirens)
            if device.hasSiren {
                Button {
                    toggleSiren()
                } label: {
                    Image(systemName: isSirenActive ? "speaker.wave.3.fill" : "speaker.wave.2")
                        .font(.system(size: 14))
                        .foregroundStyle(isSirenActive ? .red : .white)
                        .frame(width: 28, height: 28)
                        .background(isSirenActive ? Color.red.opacity(0.3) : .black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isControlLoading)
                .help(isSirenActive ? "Stop siren" : "Activate siren")
            }
        }
    }

    private func toggleFloodlight() {
        isControlLoading = true
        Task {
            do {
                let newState = !isFloodlightOn
                try await RingClient.shared.setFloodlight(deviceId: device.id, enabled: newState)
                await MainActor.run {
                    isFloodlightOn = newState
                    isControlLoading = false
                }
            } catch {
                NSLog("❌ Failed to toggle floodlight: \(error)")
                await MainActor.run {
                    isControlLoading = false
                }
            }
        }
    }

    private func toggleSiren() {
        isControlLoading = true
        Task {
            do {
                let newState = !isSirenActive
                try await RingClient.shared.setSiren(deviceId: device.id, enabled: newState)
                await MainActor.run {
                    isSirenActive = newState
                    isControlLoading = false
                    // Auto-disable siren after 30 seconds (safety)
                    if newState {
                        Task {
                            try? await Task.sleep(nanoseconds: 30_000_000_000)
                            await MainActor.run {
                                if isSirenActive {
                                    isSirenActive = false
                                }
                            }
                        }
                    }
                }
            } catch {
                NSLog("❌ Failed to toggle siren: \(error)")
                await MainActor.run {
                    isControlLoading = false
                }
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: Spacing.md) {
            // Mute incoming audio button
            Button {
                isMuted.toggle()
                streamManager.setMuted(isMuted)
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isMuted ? .white.opacity(0.5) : .white)
                    .frame(width: 40, height: 40)
                    .background(isMuted ? .red.opacity(0.6) : .black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isMuted ? "Unmute" : "Mute")

            // Zoom out button
            Button {
                zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(zoomScale > minZoom ? .white : .white.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(zoomScale <= minZoom)

            Spacer()

            // Push-to-talk button (hold to talk)
            pushToTalkButton

            Spacer()

            // Zoom in button
            Button {
                zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(zoomScale < maxZoom ? .white : .white.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(zoomScale >= maxZoom)

            // Disconnect button
            Button {
                onClose()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6), .black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Scroll Wheel Modifier for macOS Zoom

#if os(macOS)
import AppKit

struct ScrollWheelModifier: ViewModifier {
    let onScroll: (CGPoint) -> Void

    func body(content: Content) -> some View {
        content.overlay(
            ScrollWheelView(onScroll: onScroll)
        )
    }
}

struct ScrollWheelView: NSViewRepresentable {
    let onScroll: (CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

class ScrollWheelNSView: NSView {
    var onScroll: ((CGPoint) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        // Use scrollingDeltaY for smooth scrolling
        let delta = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
        onScroll?(delta)
    }

    // Pass through all mouse events so buttons remain clickable
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil  // This view doesn't handle clicks, only scroll
    }

    override var acceptsFirstResponder: Bool { false }
}

extension View {
    func onScrollWheel(_ action: @escaping (CGPoint) -> Void) -> some View {
        modifier(ScrollWheelModifier(onScroll: action))
    }
}
#endif

// MARK: - Camera Switching Keyboard Shortcuts Modifier

struct CameraSwitchingShortcuts: ViewModifier {
    let devices: [RingDevice]
    let switchToDevice: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(characters: CharacterSet(charactersIn: "1234")) { keyPress in
                // Only handle if Command is pressed
                guard keyPress.modifiers.contains(.command) else {
                    return .ignored
                }

                // Map character to device index
                switch keyPress.characters {
                case "1" where devices.count >= 1:
                    switchToDevice(0)
                    return .handled
                case "2" where devices.count >= 2:
                    switchToDevice(1)
                    return .handled
                case "3" where devices.count >= 3:
                    switchToDevice(2)
                    return .handled
                case "4" where devices.count >= 4:
                    switchToDevice(3)
                    return .handled
                default:
                    return .ignored
                }
            }
    }
}

extension View {
    func cameraSwitchingShortcuts(devices: [RingDevice], switchToDevice: @escaping (Int) -> Void) -> some View {
        modifier(CameraSwitchingShortcuts(devices: devices, switchToDevice: switchToDevice))
    }
}
