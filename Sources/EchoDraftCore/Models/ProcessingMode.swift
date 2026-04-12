import Foundation

/// How transcription and summarization are performed for a job or stored variant.
public enum ProcessingMode: String, Sendable, Codable, CaseIterable {
    case offline
    case online

    public var displayName: String {
        switch self {
        case .offline: return "Offline"
        case .online: return "Online"
        }
    }
}
