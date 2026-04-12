import Foundation
import OSLog

/// Optional failure logging when telemetry is enabled (no transcript content).
public enum EchoDraftTelemetry {
    private static let log = Logger(subsystem: "com.echodraft", category: "online")
    private static let telemetryKey = "echodraft.telemetryOptIn"

    public static func logOnlineFailure(_ message: String) {
        guard UserDefaults.standard.bool(forKey: telemetryKey) else { return }
        log.error("online: \(message, privacy: .public)")
    }
}
