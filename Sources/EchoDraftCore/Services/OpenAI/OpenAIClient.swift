import Foundation

// MARK: - Errors

public enum OpenAIClientError: Error, LocalizedError, Sendable {
    case invalidURL
    case httpStatus(Int)
    case rateLimited(retryAfterSeconds: Double?)
    case decodingFailed(String)
    case noData

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OpenAI API URL."
        case .httpStatus(let code):
            if code == 413 {
                return "Audio upload too large for one request (HTTP 413). The app normally splits long files automatically — try again, or use a shorter or more compressed export."
            }
            return "OpenAI API error (status \(code))."
        case .rateLimited(let s):
            if let s {
                return "Rate limited. Retry after \(Int(s)) seconds."
            }
            return "Rate limited. Please wait and try again."
        case .decodingFailed(let msg):
            return "Could not read API response: \(msg)"
        case .noData:
            return "Empty response from API."
        }
    }
}

// MARK: - Protocol

public protocol OpenAIClienting: Sendable {
    func transcribeAudio(
        fileURL: URL,
        apiKey: String,
        baseURL: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult

    func chatCompletion(
        apiKey: String,
        baseURL: String,
        model: String,
        messages: [[String: String]],
        temperature: Double
    ) async throws -> ChatCompletionResult
}

public struct TranscriptionResult: Sendable {
    public var text: String
    public var segments: [TranscriptionSegmentDTO]
    public var durationSeconds: Double?

    public init(text: String, segments: [TranscriptionSegmentDTO], durationSeconds: Double? = nil) {
        self.text = text
        self.segments = segments
        self.durationSeconds = durationSeconds
    }
}

public struct TranscriptionSegmentDTO: Sendable {
    public var start: Double
    public var end: Double
    public var text: String
    /// Raw speaker id from `diarized_json` (e.g. `SPEAKER_00`). Nil when the API omits it.
    public var speakerKey: String?

    public init(start: Double, end: Double, text: String, speakerKey: String? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.speakerKey = speakerKey
    }
}

public struct ChatCompletionResult: Sendable {
    public var content: String
    public var promptTokens: Int?
    public var completionTokens: Int?

    public init(content: String, promptTokens: Int? = nil, completionTokens: Int? = nil) {
        self.content = content
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

// MARK: - Live client

public final class OpenAIClient: OpenAIClienting, @unchecked Sendable {
    /// Default `URLSession` uses a ~60s per-request timeout, which fails on large uploads and long
    /// `gpt-4o-transcribe-diarize` jobs. Transcription uses a session with multi-minute (up to 1h) limits.
    private static let transcriptionSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    public init() {}

    public func transcribeAudio(
        fileURL: URL,
        apiKey: String,
        baseURL: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        let endpoint = try Self.joinBase(baseURL, path: "/v1/audio/transcriptions")
        let boundary = "Boundary-\(UUID().uuidString)"
        let multipartFile = try Self.createMultipartUploadFile(audioFileURL: fileURL, boundary: boundary)
        defer {
            try? FileManager.default.removeItem(at: multipartFile)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        progress(0.1)
        let (respData, response) = try await dataWithRetries(
            request: request,
            bodyFileURL: multipartFile,
            session: Self.transcriptionSession
        )
        progress(0.92)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIClientError.noData
        }
        if http.statusCode == 429 {
            let retry = http.value(forHTTPHeaderField: "retry-after").flatMap { Double($0) }
            throw OpenAIClientError.rateLimited(retryAfterSeconds: retry)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OpenAIClientError.httpStatus(http.statusCode)
        }

        let decoded = try parseDiarizedJSON(data: respData)
        progress(1)
        return decoded
    }

    public func chatCompletion(
        apiKey: String,
        baseURL: String,
        model: String,
        messages: [[String: String]],
        temperature: Double
    ) async throws -> ChatCompletionResult {
        let endpoint = try Self.joinBase(baseURL, path: "/v1/chat/completions")
        let payload: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await dataWithRetries(request: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIClientError.noData }
        if http.statusCode == 429 {
            let retry = http.value(forHTTPHeaderField: "retry-after").flatMap { Double($0) }
            throw OpenAIClientError.rateLimited(retryAfterSeconds: retry)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OpenAIClientError.httpStatus(http.statusCode)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw OpenAIClientError.decodingFailed("chat completions shape")
        }
        var pt: Int?
        var ct: Int?
        if let usage = obj["usage"] as? [String: Any] {
            pt = usage["prompt_tokens"] as? Int
            ct = usage["completion_tokens"] as? Int
        }
        return ChatCompletionResult(content: content, promptTokens: pt, completionTokens: ct)
    }

    private func dataWithRetries(
        request: URLRequest,
        bodyFileURL: URL? = nil,
        session: URLSession = .shared
    ) async throws -> (Data, URLResponse) {
        var attempt = 0
        let maxAttempts = 4
        var delayNs: UInt64 = 500_000_000
        while true {
            attempt += 1
            let (data, response): (Data, URLResponse)
            if let bodyFileURL {
                (data, response) = try await session.upload(for: request, fromFile: bodyFileURL)
            } else {
                (data, response) = try await session.data(for: request)
            }
            guard let http = response as? HTTPURLResponse else {
                throw OpenAIClientError.noData
            }
            if http.statusCode == 429, attempt < maxAttempts {
                let ra = http.value(forHTTPHeaderField: "retry-after").flatMap { Double($0) } ?? 2
                try await Task.sleep(nanoseconds: UInt64(ra * 1_000_000_000))
                continue
            }
            if (500 ... 599).contains(http.statusCode), attempt < maxAttempts {
                try await Task.sleep(nanoseconds: delayNs)
                delayNs *= 2
                continue
            }
            return (data, response)
        }
    }

    private static func joinBase(_ base: String, path: String) throws -> URL {
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let p = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let full = "\(b)/\(p)"
        guard let url = URL(string: full) else { throw OpenAIClientError.invalidURL }
        return url
    }

    static func createMultipartUploadFile(audioFileURL: URL, boundary: String) throws -> URL {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("echodraft-openai-upload-\(UUID().uuidString).tmp")
        fm.createFile(atPath: tmp.path, contents: nil)
        let writer = try FileHandle(forWritingTo: tmp)
        defer {
            try? writer.close()
        }

        func write(_ text: String) throws {
            try writer.write(contentsOf: Data(text.utf8))
        }

        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
        try write("Content-Type: audio/m4a\r\n\r\n")

        let reader = try FileHandle(forReadingFrom: audioFileURL)
        defer {
            try? reader.close()
        }
        while true {
            let chunk = try reader.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try writer.write(contentsOf: chunk)
        }

        try write("\r\n")
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        try write("gpt-4o-transcribe-diarize\r\n")
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        try write("diarized_json\r\n")
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"chunking_strategy\"\r\n\r\n")
        try write("auto\r\n")
        try write("--\(boundary)--\r\n")
        return tmp
    }

    private func parseDiarizedJSON(data: Data) throws -> TranscriptionResult {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIClientError.decodingFailed("root")
        }
        let text = obj["text"] as? String ?? ""
        var segs: [TranscriptionSegmentDTO] = []
        if let arr = obj["segments"] as? [[String: Any]] {
            for s in arr {
                let st = s["start"] as? Double ?? 0
                let en = s["end"] as? Double ?? st
                let t = s["text"] as? String ?? ""
                let key = Self.normalizedSpeakerKey(s["speaker"])
                segs.append(
                    TranscriptionSegmentDTO(
                        start: st,
                        end: en,
                        text: t.trimmingCharacters(in: .whitespacesAndNewlines),
                        speakerKey: key
                    )
                )
            }
        }
        if segs.isEmpty, !text.isEmpty {
            let dur = obj["duration"] as? Double
            segs.append(TranscriptionSegmentDTO(start: 0, end: dur ?? 0, text: text, speakerKey: "0"))
        }
        let dur = obj["duration"] as? Double
        return TranscriptionResult(text: text, segments: segs, durationSeconds: dur)
    }

    private static func normalizedSpeakerKey(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        if let n = value as? Int {
            return String(n)
        }
        if let d = value as? Double, d.isFinite {
            return String(Int(d))
        }
        return nil
    }
}
