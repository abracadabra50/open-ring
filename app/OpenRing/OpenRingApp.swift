import SwiftUI
import OpenRingFeature
import DesignSystem
import RingClient
import AppKit

@main
struct OpenRingApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Start global hotkey monitoring
        setupGlobalHotkey()
    }

    var body: some Scene {
        // Menubar app - no dock icon, no main window
        MenuBarExtra {
            MainPopoverView()
                .environmentObject(appState)
        } label: {
            MenuBarIcon(state: appState.menuBarState)
        }
        .menuBarExtraStyle(.window)

        // Settings window (opened from popover)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    private func setupGlobalHotkey() {
        Task { @MainActor in
            KeyboardShortcutManager.shared.startMonitoring {
                // When global hotkey is pressed, activate the app
                // This brings focus to the menu bar app
                NSApp.activate(ignoringOtherApps: true)

                // Try to click the menu bar status item
                // Find and click the OpenRing menu bar item
                if let button = findMenuBarButton() {
                    button.performClick(nil)
                }
            }
        }
    }

    private func findMenuBarButton() -> NSStatusBarButton? {
        // Find our app's menu bar button by checking all status items
        // This is a workaround since MenuBarExtra doesn't expose the status item
        guard let statusItems = NSStatusBar.system.value(forKey: "statusItems") as? [NSStatusItem] else {
            return nil
        }

        // Find the status item with our icon (bell icon)
        for item in statusItems {
            if let button = item.button,
               let image = button.image,
               image.name() == "bell" || image.accessibilityDescription?.contains("OpenRing") == true {
                return button
            }
        }

        // If not found by image, just return the last status item (most recently added)
        return statusItems.last?.button
    }
}

// MARK: - Main Popover View (handles auth state)

struct MainPopoverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.authState {
            case .authenticated:
                AuthenticatedPopoverView()
                    .environmentObject(appState)
            case .unauthenticated, .expired:
                LoginView {
                    Task {
                        await appState.onLoginSuccess()
                    }
                }
            case .loading:
                loadingView
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading...")
                .font(.Ring.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: Layout.Popover.width, height: 200)
    }
}

// MARK: - Authenticated Popover View

struct AuthenticatedPopoverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        PopoverView(
            devices: appState.devices,
            events: appState.events,
            selectedDevice: $appState.selectedDevice,
            onRefresh: {
                Task {
                    await appState.loadData()
                }
            }
        )
    }
}

// MARK: - App State

enum AuthViewState {
    case loading
    case unauthenticated
    case authenticated
    case expired
}

@MainActor
final class AppState: ObservableObject {
    @Published var authState: AuthViewState = .loading
    @Published var menuBarState: MenuBarState = .normal
    @Published var isLiveViewActive = false
    @Published var isSnoozed = false
    @Published var motionAlertsEnabled = true

    @Published var selectedDevice: RingDevice?
    @Published var devices: [RingDevice] = []
    @Published var events: [RingEvent] = []

    // Background polling for notifications
    private var pollingTask: Task<Void, Never>?

    enum MenuBarState {
        case normal
        case hasNewEvent
        case liveActive
        case authExpired
        case offline
    }

    init() {
        NSLog("🚀 AppState init - starting session restore")
        // Try to restore session on launch
        Task {
            NSLog("🚀 Task started for session restore")
            await restoreSession()
            NSLog("🚀 Session restore completed")
        }
    }

    func restoreSession() async {
        authState = .loading
        NSLog("🔐 Restoring session...")

        do {
            let restored = try await RingClient.shared.restoreSession()
            NSLog("🔐 Session restored: \(restored)")
            if restored {
                authState = .authenticated
                await loadData()

                // Request notification permission and start polling
                _ = await NotificationManager.shared.requestPermission()
                startPolling()
            } else {
                authState = .unauthenticated
            }
        } catch {
            NSLog("🔐 Failed to restore session: \(error)")
            authState = .unauthenticated
        }
    }

    func onLoginSuccess() async {
        authState = .authenticated
        await loadData()

        // Request notification permission and start polling
        _ = await NotificationManager.shared.requestPermission()
        startPolling()
    }

    func loadData() async {
        NSLog("📡 Loading data...")
        do {
            devices = try await RingClient.shared.fetchDevices()
            NSLog("✅ Loaded \(devices.count) devices: \(devices.map { $0.name })")

            let newEvents = try await RingClient.shared.fetchAllRecentEvents(limit: 20)
            NSLog("✅ Loaded \(newEvents.count) events")

            // Detect new events and send notifications
            if motionAlertsEnabled && !isSnoozed {
                let detectedEvents = NotificationManager.shared.detectNewEvents(old: events, new: newEvents)
                for event in detectedEvents {
                    await NotificationManager.shared.sendNotification(for: event)
                    menuBarState = .hasNewEvent
                }
            }

            events = newEvents

            if selectedDevice == nil {
                // Prefer doorbell devices first (Front Door priority)
                selectedDevice = devices.first(where: { $0.deviceType == .doorbell }) ?? devices.first
                NSLog("📱 Selected device: \(selectedDevice?.name ?? "none")")
            }

            // Only reset to normal if we didn't just get new events
            if menuBarState != .hasNewEvent {
                menuBarState = .normal
            }
        } catch let error as RingAPIError {
            NSLog("❌ API error loading data: \(error)")
            if case .unauthorized = error {
                authState = .expired
                menuBarState = .authExpired
                stopPolling()
            }
        } catch {
            NSLog("❌ Failed to load data: \(error)")
        }
    }

    func logout() async {
        stopPolling()
        do {
            try await RingClient.shared.logout()
        } catch {
            print("Logout error: \(error)")
        }
        devices = []
        events = []
        selectedDevice = nil
        authState = .unauthenticated
        menuBarState = .normal
    }

    // MARK: - Background Polling

    @AppStorage("pollingInterval") private var pollingInterval: Int = 30

    func startPolling() {
        guard pollingTask == nil else { return }
        let interval = pollingInterval
        NSLog("🔄 Starting background polling (every \(interval)s)")

        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await loadData()
            }
        }
    }

    func stopPolling() {
        NSLog("🔄 Stopping background polling")
        pollingTask?.cancel()
        pollingTask = nil
    }

    func updatePollingInterval(_ newInterval: Int) {
        NSLog("🔄 Updating polling interval to \(newInterval)s")
        stopPolling()
        startPolling()
    }

    func toggleSnooze() {
        isSnoozed.toggle()
        // TODO: Implement snooze logic
    }

    func toggleMotionAlerts() {
        motionAlertsEnabled.toggle()
        // TODO: Persist setting
    }

    func startLiveView(for device: RingDevice) async {
        isLiveViewActive = true
        menuBarState = .liveActive
        // TODO: Start actual live view
    }

    func stopLiveView() {
        isLiveViewActive = false
        menuBarState = .normal
    }
}

// MARK: - Menubar Icon

struct MenuBarIcon: View {
    let state: AppState.MenuBarState

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(iconColor)
    }

    private var iconName: String {
        switch state {
        case .normal:
            return "bell"
        case .hasNewEvent, .liveActive:
            return "bell.fill"
        case .authExpired:
            return "bell.badge.fill"
        case .offline:
            return "bell.slash"
        }
    }

    private var iconColor: Color {
        switch state {
        case .normal, .hasNewEvent:
            return .primary
        case .liveActive:
            return .Ring.accent
        case .authExpired:
            return .Ring.error
        case .offline:
            return .secondary
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    // Settings stored in UserDefaults
    @AppStorage("pollingInterval") private var pollingInterval: Int = 30
    @AppStorage("showBatteryIndicator") private var showBatteryIndicator: Bool = true
    @AppStorage("notificationSound") private var notificationSound: Bool = true
    @AppStorage("globalHotkey") private var globalHotkey: String = "⌘`"

    // API key state (loaded from keychain)
    @State private var anthropicAPIKey: String = ""
    @State private var isAPIKeySaved: Bool = false
    @State private var showAPIKey: Bool = false

    var body: some View {
        Form {
            // MARK: - Notifications Section
            Section("Notifications") {
                Toggle("Motion & Ring Alerts", isOn: $appState.motionAlertsEnabled)

                Toggle("Notification Sound", isOn: $notificationSound)

                Picker("Polling Interval", selection: $pollingInterval) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    Text("2 minutes").tag(120)
                }
                .onChange(of: pollingInterval) { _, newValue in
                    appState.updatePollingInterval(newValue)
                }
            }

            // MARK: - Shortcuts Section
            Section("Shortcuts") {
                Toggle("Enable Global Hotkey", isOn: Binding(
                    get: { KeyboardShortcutManager.shared.isGlobalHotkeyEnabled },
                    set: { KeyboardShortcutManager.shared.setEnabled($0) }
                ))

                HotkeyPicker(
                    selectedHotkey: $globalHotkey,
                    options: ["⌘`", "⌘⇧R", "⌘⌥O", "⌃⌥Space"]
                )
                .disabled(!KeyboardShortcutManager.shared.isGlobalHotkeyEnabled)

                Text("Use ⌘1, ⌘2, ⌘3, ⌘4 to switch cameras when viewing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - AI Section
            Section {
                HStack {
                    if showAPIKey {
                        TextField("API Key", text: $anthropicAPIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $anthropicAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    if isAPIKeySaved {
                        Label("API key saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }

                    Spacer()

                    Button("Save") {
                        saveAPIKey()
                    }
                    .disabled(anthropicAPIKey.isEmpty)

                    if isAPIKeySaved {
                        Button("Clear", role: .destructive) {
                            clearAPIKey()
                        }
                    }
                }
            } header: {
                Text("AI Guard")
            } footer: {
                Text("Enter your Anthropic API key to enable AI-powered scene analysis. Get a key at console.anthropic.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Display Section
            Section("Display") {
                Toggle("Show Battery Level", isOn: $showBatteryIndicator)
            }

            // MARK: - Account Section
            Section("Account") {
                if case .authenticated = appState.authState {
                    Button("Log Out", role: .destructive) {
                        Task {
                            await appState.logout()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
        .onAppear {
            loadAPIKey()
        }
    }

    // MARK: - API Key Management

    private func loadAPIKey() {
        Task {
            if let key = try? await KeychainManager.shared.getAnthropicAPIKey() {
                await MainActor.run {
                    anthropicAPIKey = key
                    isAPIKeySaved = true
                }
            }
        }
    }

    private func saveAPIKey() {
        Task {
            do {
                try await KeychainManager.shared.saveAnthropicAPIKey(anthropicAPIKey)
                await MainActor.run {
                    isAPIKeySaved = true
                }
            } catch {
                print("Failed to save API key: \(error)")
            }
        }
    }

    private func clearAPIKey() {
        Task {
            do {
                try await KeychainManager.shared.deleteAnthropicAPIKey()
                await MainActor.run {
                    anthropicAPIKey = ""
                    isAPIKeySaved = false
                }
            } catch {
                print("Failed to clear API key: \(error)")
            }
        }
    }
}

