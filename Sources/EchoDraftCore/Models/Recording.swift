import Foundation

/// Persisted recording with transcript segments (Codable JSON store; SwiftData can replace this in an Xcode target).
public struct Recording: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var sourceBookmarkData: Data?
    public var durationSeconds: Double
    public var searchText: String
    public var segments: [TranscriptSegment]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        sourceBookmarkData: Data? = nil,
        durationSeconds: Double = 0,
        searchText: String = "",
        segments: [TranscriptSegment] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.sourceBookmarkData = sourceBookmarkData
        self.durationSeconds = durationSeconds
        self.searchText = searchText
        self.segments = segments
    }
}
