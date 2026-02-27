import Foundation
import ProjectCore

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

public protocol PlaybackEngineProtocol: Sendable {
    func play(sequenceID: UUID, startTime: TimeInterval, qualityMode: PlaybackQualityMode) -> PlaybackSession
    func pause() -> PlaybackSession?
    func seek(to time: TimeInterval) -> PlaybackSession?
    func currentSession() -> PlaybackSession?
}

public final class PlaybackEngine: PlaybackEngineProtocol, @unchecked Sendable {
    private var session: PlaybackSession?

    public init() {}

    public func play(sequenceID: UUID, startTime: TimeInterval, qualityMode: PlaybackQualityMode) -> PlaybackSession {
        session = PlaybackSession(
            sequenceID: sequenceID,
            currentTime: max(0, startTime),
            qualityMode: qualityMode,
            isPlaying: true
        )
        return session!
    }

    public func pause() -> PlaybackSession? {
        guard var session else { return nil }
        session.isPlaying = false
        self.session = session
        return session
    }

    public func seek(to time: TimeInterval) -> PlaybackSession? {
        guard var session else { return nil }
        session.currentTime = max(0, time)
        self.session = session
        return session
    }

    public func currentSession() -> PlaybackSession? {
        session
    }
}
