#if canImport(XCTest)
import XCTest
@testable import RenderCore

final class RenderCoreTests: XCTestCase {
    func testPresetRegistryHasCreatorPresets() {
        let registry = ExportPresetRegistry()
        XCTAssertNotNil(registry.preset(id: "youtube-1080p-h264"))
        XCTAssertNotNil(registry.preset(id: "tiktok-1080x1920-h265"))
        XCTAssertNotNil(registry.preset(id: "reels-1080x1920-h264"))
    }

    func testSingleJobQueueRejectsSecondActiveJob() throws {
        let engine = RenderEngine()

        _ = try engine.enqueue(
            projectID: UUID(),
            sequenceID: UUID(),
            presetID: "youtube-1080p-h264"
        )

        XCTAssertThrowsError(
            try engine.enqueue(
                projectID: UUID(),
                sequenceID: UUID(),
                presetID: "youtube-1080p-h264"
            )
        ) { error in
            XCTAssertEqual(error as? RenderEngineError, .queueBusy)
        }
    }
}
#endif
