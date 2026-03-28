#if canImport(XCTest)
import XCTest
@testable import RenderCore
@testable import ProjectCore
#if canImport(AVFoundation)
import AVFoundation
#endif

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

    func testPreflightRejectsWhenQueueIsBusy() throws {
        let engine = RenderEngine()
        let project = ProjectFactory.starterProject(name: "BusyQueue")
        let sequence = project.sequences[0]

        _ = try engine.enqueue(
            projectID: project.id,
            sequenceID: sequence.id,
            presetID: "youtube-1080p-h264"
        )

        XCTAssertEqual(engine.preflight(project: project, sequence: sequence), .queueBusy)
    }

    #if canImport(AVFoundation)
    func testExportSimpleSequenceProducesFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RenderCoreExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let sourceURL = tempDirectory.appendingPathComponent("source.mov")
        try writeTestVideo(to: sourceURL, duration: 1.0)

        let asset = MediaAsset(name: "Source", path: sourceURL.path(), type: .video, duration: 1.0)
        let clip = ClipRef(assetID: asset.id, inTime: 0, outTime: 1.0, timelineIn: 0)
        let videoTrack = TimelineTrack(name: "V1", kind: .video, clips: [clip])
        let sequence = EditorSequence(
            name: "Sequence 1",
            mode: .track,
            duration: 1.0,
            videoTracks: [videoTrack]
        )
        let project = Project(name: "Project", fps: 30, sequences: [sequence], assets: [asset])

        let engine = RenderEngine()
        _ = try engine.enqueue(projectID: project.id, sequenceID: sequence.id, presetID: "youtube-1080p-h264")

        let outputURL = tempDirectory.appendingPathComponent("export.mp4")
        let preset = ExportPresetRegistry().preset(id: "youtube-1080p-h264")!
        try await engine.export(project: project, sequence: sequence, preset: preset, outputURL: outputURL) { _ in }
        _ = try engine.completeCurrentJob()

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path()))
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path())
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(fileSize, 0)
    }

    func testExportMultiTrackSequenceProducesFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RenderCoreMultiTrack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appendingPathComponent("source.mov")
        try writeTestVideo(to: sourceURL, duration: 1.0)

        let asset = MediaAsset(name: "Source", path: sourceURL.path(), type: .video, duration: 1.0)
        let clip = ClipRef(assetID: asset.id, inTime: 0, outTime: 1.0, timelineIn: 0)
        // Two video tracks — previously blocked, now supported
        let trackA = TimelineTrack(name: "V1", kind: .video, clips: [clip])
        let trackB = TimelineTrack(name: "V2", kind: .video, clips: [clip])
        let sequence = EditorSequence(
            name: "Sequence 1",
            mode: .track,
            duration: 1.0,
            videoTracks: [trackA, trackB]
        )
        let project = Project(name: "Project", fps: 30, sequences: [sequence], assets: [asset])

        let engine = RenderEngine()
        _ = try engine.enqueue(projectID: project.id, sequenceID: sequence.id, presetID: "youtube-1080p-h264")
        let preset = ExportPresetRegistry().preset(id: "youtube-1080p-h264")!
        let outputURL = tempDirectory.appendingPathComponent("export.mp4")
        try await engine.export(project: project, sequence: sequence, preset: preset, outputURL: outputURL) { _ in }
        _ = try engine.completeCurrentJob()

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path()))
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path())
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(fileSize, 0)
    }

    func testExportWithNonDefaultTransformProducesFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RenderCoreTransform-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appendingPathComponent("source.mov")
        try writeTestVideo(to: sourceURL, duration: 1.0)

        let asset = MediaAsset(name: "Source", path: sourceURL.path(), type: .video, duration: 1.0)
        let transform = ClipTransform(positionX: 10, positionY: 0, scaleX: 0.9, scaleY: 0.9, opacity: 0.8)
        let clip = ClipRef(assetID: asset.id, inTime: 0, outTime: 1.0, timelineIn: 0, transforms: transform)
        let videoTrack = TimelineTrack(name: "V1", kind: .video, clips: [clip])
        let sequence = EditorSequence(name: "Sequence 1", mode: .track, duration: 1.0, videoTracks: [videoTrack])
        let project = Project(name: "Project", fps: 30, sequences: [sequence], assets: [asset])

        let engine = RenderEngine()
        _ = try engine.enqueue(projectID: project.id, sequenceID: sequence.id, presetID: "youtube-1080p-h264")
        let preset = ExportPresetRegistry().preset(id: "youtube-1080p-h264")!
        let outputURL = tempDirectory.appendingPathComponent("export.mp4")
        try await engine.export(project: project, sequence: sequence, preset: preset, outputURL: outputURL) { _ in }
        _ = try engine.completeCurrentJob()

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path()))
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path())
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(fileSize, 0)
    }

    func testTransformIsIdentityHelper() {
        XCTAssertTrue(ClipTransform().isIdentity)
        XCTAssertFalse(ClipTransform(positionX: 1).isIdentity)
        XCTAssertFalse(ClipTransform(scaleX: 0.5).isIdentity)
        XCTAssertFalse(ClipTransform(opacity: 0.5).isIdentity)
    }

    func testExportFailsForEffects() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RenderCoreEffects-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appendingPathComponent("source.mov")
        try writeTestVideo(to: sourceURL, duration: 1.0)

        let asset = MediaAsset(name: "Source", path: sourceURL.path(), type: .video, duration: 1.0)
        let effect = EffectRef(name: "Blur", parameters: ["radius": 5])
        let clip = ClipRef(assetID: asset.id, inTime: 0, outTime: 1.0, timelineIn: 0, effects: [effect])
        let videoTrack = TimelineTrack(name: "V1", kind: .video, clips: [clip])
        let sequence = EditorSequence(name: "Sequence 1", mode: .track, duration: 1.0, videoTracks: [videoTrack])
        let project = Project(name: "Project", fps: 30, sequences: [sequence], assets: [asset])

        let engine = RenderEngine()
        _ = try engine.enqueue(projectID: project.id, sequenceID: sequence.id, presetID: "youtube-1080p-h264")
        let preset = ExportPresetRegistry().preset(id: "youtube-1080p-h264")!
        let outputURL = tempDirectory.appendingPathComponent("export.mp4")

        do {
            try await engine.export(project: project, sequence: sequence, preset: preset, outputURL: outputURL) { _ in }
            XCTFail("Expected unsupported sequence error for effects")
        } catch let error as RenderEngineError {
            if case .unsupportedSequence = error {
                // Expected — effects not yet supported
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    private func writeTestVideo(to url: URL, duration: TimeInterval) throws {
        let width = 320
        let height = 180
        let fps: Int32 = 30
        let frameCount = max(1, Int(duration * Double(fps)))

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "RenderCoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to add input"])
        }
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
            let buffer = try makePixelBuffer(width: width, height: height, red: 36, green: 140, blue: 210)
            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()
        let group = DispatchGroup()
        group.enter()
        writer.finishWriting {
            group.leave()
        }
        group.wait()

        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "RenderCoreTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Writer failed"])
        }
    }

    private func makePixelBuffer(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: "RenderCoreTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to create pixel buffer"])
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                let row = ptr.advanced(by: y * bytesPerRow)
                for x in 0..<width {
                    let offset = x * 4
                    row[offset] = blue
                    row[offset + 1] = green
                    row[offset + 2] = red
                    row[offset + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
    #endif
}
#endif
