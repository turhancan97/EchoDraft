import Foundation

/// User-facing copy for processing queue failures (not MainActor-isolated).
public enum QueueErrorFormatting {
    public static func humanize(_ message: String) -> String {
        if message.localizedCaseInsensitiveContains("rate limit")
            || message.localizedCaseInsensitiveContains("429")
        {
            return "OpenAI rate limit: wait a minute or check your account quota, then try again."
        }
        if message.localizedCaseInsensitiveContains("413")
            || message.localizedCaseInsensitiveContains("payload too large")
            || message.localizedCaseInsensitiveContains("too large")
        {
            return "Upload too large for the API (HTTP 413). Very long or high‑bitrate audio is split automatically — try processing again. If it persists, trim the file or use a lower bitrate export."
        }
        if message.localizedCaseInsensitiveContains("timed out")
            || message.localizedCaseInsensitiveContains("timeout")
            || message.localizedCaseInsensitiveContains("network connection was lost")
        {
            return "The transcription request took too long (network or server). Check your connection and try again; very long files are processed in parts and can take several minutes per part."
        }
        return message
    }
}
