#if canImport(XCTest)
import XCTest
@testable import ProjectCore

final class ProjectCoreTests: XCTestCase {
    func testMigratesSchemaV1ToCurrentVersion() throws {
        let v1JSON = """
        {
          "schemaVersion": 1,
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Legacy",
          "frameRate": 24,
          "sequences": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "Main",
              "timelineMode": "track",
              "duration": 0,
              "videoTracks": [],
              "audioTracks": [],
              "markers": []
            }
          ],
          "bins": []
        }
        """.data(using: .utf8)!

        let service = ProjectMigrationService()
        let migratedData = try service.migrateIfNeeded(data: v1JSON)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(Project.self, from: migratedData)

        XCTAssertEqual(project.schemaVersion, Project.currentSchemaVersion)
        XCTAssertEqual(project.fps, 24)
        XCTAssertEqual(project.sequences.first?.mode, .track)
        XCTAssertFalse(project.metadata.migrationLog.isEmpty)
    }

    func testSaveLoadAndAutosave() throws {
        let project = ProjectFactory.starterProject(name: "Unit Test", fps: 30)
        let store = ProjectStore()

        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PremierCloneTests-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: bundleURL)
        }

        try store.createProjectBundle(at: bundleURL, with: project)
        let loaded = try store.load(from: bundleURL)

        XCTAssertEqual(loaded.name, project.name)
        XCTAssertEqual(loaded.schemaVersion, Project.currentSchemaVersion)

        let autosaveURL = try store.autosave(project: loaded, to: bundleURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: autosaveURL.path()))

        let recovered = try store.recoverLatestAutosave(from: bundleURL)
        XCTAssertEqual(recovered?.name, project.name)
    }
}
#endif
