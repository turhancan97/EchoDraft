import AVFoundation
import Foundation

@MainActor
public protocol AudioPlaybackServicing: AnyObject {
    var currentTimeSeconds: Double { get async }
    var durationSeconds: Double { get async }
    func load(url: URL) async throws
    func play() async
    func pause() async
    func seek(to seconds: Double) async
}

@MainActor
public final class AudioPlaybackService: AudioPlaybackServicing {
    private let player = AVPlayer()

    public init() {}

    public var currentTimeSeconds: Double {
        get async {
            let cm = player.currentTime()
            return cm.seconds.isFinite ? cm.seconds : 0
        }
    }

    public var durationSeconds: Double {
        get async {
            player.currentItem?.duration.seconds ?? 0
        }
    }

    public func load(url: URL) async throws {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
    }

    public func play() async {
        player.play()
    }

    public func pause() async {
        player.pause()
    }

    public func seek(to seconds: Double) async {
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        await player.seek(to: t)
    }
}
