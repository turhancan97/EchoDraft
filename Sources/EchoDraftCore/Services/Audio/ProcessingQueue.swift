import Foundation

/// Serial queue: processes jobs one at a time with pause/resume/cancel on the active job.
public actor ProcessingQueue {
    public struct Job: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let sourceURL: URL
        public let mode: ProcessingMode
        /// When set, completed segments are appended as a new variant on this recording (re-transcribe).
        public let mergeIntoRecordingID: UUID?
        public var state: ProcessingJobState

        public init(
            id: UUID = UUID(),
            sourceURL: URL,
            mode: ProcessingMode,
            mergeIntoRecordingID: UUID? = nil,
            state: ProcessingJobState = .queued
        ) {
            self.id = id
            self.sourceURL = sourceURL
            self.mode = mode
            self.mergeIntoRecordingID = mergeIntoRecordingID
            self.state = state
        }
    }

    private var pending: [Job] = []
    private var isRunning = false
    private var paused = false
    private var cancelled = false

    private let limits: ProcessingLimits
    private let extract: AudioExtractionServicing
    private let offlineTranscribe: TranscriptionServicing
    private let onlineTranscribe: TranscriptionServicing
    private let offlineDiarize: DiarizationServicing
    private let onlineDiarize: DiarizationServicing

    public var onStateChange: (@Sendable (UUID, ProcessingJobState) async -> Void)?
    public var onCompleted:
        (@Sendable (UUID, [TimedTextSegment], URL, URL, ProcessingMode, UUID?) async -> Void)?

    public init(
        limits: ProcessingLimits = .default,
        extract: AudioExtractionServicing,
        offlineTranscribe: TranscriptionServicing,
        onlineTranscribe: TranscriptionServicing,
        offlineDiarize: DiarizationServicing,
        onlineDiarize: DiarizationServicing
    ) {
        self.limits = limits
        self.extract = extract
        self.offlineTranscribe = offlineTranscribe
        self.onlineTranscribe = onlineTranscribe
        self.offlineDiarize = offlineDiarize
        self.onlineDiarize = onlineDiarize
    }

    public func setOnStateChange(_ handler: (@Sendable (UUID, ProcessingJobState) async -> Void)?) {
        onStateChange = handler
    }

    public func setOnCompleted(
        _ handler:
            (@Sendable (UUID, [TimedTextSegment], URL, URL, ProcessingMode, UUID?) async -> Void)?
    ) {
        onCompleted = handler
    }

    public func enqueue(_ url: URL, mode: ProcessingMode, mergeIntoRecordingID: UUID? = nil) async throws
        -> UUID
    {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int64 ?? 0
        guard size <= limits.maxFileBytes else {
            throw ProcessingQueueError.fileTooLarge
        }
        let duration = try await extract.durationSeconds(of: url)
        guard duration <= limits.maxDurationSeconds else {
            throw ProcessingQueueError.durationTooLong
        }
        let job = Job(sourceURL: url, mode: mode, mergeIntoRecordingID: mergeIntoRecordingID)
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
        var extractedAudioURL: URL?
        defer {
            Self.cleanupTemporaryAudioArtifact(at: extractedAudioURL)
        }
        do {
            let audioURL = try await extract.extractAudioToTemporaryFile(from: job.sourceURL)
            extractedAudioURL = audioURL
            try await waitWhilePaused(jobID: job.id)
            if cancelled {
                await notify(job.id, .cancelled)
                return
            }
            let transcriber = job.mode == .online ? onlineTranscribe : offlineTranscribe
            let raw = try await transcriber.transcribe(audioFileURL: audioURL) { p in
                Task {
                    await self.notify(job.id, .running(progress: 0.2 + p * 0.5))
                }
            }
            try await waitWhilePaused(jobID: job.id)
            if cancelled {
                await notify(job.id, .cancelled)
                return
            }
            let diarizeService = job.mode == .online ? onlineDiarize : offlineDiarize
            let finalSegs = try await diarizeService.diarize(segments: raw)
            await onCompleted?(job.id, finalSegs, job.sourceURL, audioURL, job.mode, job.mergeIntoRecordingID)
            await notify(job.id, .completed)
        } catch is CancellationError {
            await notify(job.id, .cancelled)
        } catch {
            await notify(job.id, .failed(error.localizedDescription))
        }
    }

    private func waitWhilePaused(jobID: UUID) async throws {
        while paused {
            if cancelled {
                throw CancellationError()
            }
            await notify(jobID, .paused)
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func notify(_ jobID: UUID, _ state: ProcessingJobState) async {
        await onStateChange?(jobID, state)
    }

    private static func cleanupTemporaryAudioArtifact(at url: URL?) {
        guard let url else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: url.deletingLastPathComponent())
    }
}

public enum ProcessingQueueError: Error {
    case fileTooLarge
    case durationTooLong
}
