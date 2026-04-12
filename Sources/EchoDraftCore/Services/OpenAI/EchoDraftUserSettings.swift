import Foundation
import Observation

/// User defaults for global processing mode, OpenAI endpoint, privacy, and telemetry.
@MainActor
@Observable
public final class EchoDraftUserSettings {
    public static let shared = EchoDraftUserSettings()

    private let defaults = UserDefaults.standard

    fileprivate enum Keys {
        static let globalMode = "echodraft.globalProcessingMode"
        static let baseURL = "echodraft.openaiBaseURL"
        static let privacyAcknowledged = "echodraft.onlinePrivacyAcknowledged"
        static let telemetryOptIn = "echodraft.telemetryOptIn"
    }

    /// Thread-safe reads for ``Sendable`` services (no MainActor).
    public nonisolated static func storedOpenAIBaseURL() -> String {
        let s = UserDefaults.standard.string(forKey: Keys.baseURL)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s, !s.isEmpty { return s.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        return "https://api.openai.com"
    }

    public nonisolated static func storedGlobalMode() -> ProcessingMode {
        ProcessingMode(rawValue: UserDefaults.standard.string(forKey: Keys.globalMode) ?? "") ?? .offline
    }

    public var globalProcessingMode: ProcessingMode {
        get {
            ProcessingMode(rawValue: defaults.string(forKey: Keys.globalMode) ?? "") ?? .offline
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.globalMode)
        }
    }

    /// Host base, e.g. `https://api.openai.com` (no trailing path).
    public var openAIBaseURL: String {
        get {
            let s = defaults.string(forKey: Keys.baseURL)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let s, !s.isEmpty { return s.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            return "https://api.openai.com"
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.baseURL)
        }
    }

    public var onlinePrivacyAcknowledged: Bool {
        get { defaults.bool(forKey: Keys.privacyAcknowledged) }
        set { defaults.set(newValue, forKey: Keys.privacyAcknowledged) }
    }

    public var telemetryOptIn: Bool {
        get { defaults.bool(forKey: Keys.telemetryOptIn) }
        set { defaults.set(newValue, forKey: Keys.telemetryOptIn) }
    }

    public init() {}

    public func effectiveMode(for recording: Recording?) -> ProcessingMode {
        if let raw = recording?.processingModeOverrideRaw,
            let m = ProcessingMode(rawValue: raw)
        {
            return m
        }
        return globalProcessingMode
    }

    public func canRunOnline(for recording: Recording?) -> Bool {
        guard effectiveMode(for: recording) == .online else { return true }
        return OpenAIAPIKeyStore.resolvedKey() != nil
    }
}
