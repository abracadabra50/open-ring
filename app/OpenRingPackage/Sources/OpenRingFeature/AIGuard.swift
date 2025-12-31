import Foundation
import RingClient
import Storage

// MARK: - AI Guard
// Answers questions about doorbell events using Claude

public actor AIGuard {
    public static let shared = AIGuard()

    private let keychain = KeychainManager.shared
    private let storage = StorageManager.shared
    private let visionAnalyzer = VisionAnalyzer.shared

    private init() {}

    // MARK: - Query Events

    /// Answer a question about recent doorbell events (using Ring API events directly)
    public func query(_ question: String, events: [RingEvent]) async throws -> String {
        guard let apiKey = try await keychain.getAnthropicAPIKey() else {
            throw GuardError.noAPIKey
        }

        if events.isEmpty {
            return "No events recorded recently."
        }

        // Format Ring events for context
        let eventContext = formatRingEvents(events)

        // Build request
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let payload: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 500,
            "messages": [
                [
                    "role": "user",
                    "content": """
                    You are a helpful assistant for a Ring doorbell app. Answer questions about recent events.

                    Recent doorbell events (newest first):
                    \(eventContext)

                    User question: \(question)

                    Answer based only on the events above. Be concise and helpful.
                    If the AI description is empty for an event, just mention the event type and time.
                    """
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GuardError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw GuardError.apiError(message)
            }
            throw GuardError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw GuardError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Process New Event

    /// Analyze a new event's snapshot and store the description
    public func processEvent(_ event: RingEvent, deviceId: Int) async throws {
        // Check if already processed
        if try storage.hasDescription(eventId: event.id) {
            return
        }

        // Get snapshot
        let snapshotData = try await RingClient.shared.getSnapshot(deviceId: deviceId)

        // Analyze with vision
        let description = try await visionAnalyzer.analyze(snapshotData)

        // Store the event and description
        try storage.saveEvent(
            id: event.id,
            deviceId: String(deviceId),
            kind: event.kind.rawValue,
            createdAt: event.createdAt,
            deviceName: event.deviceName
        )
        try storage.updateEventDescription(event.id, description: description)

        NSLog("AI Guard: Analyzed event \(event.id): \(description)")
    }

    // MARK: - Helpers

    private func formatRingEvents(_ events: [RingEvent]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"

        return events.map { event in
            let time = formatter.string(from: event.createdAt)
            let device = event.deviceName
            let type = event.kind.displayName

            return "[\(time)] \(type) at \(device)"
        }.joined(separator: "\n")
    }

    private func formatEvents(_ events: [StoredEvent]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"

        return events.map { event in
            let time = formatter.string(from: event.createdAt)
            let device = event.deviceName ?? "Unknown camera"
            let type = event.kindDisplayName
            let description = event.aiDescription ?? "(no description)"

            return "[\(time)] \(type) at \(device): \(description)"
        }.joined(separator: "\n")
    }
}

// MARK: - Guard Errors

public enum GuardError: Error, LocalizedError {
    case noAPIKey
    case networkError
    case apiError(String)
    case parseError

    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Anthropic API key configured. Add it in Settings."
        case .networkError:
            return "Network error connecting to Claude API"
        case .apiError(let message):
            return "Claude API error: \(message)"
        case .parseError:
            return "Failed to parse Claude response"
        }
    }
}
