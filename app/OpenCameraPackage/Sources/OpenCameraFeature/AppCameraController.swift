import CameraDomain
import CameraProviders
import Foundation

private final class EventMonitoringBridge: @unchecked Sendable {
    weak var controller: AppCameraController?

    init(controller: AppCameraController) {
        self.controller = controller
    }

    func onEvent(_ event: CameraEvent) {
        Task { @MainActor [weak controller] in
            guard let controller else { return }
            controller.handleIncomingEvent(event)
        }
    }

    func onStatusChange(_ state: CameraConnectionState) {
        Task { @MainActor [weak controller] in
            guard let controller else { return }
            controller.handleProviderStatus(state)
        }
    }
}

@MainActor
public final class AppCameraController: ObservableObject {
    public enum SetupState: Equatable {
        case loading
        case unconfigured
        case connecting
        case ready
        case error(String)
    }

    public enum MenuBarState: Equatable {
        case normal
        case hasNewEvent
        case liveActive
        case authExpired
        case offline
    }

    @Published public private(set) var setupState: SetupState = .loading
    @Published public private(set) var menuBarState: MenuBarState = .normal
    @Published public private(set) var devices: [CameraDevice] = []
    @Published public private(set) var events: [CameraEvent] = []
    @Published public var selectedDevice: CameraDevice?
    @Published public var motionAlertsEnabled: Bool
    @Published public var isSnoozed: Bool
    @Published public var setupSummary: CameraSetupSummary?

    public let provider: any CameraProvider
    private let maxEvents = 100
    private let defaults = UserDefaults.standard

    public init(provider: any CameraProvider = ProviderRegistry.makeProvider(kind: .tapo)) {
        self.provider = provider
        self.motionAlertsEnabled = defaults.object(forKey: "motion_alerts_enabled") as? Bool ?? true
        self.isSnoozed = defaults.object(forKey: "notifications_snoozed") as? Bool ?? false

        Task {
            await bootstrap()
        }
    }

    public func bootstrap() async {
        setupState = .loading
        do {
            setupSummary = try await provider.loadSetupSummary()
            guard setupSummary != nil else {
                setupState = .unconfigured
                menuBarState = .normal
                return
            }
            try await connectAndStart()
        } catch {
            setupState = .error(error.localizedDescription)
            menuBarState = .offline
        }
    }

    public func testSetup(
        host: String,
        username: String,
        password: String,
        cloudPassword: String,
        profile: CameraStreamProfile,
        rtspPort: Int,
        onvifPort: Int
    ) async throws {
        try await provider.testConnection(
            host: host,
            username: username,
            password: password,
            cloudPassword: cloudPassword,
            profile: profile,
            rtspPort: rtspPort,
            onvifPort: onvifPort
        )
    }

    public func saveSetup(
        host: String,
        username: String,
        password: String,
        cloudPassword: String,
        profile: CameraStreamProfile,
        rtspPort: Int,
        onvifPort: Int
    ) async {
        setupState = .connecting
        do {
            try await provider.saveSetup(
                host: host,
                username: username,
                password: password,
                cloudPassword: cloudPassword,
                profile: profile,
                rtspPort: rtspPort,
                onvifPort: onvifPort
            )
            setupSummary = try await provider.loadSetupSummary()
            try await connectAndStart()
        } catch {
            setupState = .error(error.localizedDescription)
            menuBarState = .offline
        }
    }

    public func clearSetup() async {
        do {
            try await provider.clearSetup()
            devices = []
            events = []
            selectedDevice = nil
            setupSummary = nil
            setupState = .unconfigured
            menuBarState = .normal
        } catch {
            setupState = .error(error.localizedDescription)
        }
    }

    public func reconnect() async {
        do {
            try await connectAndStart()
        } catch {
            setupState = .error(error.localizedDescription)
            menuBarState = .offline
        }
    }

    public func setLiveActive(_ active: Bool) {
        if active {
            menuBarState = .liveActive
        } else if menuBarState == .liveActive {
            menuBarState = .normal
        }
    }

    public func toggleSnooze() {
        isSnoozed.toggle()
        defaults.set(isSnoozed, forKey: "notifications_snoozed")
    }

    public func setSnoozed(_ snoozed: Bool) {
        isSnoozed = snoozed
        defaults.set(isSnoozed, forKey: "notifications_snoozed")
    }

    public func toggleMotionAlerts() {
        motionAlertsEnabled.toggle()
        defaults.set(motionAlertsEnabled, forKey: "motion_alerts_enabled")
    }

    public func setMotionAlertsEnabled(_ enabled: Bool) {
        motionAlertsEnabled = enabled
        defaults.set(motionAlertsEnabled, forKey: "motion_alerts_enabled")
    }

    public func refresh() async {
        do {
            devices = try await provider.fetchDevices()
            events = try await provider.fetchRecentEvents(limit: maxEvents).sorted { $0.createdAt > $1.createdAt }
            if selectedDevice == nil {
                selectedDevice = devices.first
            }
            if menuBarState != .liveActive {
                menuBarState = .normal
            }
        } catch {
            menuBarState = .offline
        }
    }

    private func connectAndStart() async throws {
        setupState = .connecting
        try await provider.connect()
        setupState = .ready
        menuBarState = .normal

        _ = await NotificationManager.shared.requestPermission()
        await refresh()
        await startEventMonitoring()
    }

    private func startEventMonitoring() async {
        let bridge = EventMonitoringBridge(controller: self)
        let onEvent: @Sendable (CameraEvent) -> Void = { event in
            bridge.onEvent(event)
        }
        let onStatusChange: @Sendable (CameraConnectionState) -> Void = { state in
            bridge.onStatusChange(state)
        }
        await provider.startEventMonitoring(
            onEvent: onEvent,
            onStatusChange: onStatusChange
        )
    }

    fileprivate func handleIncomingEvent(_ event: CameraEvent) {
        if !events.contains(where: { $0.id == event.id }) {
            events.insert(event, at: 0)
            if events.count > maxEvents {
                events = Array(events.prefix(maxEvents))
            }
        }

        if motionAlertsEnabled && !isSnoozed {
            Task {
                await NotificationManager.shared.sendNotification(for: event)
            }
            if menuBarState != .liveActive {
                menuBarState = .hasNewEvent
            }
        }
    }

    fileprivate func handleProviderStatus(_ state: CameraConnectionState) {
        switch state {
        case .connected:
            if setupState == .connecting || setupState == .loading {
                setupState = .ready
            }
            if menuBarState != .liveActive {
                menuBarState = .normal
            }
        case .offline:
            menuBarState = .offline
        case .error(let message):
            setupState = .error(message)
            menuBarState = .offline
        case .unconfigured:
            setupState = .unconfigured
            menuBarState = .normal
        case .connecting:
            setupState = .connecting
        }
    }
}
