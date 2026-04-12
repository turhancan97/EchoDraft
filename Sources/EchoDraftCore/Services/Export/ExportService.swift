import AppKit
import Foundation
import ZIPFoundation

@MainActor
public protocol ExportServicing: AnyObject {
    func markdown(for recording: Recording) -> String
    func pdfData(for recording: Recording) throws -> Data
    func zipTranscriptAndAudio(recording: Recording, audioURL: URL?) throws -> URL
    func shareToNotes(markdown: String, from window: NSWindow?)
}

@MainActor
public final class ExportService: ExportServicing {
    public init() {}

    public func markdown(for recording: Recording) -> String {
        var lines: [String] = ["# \(recording.title)", ""]
        for seg in recording.activeSegmentsSorted() {
            let t0 = formatTime(seg.startSeconds)
            let t1 = formatTime(seg.endSeconds)
            lines.append("**\(seg.speakerLabel)** [\(t0)–\(t1)]")
            lines.append(seg.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public func pdfData(for recording: Recording) throws -> Data {
        let text = markdown(for: recording)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11)]
        let attr = NSAttributedString(string: text, attributes: attributes)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 612 - 72 * 2, height: 10_000))
        tv.textStorage?.setAttributedString(attr)
        tv.isEditable = false
        tv.sizeToFit()
        let h = max(tv.bounds.height, 200)
        tv.frame = NSRect(x: 0, y: 0, width: 612 - 72 * 2, height: h)
        return tv.dataWithPDF(inside: tv.bounds)
    }

    public func zipTranscriptAndAudio(recording: Recording, audioURL: URL?) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let mdURL = work.appendingPathComponent("transcript.md")
        try markdown(for: recording).write(to: mdURL, atomically: true, encoding: .utf8)
        if let audioURL, fm.fileExists(atPath: audioURL.path) {
            let dest = work.appendingPathComponent(audioURL.lastPathComponent)
            try fm.copyItem(at: audioURL, to: dest)
        }
        let zipURL = fm.temporaryDirectory.appendingPathComponent(
            "\(sanitizeFilename(recording.title))-export.zip")
        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }
        let archive = try Archive(url: zipURL, accessMode: .create)
        let items = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
        for url in items {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            try archive.addEntry(with: url.lastPathComponent, relativeTo: work, compressionMethod: .deflate)
        }
        return zipURL
    }

    public func shareToNotes(markdown: String, from window: NSWindow?) {
        let names: [NSSharingService.Name] = [
            .init("com.apple.Notes.SharingExtension"),
            .init("com.apple.share.add-to-notes"),
        ]
        for n in names {
            if let service = NSSharingService(named: n) {
                service.perform(withItems: [markdown])
                return
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}

private func formatTime(_ seconds: Double) -> String {
    let s = Int(seconds) % 60
    let m = (Int(seconds) / 60) % 60
    let h = Int(seconds) / 3600
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
}

private func sanitizeFilename(_ s: String) -> String {
    s.replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .prefix(80).description
}
