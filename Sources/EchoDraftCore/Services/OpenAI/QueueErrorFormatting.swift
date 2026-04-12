import Foundation

/// User-facing copy for processing queue failures (not MainActor-isolated).
public enum QueueErrorFormatting {
    public static func humanize(_ message: String) -> String {
        if message.localizedCaseInsensitiveContains("rate limit")
            || message.localizedCaseInsensitiveContains("429")
        {
            return "OpenAI rate limit: wait a minute or check your account quota, then try again."
        }
        return message
    }
}
