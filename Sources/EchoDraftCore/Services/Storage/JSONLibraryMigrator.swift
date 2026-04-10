import Foundation
import SwiftData

private let migrationFlagKey = "didMigrateJSONToSwiftData"

/// One-shot migration from legacy `library.json` (Codable structs) into SwiftData.
@MainActor
public struct JSONLibraryMigrator: Sendable {
    public init() {}

    public func migrateIfNeeded(modelContext: ModelContext, fileURL: URL? = nil) throws {
        guard !UserDefaults.standard.bool(forKey: migrationFlagKey) else { return }

        let url: URL = fileURL ?? defaultLibraryJSONURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            UserDefaults.standard.set(true, forKey: migrationFlagKey)
            return
        }

        let data = try Data(contentsOf: url)
        let legacy = try JSONDecoder().decode([LegacyRecording].self, from: data)

        for item in legacy {
            let rec = Recording(
                id: item.id,
                title: item.title,
                createdAt: item.createdAt,
                sourceBookmarkData: item.sourceBookmarkData,
                durationSeconds: item.durationSeconds,
                searchText: item.searchText,
                segments: []
            )
            var segs: [TranscriptSegment] = []
            for s in item.segments.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let seg = TranscriptSegment(
                    id: s.id,
                    startSeconds: s.startSeconds,
                    endSeconds: s.endSeconds,
                    text: s.text,
                    speakerLabel: s.speakerLabel,
                    sortOrder: s.sortOrder
                )
                seg.recording = rec
                segs.append(seg)
            }
            rec.segments = segs
            rec.recomputeSearchText()
            modelContext.insert(rec)
        }

        try modelContext.save()

        let migrated = url.deletingLastPathComponent().appendingPathComponent("library.json.migrated")
        try? FileManager.default.removeItem(at: migrated)
        try FileManager.default.moveItem(at: url, to: migrated)

        UserDefaults.standard.set(true, forKey: migrationFlagKey)
    }

    private func defaultLibraryJSONURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let dir = base.appendingPathComponent("EchoDraft", isDirectory: true)
        return dir.appendingPathComponent("library.json")
    }
}

/// Legacy JSON shape (pre–SwiftData).
private struct LegacyRecording: Codable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var sourceBookmarkData: Data?
    var durationSeconds: Double
    var searchText: String
    var segments: [LegacyTranscriptSegment]
}

private struct LegacyTranscriptSegment: Codable, Sendable {
    var id: UUID
    var startSeconds: Double
    var endSeconds: Double
    var text: String
    var speakerLabel: String
    var sortOrder: Int
}
