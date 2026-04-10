import Foundation

public protocol ModelDownloadServicing: Sendable {
    func downloadIfNeeded(
        from url: URL,
        to destinationDirectory: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL
}

public enum ModelDownloadError: Error {
    case invalidHTTPStatus(Int)
    case fileSystem(String)
}

public final class ModelDownloadService: ModelDownloadServicing, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func downloadIfNeeded(
        from url: URL,
        to destinationDirectory: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let fileName = url.lastPathComponent.isEmpty ? "download.bin" : url.lastPathComponent
        let destURL = destinationDirectory.appendingPathComponent(fileName)
        if fm.fileExists(atPath: destURL.path) {
            progress(1)
            return destURL
        }
        let (asyncBytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModelDownloadError.invalidHTTPStatus(code)
        }
        let total = http.expectedContentLength > 0 ? Double(http.expectedContentLength) : nil
        var received: Int64 = 0
        var data = Data()
        data.reserveCapacity(Int(http.expectedContentLength))
        for try await byte in asyncBytes {
            data.append(byte)
            received += 1
            if let total {
                progress(min(1, Double(received) / total))
            }
        }
        do {
            try data.write(to: destURL, options: .atomic)
        } catch {
            throw ModelDownloadError.fileSystem(error.localizedDescription)
        }
        progress(1)
        return destURL
    }
}
