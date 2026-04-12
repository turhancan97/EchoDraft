import Foundation
import SwiftData

// MARK: - TranscriptSegment

@Model
public final class TranscriptSegment {
    @Attribute(.unique) public var id: UUID
    public var startSeconds: Double
    public var endSeconds: Double
    public var text: String
    public var speakerLabel: String
    public var sortOrder: Int
    public var variant: TranscriptVariant?

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

// MARK: - TranscriptVariant

@Model
public final class TranscriptVariant {
    @Attribute(.unique) public var id: UUID
    public var modeRaw: String
    public var createdAt: Date
    public var usageJSON: String?
    public var recording: Recording?
    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.variant)
    public var segments: [TranscriptSegment]

    public init(
        id: UUID = UUID(),
        mode: ProcessingMode,
        createdAt: Date = Date(),
        usageJSON: String? = nil,
        segments: [TranscriptSegment] = []
    ) {
        self.id = id
        self.modeRaw = mode.rawValue
        self.createdAt = createdAt
        self.usageJSON = usageJSON
        self.segments = segments
    }
}

extension TranscriptVariant {
    public var processingMode: ProcessingMode {
        get { ProcessingMode(rawValue: modeRaw) ?? .offline }
        set { modeRaw = newValue.rawValue }
    }
}

// MARK: - Recording

@Model
public final class Recording {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var sourceBookmarkData: Data?
    public var durationSeconds: Double
    public var searchText: String
    @Relationship(deleteRule: .cascade, inverse: \TranscriptVariant.recording)
    public var variants: [TranscriptVariant]
    public var activeVariantID: UUID?
    public var processingModeOverrideRaw: String?

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        sourceBookmarkData: Data? = nil,
        durationSeconds: Double = 0,
        searchText: String = "",
        variants: [TranscriptVariant] = [],
        activeVariantID: UUID? = nil,
        processingModeOverrideRaw: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.sourceBookmarkData = sourceBookmarkData
        self.durationSeconds = durationSeconds
        self.searchText = searchText
        self.variants = variants
        self.activeVariantID = activeVariantID
        self.processingModeOverrideRaw = processingModeOverrideRaw
    }
}

extension Recording {
    public func activeSegmentsSorted() -> [TranscriptSegment] {
        if let aid = activeVariantID,
            let v = variants.first(where: { $0.id == aid })
        {
            return v.segments.sorted { $0.sortOrder < $1.sortOrder }
        }
        if let v = variants.sorted(by: { $0.createdAt > $1.createdAt }).first {
            return v.segments.sorted { $0.sortOrder < $1.sortOrder }
        }
        return []
    }

    public func recomputeSearchText() {
        searchText = activeSegmentsSorted().map(\.text).joined(separator: " ")
    }

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
