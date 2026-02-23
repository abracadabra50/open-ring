import CameraDomain
import Foundation
import Network
import RingClient
import Storage

private final class PortCheckCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var continuation: CheckedContinuation<Void, Error>?
    private let connection: NWConnection

    init(connection: NWConnection, continuation: CheckedContinuation<Void, Error>) {
        self.connection = connection
        self.continuation = continuation
    }

    func complete(_ result: Result<Void, Error>) {
        lock.lock()
        guard !resumed, let continuation else {
            lock.unlock()
            return
        }
        resumed = true
        self.continuation = nil
        lock.unlock()

        connection.cancel()
        continuation.resume(with: result)
    }
}

public final class TapoProvider: CameraProvider, @unchecked Sendable {
    public let id = "tapo"
    public let displayName = "Tapo"

    private var state: CameraConnectionState = .unconfigured
    private var config: TapoSetupConfig?
    private var password: String?
    private var cloudPassword: String?

    private var activeSessions: [String: RtspPlayerSession] = [:]
    private var tapoHttpMonitor: TapoHttpEventMonitor?
    private var onvifMonitor: OnvifEventMonitor?
    private var fallbackMonitor: SnapshotDiffEventMonitor?
    private var fallbackEnabled = false
    private var onvifFallbackEnabled = false

    private let keychain = KeychainManager.shared
    private let storage = StorageManager.shared

    public init() {
        self.config = TapoConfigStore.load()
        if self.config != nil {
            self.state = .offline
        }
    }

    public func loadSetupSummary() async throws -> CameraSetupSummary? {
        if let config {
            return config.setupSummary
        }
        if let loaded = TapoConfigStore.load() {
            config = loaded
            return loaded.setupSummary
        }
        return nil
    }

    public func saveSetup(
        host: String,
        username: String,
        password: String,
        cloudPassword: String,
        profile: CameraStreamProfile,
        rtspPort: Int,
        onvifPort: Int
    ) async throws {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedHost.isEmpty, !normalizedUsername.isEmpty, !password.isEmpty else {
            throw CameraProviderError.unsupported("Host, username, and password are required.")
        }

        let savedConfig = TapoSetupConfig(
            host: normalizedHost,
            username: normalizedUsername,
            profile: profile,
            rtspPort: rtspPort,
            onvifPort: onvifPort
        )

        try TapoConfigStore.save(savedConfig)
        try await keychain.saveTapoCredentials(username: normalizedUsername, password: password)
        if !cloudPassword.isEmpty {
            try await keychain.saveTapoCloudPassword(cloudPassword)
        }
        self.config = savedConfig
        self.password = password
        self.cloudPassword = cloudPassword.isEmpty ? nil : cloudPassword
        state = .offline
    }

    public func clearSetup() async throws {
        await disconnect()
        TapoConfigStore.clear()
        try await keychain.clearTapoCredentials()
        config = nil
        password = nil
        state = .unconfigured
    }

    public func testConnection(
        host: String,
        username: String,
        password: String,
        cloudPassword: String,
        profile: CameraStreamProfile,
        rtspPort: Int,
        onvifPort: Int
    ) async throws {
        let testConfig = TapoSetupConfig(
            host: host,
            username: username,
            profile: profile,
            rtspPort: rtspPort,
            onvifPort: onvifPort
        )

        try await validatePortOpen(host: testConfig.host, port: testConfig.rtspPort)
        try await validatePortOpen(host: testConfig.host, port: testConfig.onvifPort)

        guard testConfig.rtspURL != nil else {
            throw CameraProviderError.streamStartFailed
        }

        _ = password
        _ = cloudPassword
    }

    public func currentConnectionState() async -> CameraConnectionState {
        state
    }

    public func connect() async throws {
        state = .connecting
        let (config, _) = try await ensureCredentials()

        do {
            try await validatePortOpen(host: config.host, port: config.rtspPort)
            state = .connected
        } catch {
            state = .offline
            throw error
        }
    }

    public func disconnect() async {
        await stopEventMonitoring()
        for (_, session) in activeSessions {
            await session.stop()
        }
        activeSessions.removeAll()
        state = config == nil ? .unconfigured : .offline
    }

    public func fetchDevices() async throws -> [CameraDevice] {
        let config = try await requireConfig()
        let isOnline: Bool
        switch state {
        case .connected:
            isOnline = true
        default:
            isOnline = false
        }
        return [
            CameraDevice(
                id: config.deviceId,
                name: config.deviceName,
                model: "Tapo C220",
                host: config.host,
                isOnline: isOnline,
                supportsMotionEvents: true,
                supportsPersonEvents: true
            )
        ]
    }

    public func fetchRecentEvents(limit: Int) async throws -> [CameraEvent] {
        let rows = try storage.getRecentEventsWithDescriptions(hours: 24, limit: limit)
        return rows.compactMap { row in
            let kind: CameraEventKind
            switch row.kind {
            case CameraEventKind.person.rawValue:
                kind = .person
            case CameraEventKind.motion.rawValue:
                kind = .motion
            default:
                return nil
            }

            return CameraEvent(
                id: row.id,
                deviceId: row.deviceId,
                deviceName: row.deviceName ?? "Tapo C220",
                kind: kind,
                createdAt: row.createdAt,
                source: "storage",
                detail: row.aiDescription
            )
        }
    }

    public func startLiveSession(deviceId: String) async throws -> any CameraLiveSession {
        if let existing = activeSessions[deviceId] {
            return existing
        }

        let (config, password) = try await ensureCredentials()
        guard deviceId == config.deviceId else {
            throw CameraProviderError.notConfigured
        }
        guard let streamURL = config.rtspURL else {
            throw CameraProviderError.streamStartFailed
        }

        let session = RtspPlayerSession(
            id: deviceId,
            streamURL: streamURL,
            username: config.username,
            password: password
        )
        try await session.start()
        activeSessions[deviceId] = session
        state = .connected
        return session
    }

    public func stopLiveSession(deviceId: String) async {
        guard let session = activeSessions.removeValue(forKey: deviceId) else {
            return
        }
        await session.stop()
    }

    public func startEventMonitoring(
        onEvent: @escaping @Sendable (CameraEvent) -> Void,
        onStatusChange: @escaping @Sendable (CameraConnectionState) -> Void
    ) async {
        do {
            let (config, password) = try await ensureCredentials()

            await stopEventMonitoring()
            fallbackEnabled = false
            onvifFallbackEnabled = false

            NSLog("📡 Starting Tapo HTTP event monitoring for \(config.host)")

            // Use cloud password for HTTP API auth (falls back to camera password)
            let httpPassword = try await keychain.getTapoCloudPassword() ?? password
            let httpMonitor = TapoHttpEventMonitor(config: config, password: httpPassword)
            tapoHttpMonitor = httpMonitor
            httpMonitor.start(
                onEvent: { [weak self] event in
                    self?.state = .connected
                    self?.persist(event)
                    onEvent(event)
                    onStatusChange(.connected)
                },
                onFailureThreshold: { [weak self] _ in
                    guard let self else { return }
                    NSLog("📡 Tapo HTTP failure threshold reached, falling back to ONVIF")
                    self.enableOnvifFallback(
                        config: config,
                        password: password,
                        onEvent: onEvent,
                        onStatusChange: onStatusChange
                    )
                }
            )
        } catch {
            NSLog("📡 Event monitoring failed to start: \(error.localizedDescription)")
            onStatusChange(.error(error.localizedDescription))
        }
    }

    public func stopEventMonitoring() async {
        tapoHttpMonitor?.stop()
        onvifMonitor?.stop()
        fallbackMonitor?.stop()
        tapoHttpMonitor = nil
        onvifMonitor = nil
        fallbackMonitor = nil
        fallbackEnabled = false
        onvifFallbackEnabled = false
    }

    /// Secondary fallback: ONVIF PullPoint event monitoring
    private func enableOnvifFallback(
        config: TapoSetupConfig,
        password: String,
        onEvent: @escaping @Sendable (CameraEvent) -> Void,
        onStatusChange: @escaping @Sendable (CameraConnectionState) -> Void
    ) {
        guard !onvifFallbackEnabled else {
            NSLog("📡 ONVIF fallback already enabled")
            return
        }
        onvifFallbackEnabled = true
        NSLog("📡 Enabling ONVIF fallback monitor for \(config.host):\(config.onvifPort)")

        let monitor = OnvifEventMonitor(config: config, password: password)
        onvifMonitor = monitor
        monitor.start(
            onEvent: { [weak self] event in
                self?.state = .connected
                self?.persist(event)
                onEvent(event)
                onStatusChange(.connected)
            },
            onFailureThreshold: { [weak self] _ in
                guard let self else { return }
                NSLog("📡 ONVIF fallback also failed, switching to snapshot-diff")
                self.state = .offline
                onStatusChange(.offline)
                self.enableSnapshotDiffFallback(
                    config: config,
                    password: password,
                    onEvent: onEvent
                )
            }
        )
    }

    /// Tertiary fallback: Snapshot luminance diff monitoring
    private func enableSnapshotDiffFallback(
        config: TapoSetupConfig,
        password: String,
        onEvent: @escaping @Sendable (CameraEvent) -> Void
    ) {
        guard !fallbackEnabled else {
            NSLog("📸 Snapshot-diff fallback already enabled")
            return
        }
        fallbackEnabled = true
        NSLog("📸 Enabling snapshot-diff fallback monitor for \(config.host)")
        let fallback = SnapshotDiffEventMonitor(config: config, password: password)
        fallbackMonitor = fallback
        fallback.start { [weak self] event in
            self?.persist(event)
            onEvent(event)
        }
    }

    private func persist(_ event: CameraEvent) {
        do {
            try storage.saveEvent(
                id: event.id,
                deviceId: event.deviceId,
                kind: event.kind.rawValue,
                createdAt: event.createdAt,
                deviceName: event.deviceName
            )
        } catch {
            NSLog("❌ Failed to persist event: \(error)")
        }
    }

    private func requireConfig() async throws -> TapoSetupConfig {
        if let config {
            return config
        }
        if let loaded = TapoConfigStore.load() {
            self.config = loaded
            return loaded
        }
        throw CameraProviderError.notConfigured
    }

    private func ensureCredentials() async throws -> (TapoSetupConfig, String) {
        let config = try await requireConfig()
        if let password {
            return (config, password)
        }
        guard let storedPassword = try await keychain.getTapoPassword() else {
            throw CameraProviderError.notConfigured
        }
        self.password = storedPassword
        // Also load cloud password if available
        self.cloudPassword = try await keychain.getTapoCloudPassword()
        return (config, storedPassword)
    }

    private func validatePortOpen(host: String, port: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                continuation.resume(throwing: CameraProviderError.networkUnavailable)
                return
            }

            let endpoint = NWEndpoint.Host(host)
            let connection = NWConnection(host: endpoint, port: nwPort, using: .tcp)
            let queue = DispatchQueue(label: "tapo.portcheck.\(port)")
            let completion = PortCheckCompletion(connection: connection, continuation: continuation)

            queue.asyncAfter(deadline: .now() + 4) {
                completion.complete(.failure(CameraProviderError.networkUnavailable))
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    completion.complete(.success(()))
                case .failed(let error):
                    completion.complete(.failure(error))
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}
