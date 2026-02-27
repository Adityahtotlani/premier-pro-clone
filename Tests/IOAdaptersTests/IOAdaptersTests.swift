#if canImport(XCTest)
import XCTest
@testable import IOAdapters
import ProjectCore

final class IOAdaptersTests: XCTestCase {
    func testMediaImporterInfersKnownTypes() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaImporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let movieURL = tempDirectory.appendingPathComponent("clip.mp4")
        let audioURL = tempDirectory.appendingPathComponent("voice.wav")
        let imageURL = tempDirectory.appendingPathComponent("thumb.png")

        try Data().write(to: movieURL)
        try Data().write(to: audioURL)
        try Data().write(to: imageURL)

        let importer = MediaImporter()
        let result = importer.import(urls: [movieURL, audioURL, imageURL])

        XCTAssertEqual(result.importedAssets.count, 3)
        let types = Set(result.importedAssets.map(\.type))
        XCTAssertTrue(types.contains(.video))
        XCTAssertTrue(types.contains(.audio))
        XCTAssertTrue(types.contains(.image))
    }

    func testProxyManagerWritesManifest() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProxyManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let assets = [
            MediaAsset(name: "A", path: "/tmp/A.mp4", type: .video, duration: 3),
            MediaAsset(name: "B", path: "/tmp/B.mp4", type: .video, duration: 5)
        ]

        let manager = ProxyManager()
        let manifest = try manager.createProxyManifest(for: assets, in: tempDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path()))

        let data = try Data(contentsOf: manifest)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([ProxyRecord].self, from: data)

        XCTAssertEqual(records.count, 2)
    }
}
#endif
