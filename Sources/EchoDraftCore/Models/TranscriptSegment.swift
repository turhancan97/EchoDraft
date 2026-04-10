import Foundation
import SwiftData

@Model
public final class TranscriptSegment {
    @Attribute(.unique) public var id: UUID
    public var startSeconds: Double
    public var endSeconds: Double
    public var text: String
    public var speakerLabel: String
    public var sortOrder: Int
    public var recording: Recording?

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
