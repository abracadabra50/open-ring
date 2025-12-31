import Foundation
import Security

// MARK: - Keychain Manager

public actor KeychainManager {
    public static let shared = KeychainManager()

    private let service = "dev.open-ring"

    private init() {}

    // MARK: - Token Storage

    public func saveRefreshToken(_ token: String) throws {
        try save(key: "refresh_token", value: token)
    }

    public func getRefreshToken() throws -> String? {
        try get(key: "refresh_token")
    }

    public func saveAccessToken(_ token: String, expiresIn: Int) throws {
        try save(key: "access_token", value: token)
        let expirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        try save(key: "access_token_expires", value: String(expirationDate.timeIntervalSince1970))
    }

    public func getAccessToken() throws -> String? {
        // Check if token is expired
        if let expiresString = try get(key: "access_token_expires"),
           let expires = Double(expiresString) {
            let expirationDate = Date(timeIntervalSince1970: expires)
            if expirationDate < Date() {
                // Token expired, remove it
                try? delete(key: "access_token")
                try? delete(key: "access_token_expires")
                return nil
            }
        }
        return try get(key: "access_token")
    }

    public func saveHardwareId(_ id: String) throws {
        try save(key: "hardware_id", value: id)
    }

    public func getHardwareId() throws -> String {
        if let existing = try get(key: "hardware_id") {
            return existing
        }
        // Generate new hardware ID
        let newId = UUID().uuidString
        try save(key: "hardware_id", value: newId)
        return newId
    }

    public func clearAll() throws {
        try delete(key: "refresh_token")
        try delete(key: "access_token")
        try delete(key: "access_token_expires")
    }

    // MARK: - Anthropic API Key

    public func saveAnthropicAPIKey(_ key: String) throws {
        try save(key: "anthropic_api_key", value: key)
    }

    public func getAnthropicAPIKey() throws -> String? {
        try get(key: "anthropic_api_key")
    }

    public func deleteAnthropicAPIKey() throws {
        try delete(key: "anthropic_api_key")
    }

    // MARK: - Generic Keychain Operations

    private func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Try to delete existing item first
        try? delete(key: key)

        // Create access control that allows this app without prompting
        var access: SecAccess?
        var trustedApps: CFArray?

        // Get the current application as a trusted app
        var selfApp: SecTrustedApplication?
        let selfStatus = SecTrustedApplicationCreateFromPath(nil, &selfApp)
        if selfStatus == errSecSuccess, let app = selfApp {
            trustedApps = [app] as CFArray
        }

        let accessStatus = SecAccessCreate(
            "OpenRing Keychain Access" as CFString,
            trustedApps,
            &access
        )

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Add access control if created successfully
        if accessStatus == errSecSuccess, let access = access {
            query[kSecAttrAccess as String] = access
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func get(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.decodingFailed
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.readFailed(status)
        }
    }

    private func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Keychain Errors

public enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for keychain"
        case .decodingFailed:
            return "Failed to decode data from keychain"
        case .saveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .readFailed(let status):
            return "Failed to read from keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(status)"
        }
    }
}
