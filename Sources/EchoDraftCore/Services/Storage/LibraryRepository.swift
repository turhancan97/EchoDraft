import Foundation

public protocol LibraryRepository: Sendable {
    func insert(_ recording: Recording) throws
    func delete(_ recording: Recording) throws
    func fetchAll() throws -> [Recording]
    func search(_ query: String) throws -> [Recording]
    func clearEverything() throws
}
