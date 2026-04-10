import Foundation
import SwiftData

@MainActor
public final class SwiftDataLibraryRepository: LibraryRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func insert(_ recording: Recording) throws {
        modelContext.insert(recording)
        try modelContext.save()
    }

    public func delete(_ recording: Recording) throws {
        modelContext.delete(recording)
        try modelContext.save()
    }

    public func fetchAll() throws -> [Recording] {
        let desc = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(desc)
    }

    public func search(_ query: String) throws -> [Recording] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = try fetchAll()
        if trimmed.isEmpty { return all }
        return all.filter { r in
            r.title.localizedStandardContains(trimmed)
                || r.searchText.localizedStandardContains(trimmed)
        }
    }

    public func clearEverything() throws {
        let all = try fetchAll()
        for r in all {
            modelContext.delete(r)
        }
        try modelContext.save()
    }

    public func save() throws {
        try modelContext.save()
    }
}
