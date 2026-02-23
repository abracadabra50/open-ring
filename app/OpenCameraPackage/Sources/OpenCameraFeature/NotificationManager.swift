import Foundation
import UserNotifications
import CameraDomain

// MARK: - Notification Manager

public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationManager()

    private let seenEventsKey = "seenEventIds"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    public func requestPermission() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            NSLog("🔔 Notification permission: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            NSLog("🔔 Notification permission error: \(error)")
            return false
        }
    }

    // MARK: - Send Notification

    public func sendNotification(for event: CameraEvent) async {
        let content = UNMutableNotificationContent()

        switch event.kind {
        case .person:
            content.title = "Person"
            content.body = "Person detected at \(event.deviceName)"
            content.sound = .default
        case .motion:
            content.title = "Motion"
            content.body = "Movement at \(event.deviceName)"
            content.sound = .default
        }

        // Add event ID to userInfo for potential click handling
        content.userInfo = ["eventId": event.id]

        let request = UNNotificationRequest(
            identifier: event.id,
            content: content,
            trigger: nil  // Deliver immediately
        )

        do {
            let center = UNUserNotificationCenter.current()
            try await center.add(request)
            NSLog("🔔 Sent notification for \(event.kind.displayName) at \(event.deviceName)")

            // Mark as seen
            markEventAsSeen(event.id)
        } catch {
            NSLog("🔔 Failed to send notification: \(error)")
        }
    }

    // MARK: - Detect New Events

    public func detectNewEvents(old: [CameraEvent], new: [CameraEvent]) -> [CameraEvent] {
        let oldIds = Set(old.map { $0.id })
        let seenIds = getSeenEventIds()
        let twoMinutesAgo = Date().addingTimeInterval(-120)

        return new.filter { event in
            // Must be a new event (not in old list and not previously seen)
            let isNew = !oldIds.contains(event.id) && !seenIds.contains(event.id)
            // Must be recent (within 2 minutes) to avoid spam on launch
            let isRecent = event.createdAt > twoMinutesAgo
            // Only person and motion events
            let isNotifiable = event.kind == .person || event.kind == .motion

            return isNew && isRecent && isNotifiable
        }
    }

    // MARK: - Seen Events Persistence

    private func getSeenEventIds() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: seenEventsKey) ?? []
        return Set(array)
    }

    private func markEventAsSeen(_ eventId: String) {
        var seen = getSeenEventIds()
        seen.insert(eventId)

        // Keep only last 100 events to prevent unbounded growth
        let array = Array(seen.suffix(100))
        UserDefaults.standard.set(array, forKey: seenEventsKey)
    }

    // MARK: - Delegate Methods

    // Handle notification when app is in foreground
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner even when app is open
        return [.banner, .sound]
    }

    // Handle notification tap
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let eventId = response.notification.request.content.userInfo["eventId"] as? String
        NSLog("🔔 Notification tapped for event: \(eventId ?? "unknown")")
        // TODO: Could open popover and show specific event
    }
}
