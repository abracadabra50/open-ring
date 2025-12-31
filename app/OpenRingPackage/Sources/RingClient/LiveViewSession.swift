import Foundation
@preconcurrency import WebRTC

// MARK: - Live View Session Manager

/// Uses Ring's newer client-initiated WebRTC API
/// POST to /integrations/v1/liveview/start with local SDP offer
/// Receives SDP answer in response - no WebSocket signaling needed
public actor LiveViewSession {
    public enum State: Sendable, Equatable {
        case idle
        case connecting
        case creatingOffer
        case negotiating
        case connected
        case failed(String)
        case disconnected

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.connecting, .connecting),
                 (.creatingOffer, .creatingOffer),
                 (.negotiating, .negotiating),
                 (.connected, .connected),
                 (.disconnected, .disconnected):
                return true
            case (.failed(let l), .failed(let r)):
                return l == r
            default:
                return false
            }
        }

        public var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    public private(set) var state: State = .idle
    private var sessionId: String
    private var peerConnection: RTCPeerConnection?
    private var videoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?
    private var peerConnectionDelegate: PeerConnectionDelegate?

    // Push-to-talk state
    public private(set) var isTalking: Bool = false

    private let deviceId: Int
    private let accessToken: String
    private let hardwareId: String
    private let session: URLSession
    private let factory: RTCPeerConnectionFactory

    public var onStateChange: (@Sendable (State) -> Void)?
    public var onVideoTrack: (@Sendable (RTCVideoTrack) -> Void)?
    public var onAudioTrack: (@Sendable (RTCAudioTrack) -> Void)?

    // MARK: - Callbacks Setup

    public func setCallbacks(
        onStateChange: @escaping @Sendable (State) -> Void,
        onVideoTrack: @escaping @Sendable (RTCVideoTrack) -> Void,
        onAudioTrack: @escaping @Sendable (RTCAudioTrack) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onVideoTrack = onVideoTrack
        self.onAudioTrack = onAudioTrack
    }

    // MARK: - Init

    public init(deviceId: Int, accessToken: String, hardwareId: String) {
        self.deviceId = deviceId
        self.accessToken = accessToken
        self.hardwareId = hardwareId
        self.sessionId = UUID().uuidString.lowercased()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        // Initialize WebRTC
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
    }

    deinit {
        RTCCleanupSSL()
    }

    // MARK: - Public API

    public func start() async throws {
        guard case .idle = state else {
            throw LiveViewError.alreadyStarted
        }

        state = .connecting
        onStateChange?(.connecting)
        NSLog("📹 LiveView: Starting live session for device \(deviceId)")

        do {
            // Step 1: Create peer connection and local offer
            state = .creatingOffer
            onStateChange?(.creatingOffer)

            try await setupPeerConnection()
            let localOffer = try await createOffer()
            NSLog("📹 LiveView: Created local SDP offer")

            // Step 2: Send offer to Ring API and get answer
            state = .negotiating
            onStateChange?(.negotiating)

            let answerSdp = try await startLiveView(offerSdp: localOffer.sdp)
            NSLog("📹 LiveView: Received SDP answer from Ring")

            // Step 3+4: Set remote description AND activate camera in parallel
            // activateCamera only needs sessionId (set at init), not remote description
            async let activationTask: () = activateCamera()
            try await setRemoteDescription(answerSdp)
            NSLog("📹 LiveView: Set remote description")
            try await activationTask
            NSLog("📹 LiveView: Camera activated (parallel)")

            // Step 5: Wait for video track and start stats monitoring
            // The delegate will call us when track arrives
            NSLog("📹 LiveView: Waiting for video track...")

            // Start a background task to periodically log stats
            Task.detached { [weak self] in
                for i in 1...10 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    await self?.logConnectionStats()
                }
            }

        } catch {
            NSLog("📹 LiveView: Failed to start: \(error)")
            let errorMsg = error.localizedDescription
            state = .failed(errorMsg)
            onStateChange?(.failed(errorMsg))
            throw error
        }
    }

    public func stop() async {
        NSLog("📹 LiveView: Stopping session...")

        // End session on server
        do {
            try await endLiveView()
        } catch {
            NSLog("📹 LiveView: Failed to end session: \(error)")
        }

        peerConnection?.close()
        peerConnection = nil
        peerConnectionDelegate = nil

        videoTrack = nil
        localAudioTrack = nil
        isTalking = false

        state = .disconnected
        onStateChange?(.disconnected)
    }

    // MARK: - Push-to-Talk

    /// Start talking - enables microphone
    public func startTalking() {
        guard state == .connected else {
            NSLog("🎤 PTT: Cannot start talking - not connected")
            return
        }
        localAudioTrack?.isEnabled = true
        isTalking = true
        NSLog("🎤 PTT: Microphone ENABLED - talking started")
    }

    /// Stop talking - disables microphone
    public func stopTalking() {
        localAudioTrack?.isEnabled = false
        isTalking = false
        NSLog("🎤 PTT: Microphone DISABLED - talking stopped")
    }

    // MARK: - Ring Live View API

    private func startLiveView(offerSdp: String) async throws -> String {
        let url = URL(string: "https://api.ring.com/integrations/v1/liveview/start")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("android:com.ringapp", forHTTPHeaderField: "User-Agent")
        request.setValue(hardwareId, forHTTPHeaderField: "hardware_id")

        let body: [String: Any] = [
            "session_id": sessionId,
            "device_id": deviceId,
            "sdp": offerSdp,
            "protocol": "webrtc"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        NSLog("📹 LiveView: session_id=\(sessionId), device_id=\(deviceId)")
        NSLog("📹 LiveView: SDP length=\(offerSdp.count), first 200 chars: \(String(offerSdp.prefix(200)))")
        NSLog("📹 LiveView: Sending offer to Ring API...")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LiveViewError.networkError
        }

        NSLog("📹 LiveView: API response: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            if let responseText = String(data: data, encoding: .utf8) {
                NSLog("📹 LiveView: Error response: \(responseText)")
            }
            throw LiveViewError.sessionCreationFailed(httpResponse.statusCode)
        }

        // Parse response to get SDP answer
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answerSdp = json["sdp"] as? String else {
            if let responseText = String(data: data, encoding: .utf8) {
                NSLog("📹 LiveView: Response: \(responseText)")
            }
            throw LiveViewError.invalidSessionResponse
        }

        // Log SDP answer for debugging (check for ICE candidates and media)
        NSLog("📹 LiveView: SDP answer length: \(answerSdp.count)")

        // Extract and log candidate info
        let lines = answerSdp.components(separatedBy: "\r\n")
        var candidateCount = 0
        var hasRelay = false
        var hasSrflx = false
        var hasHost = false

        for line in lines {
            if line.starts(with: "a=candidate") {
                candidateCount += 1
                // Log every candidate to see the actual IPs
                NSLog("📹 LiveView: Candidate: \(line)")
                if line.contains("relay") || line.contains("typ relay") {
                    hasRelay = true
                } else if line.contains("srflx") || line.contains("typ srflx") {
                    hasSrflx = true
                } else if line.contains("host") || line.contains("typ host") {
                    hasHost = true
                }
            }
        }

        NSLog("📹 LiveView: SDP has \(candidateCount) ICE candidates (host=\(hasHost), srflx=\(hasSrflx), relay=\(hasRelay))")

        if !hasRelay {
            NSLog("📹 LiveView: ⚠️ No TURN/relay candidates - NAT traversal may fail")
        }

        if answerSdp.contains("m=video") {
            NSLog("📹 LiveView: SDP contains video media line")
        }

        return answerSdp
    }

    private func endLiveView() async throws {
        let url = URL(string: "https://api.ring.com/integrations/v1/liveview/end")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("android:com.ringapp", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "session_id": sessionId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            NSLog("📹 LiveView: End session response: \(httpResponse.statusCode)")
        }
    }

    private func activateCamera() async throws {
        let url = URL(string: "https://api.ring.com/integrations/v1/liveview/options")!

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("android:com.ringapp", forHTTPHeaderField: "User-Agent")
        request.setValue(hardwareId, forHTTPHeaderField: "hardware_id")

        let body: [String: Any] = [
            "session_id": sessionId,
            "actions": ["turn_off_stealth_mode"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        NSLog("📹 LiveView: Activating camera (turn off stealth mode)...")
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            NSLog("📹 LiveView: Activate camera response: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
                if let responseText = String(data: data, encoding: .utf8) {
                    NSLog("📹 LiveView: Activate camera error: \(responseText)")
                }
            }
        }
    }

    // MARK: - WebRTC Setup

    private func setupPeerConnection() async throws {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.iceTransportPolicy = .all  // Allow all transport types (UDP and TCP)
        config.tcpCandidatePolicy = .enabled  // Keep TCP enabled as fallback

        // Log network interfaces for debugging
        NSLog("📹 LiveView: Setting up peer connection with iceTransportPolicy=all, tcpCandidatePolicy=enabled")

        // STUN servers for NAT traversal - use only 2 fastest (Google + Ring)
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun.ring.com:3478"])
        ]

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        // Create delegate to handle events
        let delegate = PeerConnectionDelegate(
            onVideoTrack: { [weak self] track in
                Task { [weak self] in
                    await self?.handleVideoTrack(track)
                }
            },
            onAudioTrack: { [weak self] track in
                Task { [weak self] in
                    await self?.handleAudioTrack(track)
                }
            },
            onIceConnectionChange: { [weak self] newState in
                Task { [weak self] in
                    await self?.handleIceConnectionStateChange(newState)
                }
            }
        )
        self.peerConnectionDelegate = delegate

        peerConnection = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: delegate
        )

        guard let pc = peerConnection else {
            throw LiveViewError.peerConnectionNotReady
        }

        // Create local audio source/track for push-to-talk
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: audioConstraints)
        localAudioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        localAudioTrack?.isEnabled = false  // Start muted, enable when push-to-talk is pressed

        // Add transceivers with both send and receive for two-way audio
        let audioTransceiverInit = RTCRtpTransceiverInit()
        audioTransceiverInit.direction = .sendRecv
        audioTransceiverInit.streamIds = ["stream0"]
        let audioTransceiver = pc.addTransceiver(of: .audio, init: audioTransceiverInit)
        if let sender = audioTransceiver?.sender {
            sender.track = localAudioTrack
        }
        NSLog("🎤 LiveView: Audio track configured for push-to-talk")

        // Set up video transceiver for receiving only
        let videoTransceiverInit = RTCRtpTransceiverInit()
        videoTransceiverInit.direction = .recvOnly
        pc.addTransceiver(of: .video, init: videoTransceiverInit)

        NSLog("📹 LiveView: Peer connection configured with transceivers")
    }

    private func createOffer() async throws -> RTCSessionDescription {
        guard let pc = peerConnection else {
            throw LiveViewError.peerConnectionNotReady
        }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveVideo": "true",
                "OfferToReceiveAudio": "true"
            ],
            optionalConstraints: nil
        )

        let offer = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            pc.offer(for: constraints) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sdp = sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: LiveViewError.offerCreationFailed)
                }
            }
        }

        // Set local description
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(offer) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        // Wait for ICE gathering to complete (or timeout)
        try await waitForIceGathering()

        // Return the offer with gathered ICE candidates
        guard let localDescription = pc.localDescription else {
            throw LiveViewError.offerCreationFailed
        }

        // Log our local candidates
        let offerLines = localDescription.sdp.components(separatedBy: "\r\n")
        var localCandidateCount = 0
        for line in offerLines {
            if line.starts(with: "a=candidate") {
                localCandidateCount += 1
                NSLog("📹 LiveView: OUR candidate: \(line)")
            }
        }
        NSLog("📹 LiveView: Our offer has \(localCandidateCount) ICE candidates")

        return localDescription
    }

    private func waitForIceGathering() async throws {
        guard let pc = peerConnection else { return }

        // Quick timeout - host candidates are instant, srflx arrive in 100-500ms
        let timeout = 2.0
        let startTime = Date()

        while pc.iceGatheringState != .complete {
            if Date().timeIntervalSince(startTime) > timeout {
                NSLog("📹 LiveView: ICE gathering timeout after \(timeout)s, proceeding with available candidates")
                break
            }

            // Early exit: Check if we have at least 2 candidates (host + srflx)
            if let sdp = pc.localDescription?.sdp {
                let candidateCount = sdp.components(separatedBy: "a=candidate").count - 1
                if candidateCount >= 2 {
                    NSLog("📹 LiveView: ICE early exit with \(candidateCount) candidates")
                    break
                }
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms polling (faster)
        }

        NSLog("📹 LiveView: ICE gathering state: \(pc.iceGatheringState.rawValue)")
    }

    private func setRemoteDescription(_ sdp: String) async throws {
        guard let pc = peerConnection else {
            throw LiveViewError.peerConnectionNotReady
        }

        let answer = RTCSessionDescription(type: .answer, sdp: sdp)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(answer) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        // Check if we already have a video track
        checkForVideoTrack()
    }

    // MARK: - Track Handling

    private func handleVideoTrack(_ track: RTCVideoTrack) {
        NSLog("📹 LiveView: Received video track from delegate!")
        videoTrack = track
        onVideoTrack?(track)
        state = .connected
        onStateChange?(.connected)
    }

    private func handleAudioTrack(_ track: RTCAudioTrack) {
        NSLog("🔊 LiveView: Received audio track from delegate!")
        // Audio tracks start enabled by default - the MultiStreamManager will mute non-active cameras
        onAudioTrack?(track)
    }

    private func handleIceConnectionStateChange(_ newState: RTCIceConnectionState) {
        NSLog("📹 LiveView: ICE connection state: \(newState.rawValue)")

        switch newState {
        case .connected, .completed:
            if state != .connected {
                checkForVideoTrack()
            }
        case .failed:
            state = .failed("ICE connection failed")
            onStateChange?(.failed("ICE connection failed"))
        case .disconnected:
            if state == .connected {
                state = .disconnected
                onStateChange?(.disconnected)
            }
        default:
            break
        }
    }

    private func logConnectionStats() async {
        guard let pc = peerConnection else { return }

        NSLog("📹 Stats: ICE connection=\(pc.iceConnectionState.rawValue), signaling=\(pc.signalingState.rawValue)")

        // Get stats using the callback-based API
        pc.statistics { report in
            for (_, stats) in report.statistics {
                let statsType = stats.type
                if statsType == "inbound-rtp" {
                    if let values = stats.values as? [String: Any] {
                        let kind = values["kind"] as? String ?? "unknown"
                        let bytesReceived = values["bytesReceived"] as? Int64 ?? 0
                        let packetsReceived = values["packetsReceived"] as? Int64 ?? 0
                        let framesDecoded = values["framesDecoded"] as? Int64 ?? 0
                        NSLog("📹 Stats inbound-rtp (\(kind)): bytes=\(bytesReceived), packets=\(packetsReceived), framesDecoded=\(framesDecoded)")
                    }
                } else if statsType == "candidate-pair" {
                    if let values = stats.values as? [String: Any] {
                        let state = values["state"] as? String ?? "unknown"
                        let bytesReceived = values["bytesReceived"] as? Int64 ?? 0
                        let bytesSent = values["bytesSent"] as? Int64 ?? 0
                        let nominated = values["nominated"] as? Bool ?? false
                        let localCandidateId = values["localCandidateId"] as? String ?? "?"
                        let remoteCandidateId = values["remoteCandidateId"] as? String ?? "?"
                        NSLog("📹 Stats candidate-pair: state=\(state), nominated=\(nominated), bytesRecv=\(bytesReceived), bytesSent=\(bytesSent), local=\(localCandidateId), remote=\(remoteCandidateId)")
                    }
                } else if statsType == "local-candidate" || statsType == "remote-candidate" {
                    if let values = stats.values as? [String: Any] {
                        let candidateType = values["candidateType"] as? String ?? "unknown"
                        let protocol_ = values["protocol"] as? String ?? "?"
                        let address = values["address"] as? String ?? values["ip"] as? String ?? "?"
                        NSLog("📹 Stats \(statsType): type=\(candidateType), protocol=\(protocol_), address=\(address)")
                    }
                }
            }
        }
    }

    private func checkForVideoTrack() {
        guard let pc = peerConnection else { return }

        // Log detailed transceiver info
        NSLog("📹 LiveView: Checking transceivers (\(pc.transceivers.count) total):")
        for (i, transceiver) in pc.transceivers.enumerated() {
            let mediaType = transceiver.mediaType == .video ? "video" : "audio"
            let direction = transceiver.direction.rawValue
            let currentDir = transceiver.currentDirection
            NSLog("📹   Transceiver \(i): type=\(mediaType), direction=\(direction), currentDirection=\(currentDir)")
            let receiver = transceiver.receiver
            if let track = receiver.track {
                NSLog("📹     Receiver track: kind=\(track.kind), enabled=\(track.isEnabled), readyState=\(track.readyState.rawValue)")
            } else {
                NSLog("📹     Receiver has no track")
            }
        }

        NSLog("📹 LiveView: Checking receivers (\(pc.receivers.count) total):")
        for (i, receiver) in pc.receivers.enumerated() {
            if let track = receiver.track as? RTCVideoTrack {
                NSLog("📹 LiveView: Found video track in receiver \(i)! enabled=\(track.isEnabled), readyState=\(track.readyState.rawValue)")
                videoTrack = track
                onVideoTrack?(track)
                state = .connected
                onStateChange?(.connected)
                return
            } else if let track = receiver.track {
                NSLog("📹   Receiver \(i): track kind=\(track.kind), enabled=\(track.isEnabled)")
            } else {
                NSLog("📹   Receiver \(i): no track")
            }
        }

        NSLog("📹 LiveView: No video track yet, waiting for delegate callback...")
    }
}

// MARK: - Peer Connection Delegate

private class PeerConnectionDelegate: NSObject, RTCPeerConnectionDelegate {
    private let onVideoTrack: (RTCVideoTrack) -> Void
    private let onAudioTrack: (RTCAudioTrack) -> Void
    private let onIceConnectionChange: (RTCIceConnectionState) -> Void

    init(
        onVideoTrack: @escaping (RTCVideoTrack) -> Void,
        onAudioTrack: @escaping (RTCAudioTrack) -> Void,
        onIceConnectionChange: @escaping (RTCIceConnectionState) -> Void
    ) {
        self.onVideoTrack = onVideoTrack
        self.onAudioTrack = onAudioTrack
        self.onIceConnectionChange = onIceConnectionChange
        super.init()
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        NSLog("📹 WebRTC: Signaling state: \(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        NSLog("📹 WebRTC: Added stream with \(stream.videoTracks.count) video, \(stream.audioTracks.count) audio tracks")
        if let videoTrack = stream.videoTracks.first {
            onVideoTrack(videoTrack)
        }
        if let audioTrack = stream.audioTracks.first {
            onAudioTrack(audioTrack)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        NSLog("📹 WebRTC: Removed stream")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        NSLog("📹 WebRTC: Should negotiate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let stateName: String
        switch newState {
        case .new: stateName = "new"
        case .checking: stateName = "checking"
        case .connected: stateName = "connected"
        case .completed: stateName = "completed"
        case .failed: stateName = "FAILED"
        case .disconnected: stateName = "disconnected"
        case .closed: stateName = "closed"
        case .count: stateName = "count"
        @unknown default: stateName = "unknown(\(newState.rawValue))"
        }
        NSLog("📹 WebRTC: ICE connection state changed to: \(stateName) (rawValue=\(newState.rawValue))")
        onIceConnectionChange(newState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        NSLog("📹 WebRTC: ICE gathering state: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // Parse candidate type and protocol
        let sdp = candidate.sdp
        let isUdp = sdp.contains(" udp ") || sdp.contains(" UDP ")
        let isTcp = sdp.contains(" tcp ") || sdp.contains(" TCP ")
        let isSrflx = sdp.contains("typ srflx")
        let isHost = sdp.contains("typ host")
        let isRelay = sdp.contains("typ relay")
        let typeStr = isSrflx ? "srflx" : (isRelay ? "relay" : (isHost ? "host" : "unknown"))
        let protoStr = isUdp ? "UDP" : (isTcp ? "TCP" : "?")
        NSLog("📹 WebRTC: Generated ICE candidate [\(protoStr)/\(typeStr)]: \(candidate.sdp)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        NSLog("📹 WebRTC: Removed \(candidates.count) ICE candidates")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        NSLog("📹 WebRTC: Opened data channel")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        NSLog("📹 WebRTC: Added RTP receiver, track kind: \(rtpReceiver.track?.kind ?? "unknown")")
        if let videoTrack = rtpReceiver.track as? RTCVideoTrack {
            onVideoTrack(videoTrack)
        } else if let audioTrack = rtpReceiver.track as? RTCAudioTrack {
            onAudioTrack(audioTrack)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        NSLog("📹 WebRTC: Removed RTP receiver")
    }
}

// MARK: - Errors

public enum LiveViewError: Error, LocalizedError {
    case alreadyStarted
    case networkError
    case sessionCreationFailed(Int)
    case invalidSessionResponse
    case peerConnectionNotReady
    case offerCreationFailed
    case answerCreationFailed
    case encodingError
    case timeout

    public var errorDescription: String? {
        switch self {
        case .alreadyStarted:
            return "Live view already started"
        case .networkError:
            return "Network error"
        case .sessionCreationFailed(let code):
            return "Failed to create session (HTTP \(code))"
        case .invalidSessionResponse:
            return "Invalid session response"
        case .peerConnectionNotReady:
            return "Peer connection not ready"
        case .offerCreationFailed:
            return "Failed to create SDP offer"
        case .answerCreationFailed:
            return "Failed to create SDP answer"
        case .encodingError:
            return "Encoding error"
        case .timeout:
            return "Connection timeout"
        }
    }
}
