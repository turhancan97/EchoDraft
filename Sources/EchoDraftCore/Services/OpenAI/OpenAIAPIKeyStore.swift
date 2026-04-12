import Foundation
import Security

/// Stores the OpenAI API key in the macOS Keychain (service-scoped).
public enum OpenAIAPIKeyStore {
    private static let service = "com.echodraft.openai.apikey"
    private static let account = "default"

    public static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
            let string = String(data: data, encoding: .utf8),
            !string.isEmpty
        else {
            return nil
        }
        return string
    }

    /// DEBUG: optional override from environment (never used in Release for security).
    public static func resolvedKey() -> String? {
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !env.isEmpty
        {
            return env
        }
        #endif
        return load()
    }

    public static func save(_ key: String) throws {
        let data = Data(key.utf8)
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OpenAIKeychainError.saveFailed(status)
        }
    }

    public static func delete() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}

public enum OpenAIKeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let code):
            return "Could not save API key to Keychain (error \(code))."
        }
    }
}
