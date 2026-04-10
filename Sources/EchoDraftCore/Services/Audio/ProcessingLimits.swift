import Foundation

public struct ProcessingLimits: Equatable, Sendable {
    public var maxFileBytes: Int64
    public var maxDurationSeconds: Double

    public static let `default` = ProcessingLimits(maxFileBytes: 500 * 1024 * 1024, maxDurationSeconds: 4 * 60 * 60)

    public init(maxFileBytes: Int64, maxDurationSeconds: Double) {
        self.maxFileBytes = maxFileBytes
        self.maxDurationSeconds = maxDurationSeconds
    }
}
