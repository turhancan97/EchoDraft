import Foundation
import SwiftData

@Model
public final class Recording {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var sourceBookmarkData: Data?
    public var durationSeconds: Double
    public var searchText: String
    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.recording)
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

extension Recording {
    public func recomputeSearchText() {
        searchText = segments.sorted { $0.sortOrder < $1.sortOrder }.map(\.text).joined(separator: " ")
    }

    /// Resolves the original media file from a security-scoped bookmark, if present.
    public func resolvedSourceURL() -> URL? {
        guard let data = sourceBookmarkData else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}
