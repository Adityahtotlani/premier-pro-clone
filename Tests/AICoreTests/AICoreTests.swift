#if canImport(XCTest)
import XCTest
@testable import AICore
import ProjectCore

final class AICoreTests: XCTestCase {
    func testHighlightSuggestionsReturnScorePayload() throws {
        let service = AIAssistService()
        let project = makeProject()
        let sequenceID = try XCTUnwrap(project.sequences.first?.id)

        let artifact = try service.run(
            taskType: .highlightSuggestions,
            sequenceID: sequenceID,
            options: [:],
            in: project
        )

        XCTAssertEqual(artifact.taskType, .highlightSuggestions)
        XCTAssertNotNil(artifact.payload["score"])
    }

    private func makeProject() -> Project {
        let captions = CaptionTrack(language: "en", segments: [
            CaptionSegment(start: 0, end: 2, text: "hello", confidence: 0.92)
        ])

        let clip = ClipRef(assetID: UUID(), inTime: 0, outTime: 5, timelineIn: 0)
        let videoTrack = TimelineTrack(name: "V1", kind: .video, clips: [clip])
        let audioTrack = TimelineTrack(name: "A1", kind: .audio)
        let sequence = EditorSequence(
            name: "Main",
            mode: .track,
            duration: 5,
            videoTracks: [videoTrack],
            audioTracks: [audioTrack],
            markers: [TimelineMarker(time: 1, label: "beat")],
            captionTracks: [captions]
        )

        return Project(name: "AI Test", fps: 30, sequences: [sequence], bins: [])
    }
}
#endif
