import Foundation

/// Serial queue: processes jobs one at a time with pause/resume/cancel on the active job.
public actor ProcessingQueue {
    public struct Job: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let sourceURL: URL
        public var state: ProcessingJobState

        public init(id: UUID = UUID(), sourceURL: URL, state: ProcessingJobState = .queued) {
            self.id = id
            self.sourceURL = sourceURL
            self.state = state
        }
    }

    private var pending: [Job] = []
    private var isRunning = false
    private var paused = false
    private var cancelled = false

    private let limits: ProcessingLimits
    private let extract: AudioExtractionServicing
    private let transcribe: TranscriptionServicing
    private let diarize: DiarizationServicing

    public var onStateChange: (@Sendable (UUID, ProcessingJobState) async -> Void)?
    public var onCompleted: (@Sendable (UUID, [TimedTextSegment], URL, URL) async -> Void)?

    public init(
        limits: ProcessingLimits = .default,
        extract: AudioExtractionServicing,
        transcribe: TranscriptionServicing,
        diarize: DiarizationServicing
    ) {
        self.limits = limits
        self.extract = extract
        self.transcribe = transcribe
        self.diarize = diarize
    }

    public func setOnStateChange(_ handler: (@Sendable (UUID, ProcessingJobState) async -> Void)?) {
        onStateChange = handler
    }

    public func setOnCompleted(
        _ handler: (@Sendable (UUID, [TimedTextSegment], URL, URL) async -> Void)?
    ) {
        onCompleted = handler
    }

    public func enqueue(_ url: URL) async throws -> UUID {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int64 ?? 0
        guard size <= limits.maxFileBytes else {
            throw ProcessingQueueError.fileTooLarge
        }
        let duration = try await extract.durationSeconds(of: url)
        guard duration <= limits.maxDurationSeconds else {
            throw ProcessingQueueError.durationTooLong
        }
        let job = Job(sourceURL: url)
        pending.append(job)
        await pump()
        return job.id
    }

    public func pause() {
        paused = true
    }

    public func resume() {
        paused = false
    }

    public func cancelActive() {
        cancelled = true
    }

    private func pump() async {
        guard !isRunning else { return }
        guard !pending.isEmpty else { return }
        isRunning = true
        let job = pending.removeFirst()
        await run(job: job)
        isRunning = false
        await pump()
    }

    private func run(job: Job) async {
        // Keep security-scoped access for the whole job (files chosen via NSOpenPanel / sandbox).
        let scoped = job.sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                job.sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        await notify(job.id, .running(progress: 0))
        cancelled = false
        do {
            let audioURL = try await extract.extractAudioToTemporaryFile(from: job.sourceURL)
            try await waitWhilePaused(jobID: job.id)
            if cancelled {
                await notify(job.id, .cancelled)
                return
            }
            let raw = try await transcribe.transcribe(audioFileURL: audioURL) { p in
                Task {
                    await self.notify(job.id, .running(progress: 0.2 + p * 0.5))
                }
            }
            try await waitWhilePaused(jobID: job.id)
            if cancelled {
                await notify(job.id, .cancelled)
                return
            }
            let finalSegs = try await diarize.diarize(segments: raw)
            await onCompleted?(job.id, finalSegs, job.sourceURL, audioURL)
            await notify(job.id, .completed)
        } catch is CancellationError {
            await notify(job.id, .cancelled)
        } catch {
            await notify(job.id, .failed(error.localizedDescription))
        }
    }

    private func waitWhilePaused(jobID: UUID) async throws {
        while paused {
            await notify(jobID, .paused)
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func notify(_ jobID: UUID, _ state: ProcessingJobState) async {
        await onStateChange?(jobID, state)
    }
}

public enum ProcessingQueueError: Error {
    case fileTooLarge
    case durationTooLong
}
