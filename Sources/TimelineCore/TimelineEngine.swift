import Foundation
import ProjectCore

public enum TimelineOperation: Sendable {
    case insertClip(sequenceID: UUID, trackID: UUID, trackKind: TrackKind, clip: ClipRef)
    case splitClip(sequenceID: UUID, trackID: UUID, trackKind: TrackKind, clipID: UUID, splitTime: TimeInterval)
    case trimClip(sequenceID: UUID, trackID: UUID, trackKind: TrackKind, clipID: UUID, newIn: TimeInterval, newOut: TimeInterval)
    case rippleDelete(sequenceID: UUID, trackID: UUID, trackKind: TrackKind, clipID: UUID)
    case moveClip(sequenceID: UUID, trackID: UUID, trackKind: TrackKind, clipID: UUID, newTimelineIn: TimeInterval)
    case slipClip(sequenceID: UUID, trackID: UUID, trackKind: TrackKind, clipID: UUID, deltaSource: TimeInterval)
    // Slide keeps the selected clip duration intact but shifts its position while trimming
    // the adjacent clips to preserve the two surrounding edit points (track-mode behavior).
    case slideClip(sequenceID: UUID, trackID: UUID, trackKind: TrackKind, clipID: UUID, deltaTimeline: TimeInterval)
    case changeMode(sequenceID: UUID, mode: TimelineMode)
}

public struct TimelinePatch: Equatable, Sendable {
    public var summary: String
    public var affectedClipIDs: [UUID]
    public var resultingDuration: TimeInterval

    public init(summary: String, affectedClipIDs: [UUID], resultingDuration: TimeInterval) {
        self.summary = summary
        self.affectedClipIDs = affectedClipIDs
        self.resultingDuration = resultingDuration
    }
}

public enum TimelineEngineError: Error, LocalizedError {
    case sequenceNotFound
    case trackNotFound
    case clipNotFound
    case invalidTimeRange

    public var errorDescription: String? {
        switch self {
        case .sequenceNotFound:
            return "Sequence was not found"
        case .trackNotFound:
            return "Track was not found"
        case .clipNotFound:
            return "Clip was not found"
        case .invalidTimeRange:
            return "Invalid in/out times"
        }
    }
}

public struct TimelineEngine {
    public init() {}

    public func apply(operation: TimelineOperation, to project: Project) throws -> (Project, TimelinePatch) {
        var project = project
        let minimumEditableDuration: TimeInterval = 0.2
        let timeEpsilon: TimeInterval = 0.0001

        switch operation {
        case .insertClip(let sequenceID, let trackID, let trackKind, let clip):
            let duration = try updateTrack(project: &project, sequenceID: sequenceID, trackID: trackID, trackKind: trackKind) { track in
                track.clips.append(clip)
                track.clips.sort { $0.timelineIn < $1.timelineIn }
            }
            return (project, TimelinePatch(summary: "Inserted clip", affectedClipIDs: [clip.id], resultingDuration: duration))

        case .splitClip(let sequenceID, let trackID, let trackKind, let clipID, let splitTime):
            let (newClipID, duration) = try splitClip(
                project: &project,
                sequenceID: sequenceID,
                trackID: trackID,
                trackKind: trackKind,
                clipID: clipID,
                splitTime: splitTime
            )
            return (project, TimelinePatch(summary: "Split clip", affectedClipIDs: [clipID, newClipID], resultingDuration: duration))

        case .trimClip(let sequenceID, let trackID, let trackKind, let clipID, let newIn, let newOut):
            guard newOut > newIn else {
                throw TimelineEngineError.invalidTimeRange
            }

            let duration = try updateTrack(project: &project, sequenceID: sequenceID, trackID: trackID, trackKind: trackKind) { track in
                guard let clipIndex = track.clips.firstIndex(where: { $0.id == clipID }) else {
                    throw TimelineEngineError.clipNotFound
                }
                track.clips[clipIndex].inTime = newIn
                track.clips[clipIndex].outTime = newOut
            }
            return (project, TimelinePatch(summary: "Trimmed clip", affectedClipIDs: [clipID], resultingDuration: duration))

        case .rippleDelete(let sequenceID, let trackID, let trackKind, let clipID):
            let duration = try updateTrack(project: &project, sequenceID: sequenceID, trackID: trackID, trackKind: trackKind) { track in
                guard let clipIndex = track.clips.firstIndex(where: { $0.id == clipID }) else {
                    throw TimelineEngineError.clipNotFound
                }

                let removed = track.clips.remove(at: clipIndex)
                let shiftAmount = removed.duration

                for index in track.clips.indices where track.clips[index].timelineIn > removed.timelineIn {
                    track.clips[index].timelineIn = max(0, track.clips[index].timelineIn - shiftAmount)
                }

                track.clips.sort { $0.timelineIn < $1.timelineIn }
            }
            return (project, TimelinePatch(summary: "Ripple deleted clip", affectedClipIDs: [clipID], resultingDuration: duration))

        case .moveClip(let sequenceID, let trackID, let trackKind, let clipID, let newTimelineIn):
            let duration = try updateTrack(project: &project, sequenceID: sequenceID, trackID: trackID, trackKind: trackKind) { track in
                guard let clipIndex = track.clips.firstIndex(where: { $0.id == clipID }) else {
                    throw TimelineEngineError.clipNotFound
                }
                track.clips[clipIndex].timelineIn = max(0, newTimelineIn)
                track.clips.sort { $0.timelineIn < $1.timelineIn }
            }
            return (project, TimelinePatch(summary: "Moved clip", affectedClipIDs: [clipID], resultingDuration: duration))

        case .slipClip(let sequenceID, let trackID, let trackKind, let clipID, let deltaSource):
            let projectAssets = project.assets
            let duration = try updateTrack(project: &project, sequenceID: sequenceID, trackID: trackID, trackKind: trackKind) { track in
                guard let clipIndex = track.clips.firstIndex(where: { $0.id == clipID }) else {
                    throw TimelineEngineError.clipNotFound
                }

                let clip = track.clips[clipIndex]
                let clipDuration = clip.duration
                guard clipDuration > 0 else { throw TimelineEngineError.invalidTimeRange }

                let assetDuration = projectAssets.first(where: { $0.id == clip.assetID })?.duration ?? (clip.outTime)
                let maxIn = max(0, assetDuration - clipDuration)
                let proposedIn = clip.inTime + deltaSource
                let clampedIn = min(maxIn, max(0, proposedIn))
                let clampedOut = clampedIn + clipDuration

                guard clampedOut <= assetDuration + 0.0001 else {
                    throw TimelineEngineError.invalidTimeRange
                }

                track.clips[clipIndex].inTime = clampedIn
                track.clips[clipIndex].outTime = clampedOut
            }
            return (project, TimelinePatch(summary: "Slipped clip", affectedClipIDs: [clipID], resultingDuration: duration))

        case .slideClip(let sequenceID, let trackID, let trackKind, let clipID, let deltaTimeline):
            let projectAssets = project.assets
            let duration = try updateTrack(project: &project, sequenceID: sequenceID, trackID: trackID, trackKind: trackKind) { track in
                track.clips.sort { $0.timelineIn < $1.timelineIn }
                guard let clipIndex = track.clips.firstIndex(where: { $0.id == clipID }) else {
                    throw TimelineEngineError.clipNotFound
                }
                guard clipIndex > 0 && clipIndex < (track.clips.count - 1) else {
                    throw TimelineEngineError.invalidTimeRange
                }

                let prevIndex = clipIndex - 1
                let nextIndex = clipIndex + 1

                let prev = track.clips[prevIndex]
                let clip = track.clips[clipIndex]
                let next = track.clips[nextIndex]

                let prevDuration = prev.duration
                let clipDuration = clip.duration
                let nextDuration = next.duration

                guard prevDuration >= minimumEditableDuration,
                      clipDuration > 0,
                      nextDuration >= minimumEditableDuration else {
                    throw TimelineEngineError.invalidTimeRange
                }

                let prevEnd = prev.timelineIn + prevDuration
                let clipStart = clip.timelineIn
                let clipEnd = clip.timelineIn + clipDuration
                let nextStart = next.timelineIn

                // Keep this deterministic: only support slide at contiguous edit points.
                guard abs(prevEnd - clipStart) <= timeEpsilon,
                      abs(clipEnd - nextStart) <= timeEpsilon else {
                    throw TimelineEngineError.invalidTimeRange
                }

                // Clamp delta so adjacent clips never shrink below the minimum duration, and source bounds are respected.
                var minDelta = -(prevDuration - minimumEditableDuration)
                var maxDelta = (nextDuration - minimumEditableDuration)

                // Extending the next clip to the left consumes source headroom (inTime cannot go below 0).
                minDelta = max(minDelta, -next.inTime)

                // Extending the previous clip to the right consumes source tailroom if asset duration is known.
                if let assetDuration = projectAssets.first(where: { $0.id == prev.assetID })?.duration {
                    maxDelta = min(maxDelta, assetDuration - prev.outTime)
                }

                let clampedDelta = min(maxDelta, max(minDelta, deltaTimeline))
                guard abs(clampedDelta) > timeEpsilon else {
                    return
                }

                // Apply:
                // - prev keeps its start, adjusts outTime
                // - clip keeps in/out, adjusts timelineIn
                // - next keeps its end (outTime), adjusts inTime and timelineIn
                track.clips[prevIndex].outTime = prev.outTime + clampedDelta
                track.clips[clipIndex].timelineIn = clip.timelineIn + clampedDelta
                track.clips[nextIndex].timelineIn = next.timelineIn + clampedDelta
                track.clips[nextIndex].inTime = next.inTime + clampedDelta

                guard track.clips[prevIndex].outTime - track.clips[prevIndex].inTime >= minimumEditableDuration - timeEpsilon,
                      track.clips[nextIndex].outTime - track.clips[nextIndex].inTime >= minimumEditableDuration - timeEpsilon else {
                    throw TimelineEngineError.invalidTimeRange
                }
            }

            return (project, TimelinePatch(summary: "Slid clip", affectedClipIDs: [clipID], resultingDuration: duration))

        case .changeMode(let sequenceID, let mode):
            let duration = try updateSequence(project: &project, sequenceID: sequenceID) { sequence in
                sequence.mode = mode
                sequence = TimelineModeConverter.convert(sequence: sequence, to: mode)
            }
            return (project, TimelinePatch(summary: "Switched timeline mode", affectedClipIDs: [], resultingDuration: duration))
        }
    }

    private func splitClip(
        project: inout Project,
        sequenceID: UUID,
        trackID: UUID,
        trackKind: TrackKind,
        clipID: UUID,
        splitTime: TimeInterval
    ) throws -> (UUID, TimeInterval) {
        var generatedID = UUID()
        let duration = try updateTrack(project: &project, sequenceID: sequenceID, trackID: trackID, trackKind: trackKind) { track in
            guard let clipIndex = track.clips.firstIndex(where: { $0.id == clipID }) else {
                throw TimelineEngineError.clipNotFound
            }

            let clip = track.clips[clipIndex]
            let clipStart = clip.timelineIn
            let clipEnd = clip.timelineIn + clip.duration
            guard splitTime > clipStart && splitTime < clipEnd else {
                throw TimelineEngineError.invalidTimeRange
            }

            let relativeSplit = splitTime - clip.timelineIn
            let sourceSplit = clip.inTime + relativeSplit

            track.clips[clipIndex].outTime = sourceSplit

            var trailing = clip
            trailing.id = UUID()
            trailing.inTime = sourceSplit
            trailing.timelineIn = splitTime

            generatedID = trailing.id
            track.clips.insert(trailing, at: clipIndex + 1)
        }

        return (generatedID, duration)
    }

    private func updateTrack(
        project: inout Project,
        sequenceID: UUID,
        trackID: UUID,
        trackKind: TrackKind,
        mutation: (inout TimelineTrack) throws -> Void
    ) throws -> TimeInterval {
        let sequenceIndex = try requireSequenceIndex(in: project, sequenceID: sequenceID)
        let tracks = trackKind == .video ? project.sequences[sequenceIndex].videoTracks : project.sequences[sequenceIndex].audioTracks

        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }) else {
            throw TimelineEngineError.trackNotFound
        }

        if trackKind == .video {
            try mutation(&project.sequences[sequenceIndex].videoTracks[trackIndex])
        } else {
            try mutation(&project.sequences[sequenceIndex].audioTracks[trackIndex])
        }

        project.sequences[sequenceIndex].duration = TimelineDurationCalculator.duration(of: project.sequences[sequenceIndex])
        return project.sequences[sequenceIndex].duration
    }

    private func updateSequence(
        project: inout Project,
        sequenceID: UUID,
        mutation: (inout EditorSequence) throws -> Void
    ) throws -> TimeInterval {
        let sequenceIndex = try requireSequenceIndex(in: project, sequenceID: sequenceID)
        try mutation(&project.sequences[sequenceIndex])
        project.sequences[sequenceIndex].duration = TimelineDurationCalculator.duration(of: project.sequences[sequenceIndex])
        return project.sequences[sequenceIndex].duration
    }

    private func requireSequenceIndex(in project: Project, sequenceID: UUID) throws -> Int {
        guard let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequenceID }) else {
            throw TimelineEngineError.sequenceNotFound
        }
        return sequenceIndex
    }
}

public enum TimelineDurationCalculator {
    public static func duration(of sequence: EditorSequence) -> TimeInterval {
        let videoEnd = sequence.videoTracks
            .flatMap(\.clips)
            .map { $0.timelineIn + $0.duration }
            .max() ?? 0

        let audioEnd = sequence.audioTracks
            .flatMap(\.clips)
            .map { $0.timelineIn + $0.duration }
            .max() ?? 0

        return max(videoEnd, audioEnd)
    }
}

public enum TimelineModeConverter {
    public static func convert(sequence: EditorSequence, to mode: TimelineMode) -> EditorSequence {
        switch mode {
        case .track:
            return convertToTrack(sequence)
        case .magnetic:
            return convertToMagnetic(sequence)
        }
    }

    private static func convertToMagnetic(_ sequence: EditorSequence) -> EditorSequence {
        var sequence = sequence

        let flattened = sequence.videoTracks
            .enumerated()
            .flatMap { trackOffset, track in
                track.clips.map { (trackOffset: trackOffset, clip: $0) }
            }
            .sorted {
                if $0.clip.timelineIn == $1.clip.timelineIn {
                    return $0.trackOffset < $1.trackOffset
                }
                return $0.clip.timelineIn < $1.clip.timelineIn
            }

        var nextTimelineIn: TimeInterval = 0
        let packed = flattened.map { tuple -> ClipRef in
            var clip = tuple.clip
            clip.timelineIn = nextTimelineIn
            nextTimelineIn += clip.duration
            return clip
        }

        let primaryTrackID = sequence.videoTracks.first?.id ?? UUID()
        sequence.videoTracks = [
            TimelineTrack(
                id: primaryTrackID,
                name: "Primary",
                kind: .video,
                clips: packed
            )
        ]
        sequence.mode = .magnetic
        sequence.duration = TimelineDurationCalculator.duration(of: sequence)
        return sequence
    }

    private static func convertToTrack(_ sequence: EditorSequence) -> EditorSequence {
        var sequence = sequence
        let clips = sequence.videoTracks.flatMap(\.clips).sorted { $0.timelineIn < $1.timelineIn }

        let primaryTrackID = sequence.videoTracks.first?.id ?? UUID()
        sequence.videoTracks = [
            TimelineTrack(
                id: primaryTrackID,
                name: "V1",
                kind: .video,
                clips: clips
            )
        ]
        sequence.mode = .track
        sequence.duration = TimelineDurationCalculator.duration(of: sequence)
        return sequence
    }
}
