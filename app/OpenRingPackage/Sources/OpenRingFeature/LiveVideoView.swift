import SwiftUI
import RingClient
@preconcurrency import WebRTC
import DesignSystem

// MARK: - Live Video View

public struct LiveVideoView: View {
    let device: RingDevice
    let devices: [RingDevice]
    let onClose: () -> Void
    let onSwitchDevice: (RingDevice) -> Void
    var captureHandler: FrameCaptureHandler?

    @State private var liveSession: LiveViewSession?
    @State private var videoTrack: RTCVideoTrack?
    @State private var connectionState: LiveViewSession.State = .idle
    @State private var errorMessage: String?
    @State private var isMuted = false
    @State private var dragOffset: CGFloat = 0

    // Calculate proper dimensions based on device type
    private var viewSize: CGSize {
        switch device.deviceType {
        case .doorbell:
            // Doorbells are portrait - Ring doorbells are typically 9:16 aspect ratio
            // User requested ~600px tall
            return CGSize(width: 340, height: 600)
        case .camera:
            // Cameras are landscape - typically 16:9
            return CGSize(width: 480, height: 270)
        default:
            return CGSize(width: 400, height: 300)
        }
    }

    // Get current device index for indicator dots
    private var currentIndex: Int {
        devices.firstIndex(where: { $0.id == device.id }) ?? 0
    }

    // Check if we can navigate
    private var canGoBack: Bool { currentIndex > 0 }
    private var canGoForward: Bool { currentIndex < devices.count - 1 }

    public init(
        device: RingDevice,
        devices: [RingDevice] = [],
        onClose: @escaping () -> Void,
        onSwitchDevice: @escaping (RingDevice) -> Void = { _ in },
        captureHandler: FrameCaptureHandler? = nil
    ) {
        self.device = device
        self.devices = devices.isEmpty ? [device] : devices
        self.onClose = onClose
        self.onSwitchDevice = onSwitchDevice
        self.captureHandler = captureHandler
    }

    public var body: some View {
        ZStack {
            // Video background
            Color.black

            // Video content or placeholder
            if let track = videoTrack {
                WebRTCVideoView(
                    videoTrack: track,
                    isPortrait: device.deviceType == .doorbell,
                    captureHandler: captureHandler
                )
            } else {
                connectionPlaceholder
            }

            // Camera switching arrows (middle)
            if devices.count > 1 {
                cameraSwitchingOverlay
            }

            // Overlay controls
            VStack {
                // Top bar
                topBar

                Spacer()

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
        }
        .gesture(
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
        )
        .task {
            await startLiveView()
        }
        .onDisappear {
            Task {
                await stopLiveView()
            }
        }
    }

    // MARK: - Camera Switching Overlay

    private var cameraSwitchingOverlay: some View {
        HStack {
            // Left arrow
            if canGoBack {
                Button {
                    switchToDevice(at: currentIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 36)
            }

            Spacer()

            // Right arrow
            if canGoForward {
                Button {
                    switchToDevice(at: currentIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 36)
            }
        }
        .padding(.horizontal, Spacing.sm)
    }

    // MARK: - Camera Indicator Dots

    private var cameraIndicatorDots: some View {
        HStack(spacing: 6) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, _ in
                Circle()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
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
        Task {
            await stopLiveView()
            onSwitchDevice(newDevice)
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

                Button("Try Again") {
                    Task {
                        await startLiveView()
                    }
                }
                .buttonStyle(.bordered)
                .tint(.white)

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
            if case .connected = connectionState {
                LiveBadge()
            }

            Text(device.name)
                .font(.Ring.headline)
                .foregroundStyle(.white)

            Spacer()

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
                colors: [.black.opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: Spacing.lg) {
            // Mute button
            Button {
                isMuted.toggle()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Talk button (hold to talk)
            Button {
                // TODO: Push to talk
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.Ring.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Disconnect button
            Button {
                onClose()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Live View Control

    private func startLiveView() async {
        connectionState = .connecting
        errorMessage = nil

        do {
            let session = try await RingClient.shared.startLiveView(deviceId: device.id)
            self.liveSession = session

            // Set up callbacks using actor method
            await session.setCallbacks(
                onStateChange: { state in
                    Task { @MainActor in
                        self.connectionState = state
                        if case .failed(let msg) = state {
                            self.errorMessage = msg
                        }
                    }
                },
                onVideoTrack: { track in
                    Task { @MainActor in
                        self.videoTrack = track
                    }
                },
                onAudioTrack: { _ in
                    // Audio track received - no special handling needed for single stream
                }
            )

            // Start the session
            try await session.start()

        } catch {
            connectionState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func stopLiveView() async {
        await liveSession?.stop()
        liveSession = nil
        videoTrack = nil
    }
}

// MARK: - Frame Capture Handler

/// Observable handler for capturing frames from live video
@MainActor
public class FrameCaptureHandler: ObservableObject {
    weak var metalView: MetalVideoView?

    public init() {}

    /// Capture the current video frame as JPEG data
    public func captureFrame() -> Data? {
        return metalView?.captureCurrentFrame()
    }

    /// Check if frame capture is available
    public var isReady: Bool {
        metalView != nil
    }
}

// MARK: - WebRTC Video View (NSViewRepresentable with Custom Metal Renderer)

#if os(macOS)
import MetalKit
import CoreVideo
import AppKit

struct WebRTCVideoView: NSViewRepresentable {
    let videoTrack: RTCVideoTrack
    let isPortrait: Bool
    var captureHandler: FrameCaptureHandler?

    func makeNSView(context: Context) -> MetalVideoView {
        let videoView = MetalVideoView(isPortrait: isPortrait)
        NSLog("📹 WebRTCVideoView: Adding coordinator to track, track.isEnabled=\(videoTrack.isEnabled), track.readyState=\(videoTrack.readyState.rawValue), isPortrait=\(isPortrait)")
        videoTrack.isEnabled = true
        videoTrack.add(context.coordinator)
        context.coordinator.metalView = videoView

        // Connect frame capture handler
        if let handler = captureHandler {
            handler.metalView = videoView
        }

        NSLog("📹 WebRTCVideoView: Coordinator added to track")
        return videoView
    }

    func updateNSView(_ nsView: MetalVideoView, context: Context) {
        // Update capture handler reference if needed
        if let handler = captureHandler {
            handler.metalView = nsView
        }
    }

    static func dismantleNSView(_ nsView: MetalVideoView, coordinator: Coordinator) {
        // Clean up is handled automatically
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // Custom coordinator that implements RTCVideoRenderer
    @MainActor
    class Coordinator: NSObject, RTCVideoRenderer {
        weak var metalView: MetalVideoView?
        private var videoSize: CGSize = .zero

        nonisolated func setSize(_ size: CGSize) {
            NSLog("📹 Coordinator.setSize called: \(size)")
            Task { @MainActor in
                self.videoSize = size
                self.metalView?.videoSize = size
            }
        }

        nonisolated func renderFrame(_ frame: RTCVideoFrame?) {
            guard let frame = frame else { return }

            Task { @MainActor in
                NSLog("📹 Coordinator.renderFrame called, size: \(frame.width)x\(frame.height), buffer type: \(type(of: frame.buffer))")
                self.metalView?.renderFrame(frame)
            }
        }
    }
}

// Custom Metal-based video view for rendering WebRTC frames with NV12 YUV support
class MetalVideoView: NSView {
    private var metalLayer: CAMetalLayer?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var nv12PipelineState: MTLRenderPipelineState?
    private var bgraPipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private let isPortrait: Bool

    var videoSize: CGSize = .zero {
        didSet {
            needsLayout = true
        }
    }

    private var currentFrame: RTCVideoFrame?
    private var frameCount = 0

    // MARK: - Frame Capture

    /// Capture the current video frame as JPEG data for AI analysis
    func captureCurrentFrame() -> Data? {
        guard let frame = currentFrame,
              let buffer = frame.buffer as? RTCCVPixelBuffer else {
            NSLog("📸 Frame capture failed: no current frame")
            return nil
        }

        let pixelBuffer = buffer.pixelBuffer
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        // Convert to CIImage
        var ciImage: CIImage

        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            // NV12 YUV format - CIImage handles conversion automatically
            ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        case kCVPixelFormatType_32BGRA:
            // BGRA format - direct
            ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        default:
            NSLog("📸 Frame capture failed: unknown pixel format \(pixelFormat)")
            return nil
        }

        // Apply portrait crop if needed (same as shader)
        if isPortrait {
            let fullWidth = ciImage.extent.width
            let fullHeight = ciImage.extent.height
            // Crop to 9:16 from center (matching shader coordinates)
            let cropWidth = fullWidth * 0.5625 // 0.78125 - 0.21875 = 0.5625
            let cropX = fullWidth * 0.21875
            let cropRect = CGRect(x: cropX, y: 0, width: cropWidth, height: fullHeight)
            ciImage = ciImage.cropped(to: cropRect)
        }

        // Convert to JPEG
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            NSLog("📸 Frame capture failed: couldn't create CGImage")
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            NSLog("📸 Frame capture failed: couldn't create JPEG")
            return nil
        }

        NSLog("📸 Frame captured: \(jpegData.count) bytes, \(Int(ciImage.extent.width))x\(Int(ciImage.extent.height))")
        return jpegData
    }

    init(isPortrait: Bool = false) {
        self.isPortrait = isPortrait
        super.init(frame: .zero)
        setupMetal()
    }

    override init(frame frameRect: NSRect) {
        self.isPortrait = false
        super.init(frame: frameRect)
        setupMetal()
    }

    required init?(coder: NSCoder) {
        self.isPortrait = false
        super.init(coder: coder)
        setupMetal()
    }

    private func setupMetal() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("📹 Metal not available")
            return
        }

        self.device = device
        self.commandQueue = device.makeCommandQueue()

        let metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        self.metalLayer = metalLayer
        self.layer = metalLayer

        // Create texture cache for CVPixelBuffer conversion
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache

        setupPipelines()
    }

    private func setupPipelines() {
        guard let device = device else { return }

        // NV12 YUV to RGB shader - samples both Y and UV planes
        // For portrait mode (doorbells), we crop the 1440x1440 square to 9:16 aspect
        // by sampling only the center portion horizontally

        // Calculate texture coordinates for cropping
        // Portrait 9:16 from 1:1 means X goes from 0.21875 to 0.78125
        let xMin: Float = isPortrait ? 0.21875 : 0.0
        let xMax: Float = isPortrait ? 0.78125 : 1.0

        let nv12ShaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut nv12VertexShader(uint vertexID [[vertex_id]]) {
            float2 positions[4] = {
                float2(-1, -1),
                float2( 1, -1),
                float2(-1,  1),
                float2( 1,  1)
            };
            // Texture coordinates - crop horizontally for portrait mode
            // X: \(xMin) to \(xMax), Y: 0 to 1 (flipped)
            float2 texCoords[4] = {
                float2(\(xMin), 1),
                float2(\(xMax), 1),
                float2(\(xMin), 0),
                float2(\(xMax), 0)
            };

            VertexOut out;
            out.position = float4(positions[vertexID], 0, 1);
            out.texCoord = texCoords[vertexID];
            return out;
        }

        // NV12 YUV to RGB conversion
        // Y plane is r8Unorm (luminance)
        // UV plane is rg8Unorm (Cb, Cr interleaved)
        fragment float4 nv12FragmentShader(VertexOut in [[stage_in]],
                                           texture2d<float> yTexture [[texture(0)]],
                                           texture2d<float> uvTexture [[texture(1)]]) {
            constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

            float y = yTexture.sample(s, in.texCoord).r;
            float2 uv = uvTexture.sample(s, in.texCoord).rg;

            // Convert YUV (BT.601) to RGB
            // Y is in range [0, 1], UV is in range [0, 1] (centered at 0.5)
            float u = uv.r - 0.5;
            float v = uv.g - 0.5;

            float r = y + 1.402 * v;
            float g = y - 0.344 * u - 0.714 * v;
            float b = y + 1.772 * u;

            return float4(saturate(r), saturate(g), saturate(b), 1.0);
        }
        """

        // BGRA passthrough shader (with same cropping for portrait mode)
        let bgraShaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut bgraVertexShader(uint vertexID [[vertex_id]]) {
            float2 positions[4] = {
                float2(-1, -1),
                float2( 1, -1),
                float2(-1,  1),
                float2( 1,  1)
            };
            // Texture coordinates - crop horizontally for portrait mode
            float2 texCoords[4] = {
                float2(\(xMin), 1),
                float2(\(xMax), 1),
                float2(\(xMin), 0),
                float2(\(xMax), 0)
            };

            VertexOut out;
            out.position = float4(positions[vertexID], 0, 1);
            out.texCoord = texCoords[vertexID];
            return out;
        }

        fragment float4 bgraFragmentShader(VertexOut in [[stage_in]],
                                           texture2d<float> texture [[texture(0)]]) {
            constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
            return texture.sample(s, in.texCoord);
        }
        """

        do {
            // NV12 pipeline
            let nv12Library = try device.makeLibrary(source: nv12ShaderSource, options: nil)
            let nv12VertexFunction = nv12Library.makeFunction(name: "nv12VertexShader")
            let nv12FragmentFunction = nv12Library.makeFunction(name: "nv12FragmentShader")

            let nv12Descriptor = MTLRenderPipelineDescriptor()
            nv12Descriptor.vertexFunction = nv12VertexFunction
            nv12Descriptor.fragmentFunction = nv12FragmentFunction
            nv12Descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            nv12PipelineState = try device.makeRenderPipelineState(descriptor: nv12Descriptor)

            // BGRA pipeline
            let bgraLibrary = try device.makeLibrary(source: bgraShaderSource, options: nil)
            let bgraVertexFunction = bgraLibrary.makeFunction(name: "bgraVertexShader")
            let bgraFragmentFunction = bgraLibrary.makeFunction(name: "bgraFragmentShader")

            let bgraDescriptor = MTLRenderPipelineDescriptor()
            bgraDescriptor.vertexFunction = bgraVertexFunction
            bgraDescriptor.fragmentFunction = bgraFragmentFunction
            bgraDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            bgraPipelineState = try device.makeRenderPipelineState(descriptor: bgraDescriptor)
        } catch {
            NSLog("📹 Failed to create pipelines: \(error)")
        }
    }

    func renderFrame(_ frame: RTCVideoFrame) {
        currentFrame = frame
        frameCount += 1

        // Log every 30 frames (roughly once per second)
        if frameCount % 30 == 1 {
            NSLog("📹 Rendering frame #\(frameCount), size: \(frame.width)x\(frame.height)")
        }

        guard let metalLayer = metalLayer else { return }
        guard let drawable = metalLayer.nextDrawable() else { return }
        guard let commandQueue = commandQueue else { return }

        guard let buffer = frame.buffer as? RTCCVPixelBuffer else {
            NSLog("📹 Frame buffer is not RTCCVPixelBuffer")
            return
        }

        let pixelBuffer = buffer.pixelBuffer
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        let commandBuffer = commandQueue.makeCommandBuffer()

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            // NV12 format - use YUV shader with both planes
            guard let nv12PipelineState = nv12PipelineState,
                  let (yTexture, uvTexture) = createNV12Textures(from: pixelBuffer) else {
                encoder.endEncoding()
                return
            }

            encoder.setRenderPipelineState(nv12PipelineState)
            encoder.setFragmentTexture(yTexture, index: 0)
            encoder.setFragmentTexture(uvTexture, index: 1)

        case kCVPixelFormatType_32BGRA:
            // BGRA format - direct passthrough
            guard let bgraPipelineState = bgraPipelineState,
                  let texture = createBGRATexture(from: pixelBuffer) else {
                encoder.endEncoding()
                return
            }

            encoder.setRenderPipelineState(bgraPipelineState)
            encoder.setFragmentTexture(texture, index: 0)

        default:
            NSLog("📹 Unknown pixel format: \(pixelFormat)")
            encoder.endEncoding()
            return
        }

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }

    private func createNV12Textures(from pixelBuffer: CVPixelBuffer) -> (MTLTexture, MTLTexture)? {
        guard let textureCache = textureCache else { return nil }

        // Y plane (plane 0) - full resolution, r8Unorm
        let yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)

        var yTexture: CVMetalTexture?
        let yStatus = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, .r8Unorm, yWidth, yHeight, 0, &yTexture
        )

        guard yStatus == kCVReturnSuccess, let yTexture = yTexture else {
            NSLog("📹 Failed to create Y texture: \(yStatus)")
            return nil
        }

        // UV plane (plane 1) - half resolution, rg8Unorm (interleaved Cb/Cr)
        let uvWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)

        var uvTexture: CVMetalTexture?
        let uvStatus = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, .rg8Unorm, uvWidth, uvHeight, 1, &uvTexture
        )

        guard uvStatus == kCVReturnSuccess, let uvTexture = uvTexture else {
            NSLog("📹 Failed to create UV texture: \(uvStatus)")
            return nil
        }

        guard let yMTLTexture = CVMetalTextureGetTexture(yTexture),
              let uvMTLTexture = CVMetalTextureGetTexture(uvTexture) else {
            return nil
        }

        return (yMTLTexture, uvMTLTexture)
    }

    private func createBGRATexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache = textureCache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTexture = cvTexture else {
            return nil
        }

        return CVMetalTextureGetTexture(cvTexture)
    }

    override func layout() {
        super.layout()
        metalLayer?.frame = bounds
        metalLayer?.drawableSize = CGSize(
            width: bounds.width * (NSScreen.main?.backingScaleFactor ?? 2.0),
            height: bounds.height * (NSScreen.main?.backingScaleFactor ?? 2.0)
        )
    }
}
#endif

// MARK: - Preview

#if DEBUG
#Preview("Live Video - Doorbell") {
    LiveVideoView(
        device: RingDevice.previewDoorbell,
        onClose: {}
    )
    .frame(width: 340, height: 600)
}

#Preview("Live Video - Camera") {
    LiveVideoView(
        device: RingDevice.previewCamera,
        onClose: {}
    )
    .frame(width: 480, height: 270)
}
#endif

// MARK: - Preview Helper

extension RingDevice {
    static var previewDoorbell: RingDevice {
        let json = """
        {
            "id": 12345,
            "description": "Front Door",
            "device_id": "abc123",
            "kind": "doorbell_v4",
            "location_id": "loc123"
        }
        """.data(using: .utf8)!

        return try! JSONDecoder().decode(RingDevice.self, from: json)
    }

    static var previewCamera: RingDevice {
        let json = """
        {
            "id": 67890,
            "description": "Driveway",
            "device_id": "def456",
            "kind": "stickup_cam_v4",
            "location_id": "loc123"
        }
        """.data(using: .utf8)!

        return try! JSONDecoder().decode(RingDevice.self, from: json)
    }

    static var preview: RingDevice { previewDoorbell }
}
