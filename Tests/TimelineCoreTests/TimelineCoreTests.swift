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
}
#endif
