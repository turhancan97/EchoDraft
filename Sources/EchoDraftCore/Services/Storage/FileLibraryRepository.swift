import Foundation

public final class FileLibraryRepository: LibraryRepository, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(fileURL: URL? = nil) {
        if let fileURL {
            url = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
            let dir = base.appendingPathComponent("EchoDraft", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent("library.json")
        }
    }

    private func load() throws -> [Recording] {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Recording].self, from: data)
    }

    private func save(_ items: [Recording]) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try JSONEncoder().encode(items)
        try data.write(to: url, options: .atomic)
    }

    public func insert(_ recording: Recording) throws {
        var all = try load()
        all.append(recording)
        try save(all)
    }

    public func delete(_ recording: Recording) throws {
        var all = try load()
        all.removeAll { $0.id == recording.id }
        try save(all)
    }

    public func fetchAll() throws -> [Recording] {
        try load().sorted { $0.createdAt > $1.createdAt }
    }

    public func search(_ query: String) throws -> [Recording] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = try load()
        if trimmed.isEmpty { return all.sorted { $0.createdAt > $1.createdAt } }
        return all.filter { r in
            r.title.localizedStandardContains(trimmed)
                || r.searchText.localizedStandardContains(trimmed)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    public func clearEverything() throws {
        try save([])
    }
}
