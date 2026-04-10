import Foundation

public struct TranscriptSegment: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var startSeconds: Double
    public var endSeconds: Double
    public var text: String
    public var speakerLabel: String
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        startSeconds: Double,
        endSeconds: Double,
        text: String,
        speakerLabel: String,
        sortOrder: Int
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.speakerLabel = speakerLabel
        self.sortOrder = sortOrder
    }
}
