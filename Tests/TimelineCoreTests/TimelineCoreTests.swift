#if canImport(XCTest)
import XCTest
@testable import TimelineCore
import ProjectCore

final class TimelineCoreTests: XCTestCase {
    func testSplitClipProducesTwoClips() throws {
        let engine = TimelineEngine()
        let project = makeProject()

        let sequence = try XCTUnwrap(project.sequences.first)
        let track = try XCTUnwrap(sequence.videoTracks.first)
        let clip = try XCTUnwrap(track.clips.first)

        let result = try engine.apply(
            operation: .splitClip(
                sequenceID: sequence.id,
                trackID: track.id,
                trackKind: .video,
                clipID: clip.id,
                splitTime: 5
            ),
            to: project
        )

        let updatedTrack = try XCTUnwrap(result.0.sequences.first?.videoTracks.first)
        XCTAssertEqual(updatedTrack.clips.count, 2)
        XCTAssertEqual(updatedTrack.clips[0].outTime, 5)
        XCTAssertEqual(updatedTrack.clips[1].inTime, 5)
    }

    func testRippleDeleteShiftsFollowingClips() throws {
        let engine = TimelineEngine()
        let project = makeProject(includeSecondClip: true)

        let sequence = try XCTUnwrap(project.sequences.first)
        let track = try XCTUnwrap(sequence.videoTracks.first)
        let firstClip = try XCTUnwrap(track.clips.first)

        let result = try engine.apply(
            operation: .rippleDelete(
                sequenceID: sequence.id,
                trackID: track.id,
                trackKind: .video,
                clipID: firstClip.id
            ),
            to: project
        )

        let updatedTrack = try XCTUnwrap(result.0.sequences.first?.videoTracks.first)
        XCTAssertEqual(updatedTrack.clips.count, 1)
        XCTAssertEqual(updatedTrack.clips[0].timelineIn, 0)
    }

    func testModeConversionToMagneticRemovesGapsDeterministically() throws {
        let engine = TimelineEngine()
        var project = makeProject(includeSecondClip: true)

        let secondTrackClip = ClipRef(assetID: UUID(), inTime: 0, outTime: 2, timelineIn: 1)
        project.sequences[0].videoTracks.append(
            TimelineTrack(name: "V2", kind: .video, clips: [secondTrackClip])
        )

        let sequence = try XCTUnwrap(project.sequences.first)
        let result = try engine.apply(
            operation: .changeMode(sequenceID: sequence.id, mode: .magnetic),
            to: project
        )

        let updatedSequence = try XCTUnwrap(result.0.sequences.first)
        XCTAssertEqual(updatedSequence.mode, .magnetic)
        XCTAssertEqual(updatedSequence.videoTracks.count, 1)
        let clipStarts = updatedSequence.videoTracks[0].clips.map(\.timelineIn)
        XCTAssertEqual(clipStarts, [0, 5, 8])
    }

    func testSlipClipStaysWithinAssetDuration() throws {
        let engine = TimelineEngine()
        var project = makeProject(includeSecondClip: false)

        // Ensure asset duration known
        let assetID = project.sequences[0].videoTracks[0].clips[0].assetID
        project.assets = [MediaAsset(name: "A", path: "/tmp/a.mp4", type: .video, duration: 8)]
        project.sequences[0].videoTracks[0].clips[0].assetID = assetID

        let sequence = try XCTUnwrap(project.sequences.first)
        let track = try XCTUnwrap(sequence.videoTracks.first)
        let clip = try XCTUnwrap(track.clips.first)

        let result = try engine.apply(
            operation: .slipClip(
                sequenceID: sequence.id,
                trackID: track.id,
                trackKind: .video,
                clipID: clip.id,
                deltaSource: 1.0
            ),
            to: project
        )

        let updatedClip = try XCTUnwrap(result.0.sequences.first?.videoTracks.first?.clips.first)
        XCTAssertEqual(updatedClip.inTime, 1.0, accuracy: 0.0001)
        XCTAssertEqual(updatedClip.outTime, 6.0, accuracy: 0.0001)
    }

    func testSlideClipMovesMiddleClipAndTrimsNeighbors() throws {
        let engine = TimelineEngine()
        let project = makeContiguousSlideProject(
            prev: (inTime: 0, outTime: 5),
            middle: (inTime: 0, outTime: 3),
            next: (inTime: 0, outTime: 4)
        )

        let sequence = try XCTUnwrap(project.sequences.first)
        let track = try XCTUnwrap(sequence.videoTracks.first)
        XCTAssertEqual(track.clips.count, 3)

        let prevID = track.clips[0].id
        let middleID = track.clips[1].id
        let nextID = track.clips[2].id

        let result = try engine.apply(
            operation: .slideClip(
                sequenceID: sequence.id,
                trackID: track.id,
                trackKind: .video,
                clipID: middleID,
                deltaTimeline: 1.0
            ),
            to: project
        )

        let updated = try XCTUnwrap(result.0.sequences.first?.videoTracks.first)
        let updatedPrev = try XCTUnwrap(updated.clips.first(where: { $0.id == prevID }))
        let updatedMid = try XCTUnwrap(updated.clips.first(where: { $0.id == middleID }))
        let updatedNext = try XCTUnwrap(updated.clips.first(where: { $0.id == nextID }))

        XCTAssertEqual(updatedPrev.outTime, 6.0, accuracy: 0.0001)
        XCTAssertEqual(updatedMid.timelineIn, 6.0, accuracy: 0.0001)
        XCTAssertEqual(updatedNext.timelineIn, 9.0, accuracy: 0.0001)
        XCTAssertEqual(updatedNext.inTime, 1.0, accuracy: 0.0001)

        // Contiguity preserved at edit points.
        XCTAssertEqual(updatedPrev.timelineIn + updatedPrev.duration, updatedMid.timelineIn, accuracy: 0.0001)
        XCTAssertEqual(updatedMid.timelineIn + updatedMid.duration, updatedNext.timelineIn, accuracy: 0.0001)
    }

    func testSlideClipClampsToMinimumNeighborDuration() throws {
        let engine = TimelineEngine()
        let project = makeContiguousSlideProject(
            prev: (inTime: 0, outTime: 5),
            middle: (inTime: 0, outTime: 3),
            next: (inTime: 1.0, outTime: 1.6) // duration 0.6, so max delta right is 0.4 (min duration 0.2)
        )

        let sequence = try XCTUnwrap(project.sequences.first)
        let track = try XCTUnwrap(sequence.videoTracks.first)
        let middleID = track.clips[1].id
        let nextID = track.clips[2].id

        let result = try engine.apply(
            operation: .slideClip(
                sequenceID: sequence.id,
                trackID: track.id,
                trackKind: .video,
                clipID: middleID,
                deltaTimeline: 10.0
            ),
            to: project
        )

        let updated = try XCTUnwrap(result.0.sequences.first?.videoTracks.first)
        let updatedNext = try XCTUnwrap(updated.clips.first(where: { $0.id == nextID }))
        XCTAssertEqual(updatedNext.inTime, 1.4, accuracy: 0.0001)
        XCTAssertEqual(updatedNext.duration, 0.2, accuracy: 0.0001)
    }

    func testSlideClipRequiresContiguousEditPoints() throws {
        let engine = TimelineEngine()
        let project = makeProject(includeSecondClip: true) // this includes a gap (clip2 starts at 7, clip1 ends at 5)

        let sequence = try XCTUnwrap(project.sequences.first)
        let track = try XCTUnwrap(sequence.videoTracks.first)
        let clipID = try XCTUnwrap(track.clips.first).id

        XCTAssertThrowsError(
            try engine.apply(
                operation: .slideClip(
                    sequenceID: sequence.id,
                    trackID: track.id,
                    trackKind: .video,
                    clipID: clipID,
                    deltaTimeline: 1.0
                ),
                to: project
            )
        ) { error in
            XCTAssertEqual(error as? TimelineEngineError, .invalidTimeRange)
        }
    }

    private func makeProject(includeSecondClip: Bool = false) -> Project {
        let clip1 = ClipRef(assetID: UUID(), inTime: 0, outTime: 5, timelineIn: 0)
        var clips = [clip1]
        if includeSecondClip {
            clips.append(ClipRef(assetID: UUID(), inTime: 0, outTime: 3, timelineIn: 7))
        }

        let videoTrack = TimelineTrack(name: "V1", kind: .video, clips: clips)
        let audioTrack = TimelineTrack(name: "A1", kind: .audio)
        let sequence = EditorSequence(name: "Main", mode: .track, videoTracks: [videoTrack], audioTracks: [audioTrack])

        return Project(
            name: "Test",
            fps: 30,
            sequences: [sequence],
            bins: []
        )
    }

    private func makeContiguousSlideProject(
        prev: (inTime: TimeInterval, outTime: TimeInterval),
        middle: (inTime: TimeInterval, outTime: TimeInterval),
        next: (inTime: TimeInterval, outTime: TimeInterval)
    ) -> Project {
        let clip1 = ClipRef(assetID: UUID(), inTime: prev.inTime, outTime: prev.outTime, timelineIn: 0)
        let clip2 = ClipRef(assetID: UUID(), inTime: middle.inTime, outTime: middle.outTime, timelineIn: clip1.duration)
        let clip3 = ClipRef(assetID: UUID(), inTime: next.inTime, outTime: next.outTime, timelineIn: clip2.timelineIn + clip2.duration)

        let videoTrack = TimelineTrack(name: "V1", kind: .video, clips: [clip1, clip2, clip3])
        let audioTrack = TimelineTrack(name: "A1", kind: .audio)
        let sequence = EditorSequence(name: "Main", mode: .track, videoTracks: [videoTrack], audioTracks: [audioTrack])

        return Project(
            name: "SlideTest",
            fps: 30,
            sequences: [sequence],
            bins: []
        )
    }
}
#endif
