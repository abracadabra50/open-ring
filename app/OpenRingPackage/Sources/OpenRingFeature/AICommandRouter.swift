import Foundation
import RingClient

// MARK: - AI Command Router
// Routes natural language queries to the appropriate handler

public enum AICommand {
    /// Analyze the current live video frame
    case liveAnalysis(String)
    /// Query event history with Claude
    case eventQuery(String)
    /// Show/play a specific event video
    case showEvent(String)
}

public struct AICommandRouter {
    // Patterns for live analysis
    private static let livePatterns = [
        "now", "right now", "currently", "at the moment",
        "what's there", "who's there", "what do you see",
        "look", "check", "see", "show me now",
        "what's happening", "who's at the door"
    ]

    // Patterns for showing/playing events
    private static let showPatterns = [
        "show", "play", "watch", "see the",
        "last motion", "last ring", "last event",
        "previous", "recent video", "last video"
    ]

    /// Route a natural language query to the appropriate command
    public static func route(_ query: String) -> AICommand {
        let lowercased = query.lowercased()

        // Check for live analysis patterns
        for pattern in livePatterns {
            if lowercased.contains(pattern) {
                return .liveAnalysis(query)
            }
        }

        // Check for show/play patterns
        for pattern in showPatterns {
            if lowercased.contains(pattern) {
                return .showEvent(query)
            }
        }

        // Default to event query
        return .eventQuery(query)
    }

    /// Get a user-friendly description of what the command will do
    public static func describe(_ command: AICommand) -> String {
        switch command {
        case .liveAnalysis:
            return "Analyzing live video..."
        case .eventQuery:
            return "Searching events..."
        case .showEvent:
            return "Finding video..."
        }
    }
}

// MARK: - AI Command Handler
// Executes AI commands and returns results

public actor AICommandHandler {
    public static let shared = AICommandHandler()

    private let aiGuard = AIGuard.shared
    private let visionAnalyzer = VisionAnalyzer.shared

    private init() {}

    /// Execute a command and return the result
    public func execute(
        _ command: AICommand,
        frameData: Data? = nil,
        events: [RingEvent] = []
    ) async throws -> AICommandResult {
        switch command {
        case .liveAnalysis(let query):
            guard let frameData = frameData else {
                return .error("No frame available. Please try again when video is streaming.")
            }

            // Analyze the frame with Vision API
            let description = try await visionAnalyzer.analyze(frameData, prompt: query)
            return .text(description)

        case .eventQuery(let query):
            // Query events with Claude
            let response = try await aiGuard.query(query, events: events)
            return .text(response)

        case .showEvent(let query):
            // Find the most relevant event based on the query
            let event = findRelevantEvent(query: query, events: events)
            if let event = event {
                return .showVideo(event)
            } else {
                return .error("No matching event found.")
            }
        }
    }

    /// Find the most relevant event for a "show" command
    private func findRelevantEvent(query: String, events: [RingEvent]) -> RingEvent? {
        let lowercased = query.lowercased()

        // Filter by event type if specified
        if lowercased.contains("motion") {
            if let event = events.first(where: { $0.kind == .motion }) {
                return event
            }
        }

        if lowercased.contains("ring") || lowercased.contains("doorbell") {
            if let event = events.first(where: { $0.kind == .ding }) {
                return event
            }
        }

        // Default to most recent event
        return events.first
    }
}

// MARK: - AI Command Result

public enum AICommandResult: Sendable {
    /// Text response to display
    case text(String)
    /// Show a video for an event
    case showVideo(RingEvent)
    /// Error message
    case error(String)

    public var isError: Bool {
        if case .error = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .text(let text):
            return text
        case .showVideo(let event):
            return "Playing: \(event.kind.displayName) at \(event.deviceName)"
        case .error(let message):
            return "⚠️ \(message)"
        }
    }
}
