import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
public enum MacSavePanel {
    /// Writes data after the user confirms a path in ``NSSavePanel``.
    public static func save(
        data: Data,
        suggestedFilename: String,
        allowedTypes: [UTType]
    ) throws -> URL {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        guard panel.runModal() == .OK, let url = panel.url else {
            throw CancellationError()
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Copies an existing file (e.g. temp ZIP) to a user-chosen location.
    public static func copyFile(from sourceURL: URL, suggestedFilename: String, allowedTypes: [UTType]) throws -> URL {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        guard panel.runModal() == .OK, let dest = panel.url else {
            throw CancellationError()
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: sourceURL, to: dest)
        return dest
    }
}
