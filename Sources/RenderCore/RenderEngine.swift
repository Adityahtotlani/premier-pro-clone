import Foundation
import ProjectCore

#if canImport(AVFoundation)
import AVFoundation
#endif
public enum RenderJobStatus: String, Codable, Sendable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

public struct RenderJob: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var projectID: UUID
    public var sequenceID: UUID
    public var presetID: String
    public var status: RenderJobStatus
    public var progress: Double

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        sequenceID: UUID,
        presetID: String,
        status: RenderJobStatus = .queued,
        progress: Double = 0
    ) {
        self.id = id
        self.projectID = projectID
        self.sequenceID = sequenceID
        self.presetID = presetID
        self.status = status
        self.progress = progress
    }
}

public enum RenderEngineError: Error, LocalizedError, Equatable {
    case queueBusy
    case unknownPreset
    case missingJob
    case unsupportedSequence(String)
    case missingMedia(String)
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .queueBusy:
            return "Prototype queue supports one render at a time"
        case .unknownPreset:
            return "Unknown preset id"
        case .missingJob:
            return "Render job not found"
        case .unsupportedSequence(let reason):
            return "Unsupported export: \(reason)"
        case .missingMedia(let reason):
            return "Missing media: \(reason)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }
}

public struct ExportPresetRegistry {
    public let presets: [ExportPreset]

    public init(presets: [ExportPreset] = ExportPresetRegistry.defaultPresets) {
        self.presets = presets
    }

    public func preset(id: String) -> ExportPreset? {
        presets.first(where: { $0.id == id })
    }

    public static let defaultPresets: [ExportPreset] = [
        ExportPreset(
            id: "youtube-1080p-h264",
            name: "YouTube 1080p",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            resolution: "1920x1080",
            bitrateMbps: 12,
            fps: 30
        ),
        ExportPreset(
            id: "tiktok-1080x1920-h265",
            name: "TikTok Vertical",
            container: "mp4",
            videoCodec: "h265",
            audioCodec: "aac",
            resolution: "1080x1920",
            bitrateMbps: 10,
            fps: 30
        ),
        ExportPreset(
            id: "reels-1080x1920-h264",
            name: "Instagram Reels",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            resolution: "1080x1920",
            bitrateMbps: 10,
            fps: 30
        ),
        ExportPreset(
            id: "master-4k-h265",
            name: "Master 4K",
            container: "mov",
            videoCodec: "h265",
            audioCodec: "pcm",
            resolution: "3840x2160",
            bitrateMbps: 45,
            fps: 30
        )
    ]
}

public protocol RenderEngineProtocol: Sendable {
    func enqueue(projectID: UUID, sequenceID: UUID, presetID: String) throws -> UUID
    func currentJob() -> RenderJob?
    func completeCurrentJob() throws -> RenderJob
    func failCurrentJob() throws -> RenderJob
}

public final class RenderEngine: RenderEngineProtocol, @unchecked Sendable {
    private var activeJob: RenderJob?
    private let presetRegistry: ExportPresetRegistry
    #if canImport(AVFoundation)
    private var exportSession: AVAssetExportSession?
    #endif

    public init(presetRegistry: ExportPresetRegistry = ExportPresetRegistry()) {
        self.presetRegistry = presetRegistry
    }

    public func enqueue(projectID: UUID, sequenceID: UUID, presetID: String) throws -> UUID {
        guard activeJob == nil else {
            throw RenderEngineError.queueBusy
        }
        guard presetRegistry.preset(id: presetID) != nil else {
            throw RenderEngineError.unknownPreset
        }

        var job = RenderJob(projectID: projectID, sequenceID: sequenceID, presetID: presetID)
        job.status = .running
        activeJob = job
        return job.id
    }

    public func currentJob() -> RenderJob? {
        activeJob
    }

    public func completeCurrentJob() throws -> RenderJob {
        guard var activeJob else { throw RenderEngineError.missingJob }
        activeJob.status = .completed
        activeJob.progress = 1
        self.activeJob = nil
        return activeJob
    }

    public func failCurrentJob() throws -> RenderJob {
        guard var activeJob else { throw RenderEngineError.missingJob }
        activeJob.status = .failed
        self.activeJob = nil
        #if canImport(AVFoundation)
        exportSession?.cancelExport()
        exportSession = nil
        #endif
        return activeJob
    }

    public func preflight(project: Project, sequence: EditorSequence) -> RenderEngineError? {
        if activeJob != nil {
            return .queueBusy
        }
        #if canImport(AVFoundation)
        do {
            try validate(sequence: sequence, project: project)
            return nil
        } catch let error as RenderEngineError {
            return error
        } catch {
            return .exportFailed(error.localizedDescription)
        }
        #else
        return .unsupportedSequence("AVFoundation export is unavailable on this platform")
        #endif
    }

    #if canImport(AVFoundation)
    public func cancelCurrentExport() {
        exportSession?.cancelExport()
        exportSession = nil
    }

    @MainActor
    public func export(
        project: Project,
        sequence: EditorSequence,
        preset: ExportPreset,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        try validate(sequence: sequence, project: project)

        let composition = try buildComposition(sequence: sequence, project: project)
        let presetName = exportPresetName(for: preset)
        guard let session = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw RenderEngineError.exportFailed("Unable to create export session")
        }

        if FileManager.default.fileExists(atPath: outputURL.path()) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        session.outputURL = outputURL
        session.outputFileType = exportFileType(for: preset)
        session.shouldOptimizeForNetworkUse = true
        exportSession = session

        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                progressHandler(Double(session.progress))
                if session.status != .exporting {
                    break
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }

        defer {
            progressTask.cancel()
            exportSession = nil
        }

        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    progressHandler(1.0)
                    continuation.resume()
                case .failed:
                    let reason = session.error?.localizedDescription ?? "Unknown export error"
                    continuation.resume(throwing: RenderEngineError.exportFailed(reason))
                case .cancelled:
                    continuation.resume(throwing: RenderEngineError.exportFailed("Export cancelled"))
                default:
                    let reason = session.error?.localizedDescription ?? "Export did not complete"
                    continuation.resume(throwing: RenderEngineError.exportFailed(reason))
                }
            }
        }
    }

    private func validate(sequence: EditorSequence, project: Project) throws {
        guard sequence.videoTracks.count <= 1 else {
            throw RenderEngineError.unsupportedSequence("Multiple video tracks are not supported")
        }
        guard sequence.audioTracks.count <= 1 else {
            throw RenderEngineError.unsupportedSequence("Multiple audio tracks are not supported")
        }

        if let videoTrack = sequence.videoTracks.first {
            try validateTrack(videoTrack, in: project, kind: .video)
        }
        if let audioTrack = sequence.audioTracks.first {
            try validateTrack(audioTrack, in: project, kind: .audio)
        }
    }

    private func validateTrack(_ track: TimelineTrack, in project: Project, kind: TrackKind) throws {
        let sorted = track.clips.sorted { $0.timelineIn < $1.timelineIn }
        for (index, clip) in sorted.enumerated() {
            if !clip.effects.isEmpty {
                throw RenderEngineError.unsupportedSequence("Effects are not supported for export")
            }
            if clip.transforms.opacity != 1 ||
                clip.transforms.scaleX != 1 ||
                clip.transforms.scaleY != 1 ||
                clip.transforms.positionX != 0 ||
                clip.transforms.positionY != 0 {
                throw RenderEngineError.unsupportedSequence("Clip transforms are not supported for export")
            }
            if clip.gain != 1 {
                throw RenderEngineError.unsupportedSequence("Clip gain is not supported for export")
            }

            if index > 0 {
                let previous = sorted[index - 1]
                if clip.timelineIn < previous.timelineIn + previous.duration {
                    throw RenderEngineError.unsupportedSequence("Overlapping clips are not supported")
                }
            }

            guard project.assets.contains(where: { $0.id == clip.assetID }) else {
                throw RenderEngineError.missingMedia("Asset not found for clip")
            }
            if kind == .video {
                guard let asset = project.assets.first(where: { $0.id == clip.assetID }),
                      asset.type == .video else {
                    throw RenderEngineError.unsupportedSequence("Video track contains non-video assets")
                }
            }
            if kind == .audio {
                guard let asset = project.assets.first(where: { $0.id == clip.assetID }),
                      asset.type == .audio || asset.type == .video else {
                    throw RenderEngineError.unsupportedSequence("Audio track contains unsupported assets")
                }
            }
        }
    }

    private func buildComposition(sequence: EditorSequence, project: Project) throws -> AVMutableComposition {
        let composition = AVMutableComposition()

        if let videoTrack = sequence.videoTracks.first {
            let compVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            for clip in videoTrack.clips.sorted(by: { $0.timelineIn < $1.timelineIn }) {
                guard let asset = project.assets.first(where: { $0.id == clip.assetID }) else {
                    throw RenderEngineError.missingMedia("Asset missing for clip")
                }
                let url = URL(fileURLWithPath: asset.path)
                guard FileManager.default.fileExists(atPath: url.path()) else {
                    throw RenderEngineError.missingMedia("Missing file \(url.lastPathComponent)")
                }
                let source = AVURLAsset(url: url)
                guard let sourceTrack = source.tracks(withMediaType: .video).first else {
                    throw RenderEngineError.unsupportedSequence("No video track found in \(asset.name)")
                }
                let start = CMTime(seconds: max(0, clip.inTime), preferredTimescale: 600)
                let duration = CMTime(seconds: max(0, clip.duration), preferredTimescale: 600)
                let timeRange = CMTimeRange(start: start, duration: duration)
                let insertTime = CMTime(seconds: max(0, clip.timelineIn), preferredTimescale: 600)
                try compVideo?.insertTimeRange(timeRange, of: sourceTrack, at: insertTime)
            }
        }

        if let audioTrack = sequence.audioTracks.first {
            let compAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            for clip in audioTrack.clips.sorted(by: { $0.timelineIn < $1.timelineIn }) {
                guard let asset = project.assets.first(where: { $0.id == clip.assetID }) else {
                    throw RenderEngineError.missingMedia("Asset missing for clip")
                }
                let url = URL(fileURLWithPath: asset.path)
                guard FileManager.default.fileExists(atPath: url.path()) else {
                    throw RenderEngineError.missingMedia("Missing file \(url.lastPathComponent)")
                }
                let source = AVURLAsset(url: url)
                guard let sourceTrack = source.tracks(withMediaType: .audio).first else {
                    continue
                }
                let start = CMTime(seconds: max(0, clip.inTime), preferredTimescale: 600)
                let duration = CMTime(seconds: max(0, clip.duration), preferredTimescale: 600)
                let timeRange = CMTimeRange(start: start, duration: duration)
                let insertTime = CMTime(seconds: max(0, clip.timelineIn), preferredTimescale: 600)
                try compAudio?.insertTimeRange(timeRange, of: sourceTrack, at: insertTime)
            }
        }

        return composition
    }

    private func exportPresetName(for preset: ExportPreset) -> String {
        return AVAssetExportPresetHighestQuality
    }

    private func exportFileType(for preset: ExportPreset) -> AVFileType {
        switch preset.container.lowercased() {
        case "mov":
            return .mov
        case "mp4":
            return .mp4
        default:
            return .mp4
        }
    }
    #else
    public func cancelCurrentExport() {}
    public func export(
        project: Project,
        sequence: EditorSequence,
        preset: ExportPreset,
        outputURL: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        throw RenderEngineError.unsupportedSequence("AVFoundation is unavailable on this platform")
    }
    #endif
}
