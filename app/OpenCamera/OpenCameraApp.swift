import AppKit
import DesignSystem
import OpenCameraFeature
import RingClient
import SwiftUI

@main
struct OpenCameraApp: App {
    @StateObject private var cameraController = AppCameraController()

    init() {
        setupGlobalHotkey()
    }

    var body: some Scene {
        MenuBarExtra {
            MainPopoverView()
                .environmentObject(cameraController)
        } label: {
            MenuBarIcon(state: cameraController.menuBarState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(cameraController)
        }
    }

    private func setupGlobalHotkey() {
        Task { @MainActor in
            KeyboardShortcutManager.shared.startMonitoring {
                NSApp.activate(ignoringOtherApps: true)
                if let button = findMenuBarButton() {
                    button.performClick(nil)
                }
            }
        }
    }

    private func findMenuBarButton() -> NSStatusBarButton? {
        guard let statusItems = NSStatusBar.system.value(forKey: "statusItems") as? [NSStatusItem] else {
            return nil
        }

        for item in statusItems {
            if let button = item.button,
               let image = button.image,
               image.name() == "bell" || image.accessibilityDescription?.contains("OpenCamera") == true {
                return button
            }
        }

        return statusItems.last?.button
    }
}

struct MainPopoverView: View {
    @EnvironmentObject var cameraController: AppCameraController

    var body: some View {
        switch cameraController.setupState {
        case .loading, .connecting:
            loadingView
        case .unconfigured:
            TapoSetupView(
                summary: cameraController.setupSummary,
                onTest: { host, username, password, cloudPassword, profile, rtspPort, onvifPort in
                    try await cameraController.testSetup(
                        host: host,
                        username: username,
                        password: password,
                        cloudPassword: cloudPassword,
                        profile: profile,
                        rtspPort: rtspPort,
                        onvifPort: onvifPort
                    )
                },
                onSave: { host, username, password, cloudPassword, profile, rtspPort, onvifPort in
                    await cameraController.saveSetup(
                        host: host,
                        username: username,
                        password: password,
                        cloudPassword: cloudPassword,
                        profile: profile,
                        rtspPort: rtspPort,
                        onvifPort: onvifPort
                    )
                }
            )
        case .ready:
            TapoPopoverView()
                .environmentObject(cameraController)
        case .error(let message):
            setupErrorView(message: message)
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Connecting to camera...")
                .font(.Ring.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: Layout.Popover.width, height: 220)
    }

    private func setupErrorView(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(Color.Ring.error)

            Text("Connection error")
                .font(.Ring.headline)

            Text(message)
                .font(.Ring.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.sm) {
                Button("Retry") {
                    Task {
                        await cameraController.reconnect()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Ring.accent)

                Button("Edit Setup") {
                    Task {
                        await cameraController.clearSetup()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.lg)
        .frame(width: Layout.Popover.width, height: 260)
    }
}

struct MenuBarIcon: View {
    let state: AppCameraController.MenuBarState

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
            return Color.Ring.accent
        case .authExpired:
            return Color.Ring.error
        case .offline:
            return .secondary
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var cameraController: AppCameraController

    @AppStorage("notificationSound") private var notificationSound: Bool = true
    @AppStorage("globalHotkey") private var globalHotkey: String = "⌘`"

    @State private var anthropicAPIKey: String = ""
    @State private var isAPIKeySaved: Bool = false
    @State private var showAPIKey: Bool = false

    var body: some View {
        Form {
            Section("Camera") {
                if let setup = cameraController.setupSummary {
                    LabeledContent("Host", value: setup.host)
                    LabeledContent("Username", value: setup.username)
                    LabeledContent("Profile", value: setup.profile.displayName)
                    LabeledContent("RTSP Port", value: String(setup.rtspPort))
                    LabeledContent("ONVIF Port", value: String(setup.onvifPort))

                    HStack {
                        Button("Reconnect") {
                            Task {
                                await cameraController.reconnect()
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Reset Setup", role: .destructive) {
                            Task {
                                await cameraController.clearSetup()
                            }
                        }
                    }
                } else {
                    Text("No camera configured yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notifications") {
                Toggle(
                    "Motion & Person Alerts",
                    isOn: Binding(
                        get: { cameraController.motionAlertsEnabled },
                        set: { cameraController.setMotionAlertsEnabled($0) }
                    )
                )

                Toggle("Snooze Alerts", isOn: Binding(
                    get: { cameraController.isSnoozed },
                    set: { cameraController.setSnoozed($0) }
                ))

                Toggle("Notification Sound", isOn: $notificationSound)
            }

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
            }

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
                Text("AI and media actions remain visible as placeholders in Phase 1 Tapo mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 540)
        .onAppear {
            loadAPIKey()
        }
    }

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
                NSLog("Failed to save API key: \(error)")
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
                NSLog("Failed to clear API key: \(error)")
            }
        }
    }
}
