import Foundation
import ProjectCore

#if canImport(AVFoundation)
import AVFoundation
#endif

public enum PlaybackQualityMode: String, Codable, CaseIterable, Sendable {
    case full
    case half
    case quarter
}

public struct PlaybackSession: Equatable, Sendable {
    public var sequenceID: UUID
    public var currentTime: TimeInterval
    public var qualityMode: PlaybackQualityMode
    public var isPlaying: Bool

    public init(
        sequenceID: UUID,
        currentTime: TimeInterval,
        qualityMode: PlaybackQualityMode,
        isPlaying: Bool
    ) {
        self.sequenceID = sequenceID
        self.currentTime = currentTime
        self.qualityMode = qualityMode
        self.isPlaying = isPlaying
    }
}

public enum PlaybackChannel: String, Sendable {
    case source
    case program
}

public protocol PlaybackEngineProtocol: Sendable {
    func play(sequenceID: UUID, startTime: TimeInterval, qualityMode: PlaybackQualityMode) -> PlaybackSession
    func pause() -> PlaybackSession?
    func seek(to time: TimeInterval) -> PlaybackSession?
    func currentSession() -> PlaybackSession?
}

public final class PlaybackEngine: PlaybackEngineProtocol, @unchecked Sendable {
    private var session: PlaybackSession?
    #if canImport(AVFoundation)
    private var players: [PlaybackChannel: AVPlayer] = [:]
    private var loadedURLs: [PlaybackChannel: URL] = [:]
    #endif

    public init() {}

    public func play(sequenceID: UUID, startTime: TimeInterval, qualityMode: PlaybackQualityMode) -> PlaybackSession {
        session = PlaybackSession(
            sequenceID: sequenceID,
            currentTime: max(0, startTime),
            qualityMode: qualityMode,
            isPlaying: true
        )
        #if canImport(AVFoundation)
        if let player = players[.program] {
            player.play()
        }
        #endif
        return session!
    }

    public func pause() -> PlaybackSession? {
        guard var session else { return nil }
        session.isPlaying = false
        self.session = session
        #if canImport(AVFoundation)
        players[.program]?.pause()
        #endif
        return session
    }

    public func seek(to time: TimeInterval) -> PlaybackSession? {
        guard var session else { return nil }
        session.currentTime = max(0, time)
        self.session = session
        #if canImport(AVFoundation)
        if let player = players[.program] {
            let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        #endif
        return session
    }

    public func currentSession() -> PlaybackSession? {
        session
    }

    #if canImport(AVFoundation)
    public func load(url: URL, channel: PlaybackChannel) -> AVPlayer {
        let standardized = url.standardizedFileURL
        if let loaded = loadedURLs[channel],
           loaded == standardized,
           let player = players[channel] {
            return player
        }

        let item = AVPlayerItem(url: standardized)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false

        players[channel]?.pause()
        players[channel] = player
        loadedURLs[channel] = standardized
        return player
    }

    public func player(for channel: PlaybackChannel) -> AVPlayer? {
        players[channel]
    }

    public func seek(channel: PlaybackChannel, to time: TimeInterval) {
        guard let player = players[channel] else { return }
        let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func setRate(_ rate: Double, channel: PlaybackChannel) {
        guard let player = players[channel] else { return }
        let clamped = Float(min(4.0, max(0.25, rate)))
        player.rate = clamped
    }

    public func setMuted(_ muted: Bool, channel: PlaybackChannel) {
        players[channel]?.isMuted = muted
    }

    public func setVolume(_ volume: Double, channel: PlaybackChannel) {
        let clamped = Float(min(1.0, max(0, volume)))
        players[channel]?.volume = clamped
    }

    public func stop(channel: PlaybackChannel) {
        players[channel]?.pause()
    }
    #endif
}
