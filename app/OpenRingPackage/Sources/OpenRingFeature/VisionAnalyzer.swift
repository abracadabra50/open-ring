import Foundation
import RingClient

// MARK: - Vision Analyzer
// Uses Claude Vision API to analyze doorbell snapshots

public actor VisionAnalyzer {
    public static let shared = VisionAnalyzer()

    private let keychain = KeychainManager.shared

    private init() {}

    // MARK: - Analyze Snapshot

    /// Analyze a doorbell snapshot and return a description of what's visible
    public func analyze(_ imageData: Data) async throws -> String {
        return try await analyze(imageData, prompt: nil)
    }

    /// Analyze a doorbell snapshot with a custom prompt/question
    public func analyze(_ imageData: Data, prompt: String?) async throws -> String {
        guard let apiKey = try await keychain.getAnthropicAPIKey() else {
            throw VisionError.noAPIKey
        }

        // Convert image to base64
        let base64Image = imageData.base64EncodedString()

        // Determine media type (assume JPEG for snapshots)
        let mediaType = "image/jpeg"

        // Build request
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Build prompt - use custom prompt if provided, otherwise use default description
        let textPrompt: String
        if let customPrompt = prompt {
            textPrompt = """
            This is a live doorbell/security camera image. Answer this question about what you see:

            \(customPrompt)

            Be concise and direct. Focus only on what's visible in the image.
            """
        } else {
            textPrompt = """
            This is a doorbell camera snapshot. Briefly describe what you see:
            - Who or what is at the door? (person, package, animal, nobody)
            - If a person: describe their appearance (clothing, build, what they're carrying)
            - What are they doing? (waiting, leaving, delivering package)
            - Any vehicles visible?
            Keep it concise - 1-2 sentences max.
            """
        }

        let payload: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 300,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": mediaType,
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": textPrompt
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw VisionError.apiError(message)
            }
            throw VisionError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw VisionError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Vision Errors

public enum VisionError: Error, LocalizedError {
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
