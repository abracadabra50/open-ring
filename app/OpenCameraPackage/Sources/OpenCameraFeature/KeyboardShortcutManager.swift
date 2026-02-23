import SwiftUI
import Cocoa
import Carbon.HIToolbox

// MARK: - Keyboard Shortcut Manager
// Manages global keyboard shortcuts for the app

@MainActor
public final class KeyboardShortcutManager: ObservableObject {
    public static let shared = KeyboardShortcutManager()

    @Published public var isGlobalHotkeyEnabled = true
    @Published public var globalHotkeyString: String = "⌘`"

    private var eventMonitor: Any?
    private var hotkeyCallback: (() -> Void)?

    private init() {
        // Load saved preference
        if let savedHotkey = UserDefaults.standard.string(forKey: "globalHotkey") {
            globalHotkeyString = savedHotkey
        }
        isGlobalHotkeyEnabled = UserDefaults.standard.object(forKey: "globalHotkeyEnabled") as? Bool ?? true
    }

    // MARK: - Public API

    /// Start monitoring for the global hotkey
    public func startMonitoring(callback: @escaping () -> Void) {
        self.hotkeyCallback = callback
        setupEventMonitor()
    }

    /// Stop monitoring for the global hotkey
    public func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        hotkeyCallback = nil
    }

    /// Update the global hotkey
    public func setHotkey(_ hotkey: String) {
        globalHotkeyString = hotkey
        UserDefaults.standard.set(hotkey, forKey: "globalHotkey")

        // Restart monitoring with new hotkey
        if let callback = hotkeyCallback {
            stopMonitoring()
            startMonitoring(callback: callback)
        }
    }

    /// Enable or disable the global hotkey
    public func setEnabled(_ enabled: Bool) {
        isGlobalHotkeyEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "globalHotkeyEnabled")

        if enabled, hotkeyCallback != nil {
            setupEventMonitor()
        } else {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }

    // MARK: - Private Methods

    private func setupEventMonitor() {
        guard isGlobalHotkeyEnabled else { return }

        // Remove existing monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Parse the hotkey string to get modifiers and key
        let (modifiers, keyCode) = parseHotkeyString(globalHotkeyString)

        // Create global monitor for key down events
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }

            // Check if the event matches our hotkey
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers &&
               event.keyCode == keyCode {
                Task { @MainActor in
                    self.hotkeyCallback?()
                }
            }
        }

        // Also add local monitor for when app has focus
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers &&
               event.keyCode == keyCode {
                Task { @MainActor in
                    self.hotkeyCallback?()
                }
                return nil  // Consume the event
            }
            return event
        }

        NSLog("⌨️ Global hotkey monitoring started: \(globalHotkeyString)")
    }

    private func parseHotkeyString(_ hotkey: String) -> (NSEvent.ModifierFlags, UInt16) {
        var modifiers: NSEvent.ModifierFlags = []
        var keyCode: UInt16 = 0

        // Parse modifiers
        if hotkey.contains("⌘") || hotkey.lowercased().contains("cmd") {
            modifiers.insert(.command)
        }
        if hotkey.contains("⌥") || hotkey.lowercased().contains("opt") || hotkey.lowercased().contains("alt") {
            modifiers.insert(.option)
        }
        if hotkey.contains("⌃") || hotkey.lowercased().contains("ctrl") {
            modifiers.insert(.control)
        }
        if hotkey.contains("⇧") || hotkey.lowercased().contains("shift") {
            modifiers.insert(.shift)
        }

        // Parse key character (last character after modifiers)
        let keyChar = hotkey.last ?? "`"

        // Map common keys to key codes
        switch keyChar {
        case "`": keyCode = UInt16(kVK_ANSI_Grave)
        case "1": keyCode = UInt16(kVK_ANSI_1)
        case "2": keyCode = UInt16(kVK_ANSI_2)
        case "3": keyCode = UInt16(kVK_ANSI_3)
        case "4": keyCode = UInt16(kVK_ANSI_4)
        case "5": keyCode = UInt16(kVK_ANSI_5)
        case "6": keyCode = UInt16(kVK_ANSI_6)
        case "7": keyCode = UInt16(kVK_ANSI_7)
        case "8": keyCode = UInt16(kVK_ANSI_8)
        case "9": keyCode = UInt16(kVK_ANSI_9)
        case "0": keyCode = UInt16(kVK_ANSI_0)
        case "r", "R": keyCode = UInt16(kVK_ANSI_R)
        case "o", "O": keyCode = UInt16(kVK_ANSI_O)
        case " ": keyCode = UInt16(kVK_Space)
        default: keyCode = UInt16(kVK_ANSI_Grave)  // Default to backtick
        }

        return (modifiers, keyCode)
    }
}

// MARK: - Hotkey Picker View

public struct HotkeyPicker: View {
    @Binding var selectedHotkey: String
    let options: [String]

    public init(selectedHotkey: Binding<String>, options: [String] = ["⌘`", "⌘⇧R", "⌘⌥O", "⌃⌥Space"]) {
        self._selectedHotkey = selectedHotkey
        self.options = options
    }

    public var body: some View {
        Picker("Global Hotkey", selection: $selectedHotkey) {
            ForEach(options, id: \.self) { hotkey in
                Text(hotkey).tag(hotkey)
            }
        }
        .onChange(of: selectedHotkey) { _, newValue in
            KeyboardShortcutManager.shared.setHotkey(newValue)
        }
    }
}
