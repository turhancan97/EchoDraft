import Foundation

@MainActor
public protocol LibraryRepository: AnyObject {
    func insert(_ recording: Recording) throws
    func delete(_ recording: Recording) throws
    func fetchAll() throws -> [Recording]
    func search(_ query: String) throws -> [Recording]
    func clearEverything() throws
    func save() throws
}
