#if canImport(XCTest)
import XCTest
@testable import AppShell
import ProjectCore

@MainActor
final class AppShellTests: XCTestCase {
    func testCreateSequenceAndSwitch() {
        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "Test"))
        let initialCount = workspace.project.sequences.count

        workspace.createSequence(named: "Alt")

        XCTAssertEqual(workspace.project.sequences.count, initialCount + 1)
        XCTAssertEqual(workspace.activeSequence?.name, "Alt")
    }

    func testAddMarkerAtPlayhead() {
        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "Test"))
        workspace.updatePlayhead(to: 12.0)
        workspace.addMarkerAtPlayhead(label: "Beat")

        XCTAssertEqual(workspace.activeSequence?.markers.count, 1)
        XCTAssertEqual(workspace.activeSequence?.markers.first?.label, "Beat")
    }

    func testSelectedClipMutationUpdatesTransform() {
        var project = ProjectFactory.starterProject(name: "Test")
        let asset = MediaAsset(name: "Clip", path: "/tmp/clip.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()

        guard let selectedClip = workspace.selectedClip else {
            XCTFail("Expected selected clip")
            return
        }

        workspace.updateSelectedClipPositionX(42)

        let updated = workspace.activeSequence?.videoTracks
            .flatMap(\.clips)
            .first(where: { $0.id == selectedClip.id })

        XCTAssertEqual(updated?.transforms.positionX, 42)
    }
}
#endif
