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

    public func export(
        project: Project,
        sequence: EditorSequence,
        preset: ExportPreset,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        try validate(sequence: sequence, project: project)

        let (composition, videoTrackMap, audioTrackMap) = try buildComposition(
            sequence: sequence,
            project: project
        )

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

        // Wire multi-track video composition (handles transforms + track layering)
        if let videoComp = buildVideoComposition(
            sequence: sequence,
            composition: composition,
            videoTrackMap: videoTrackMap,
            preset: preset
        ) {
            session.videoComposition = videoComp
        }

        // Wire audio mix (handles per-clip gain)
        if let audioMix = buildAudioMix(
            sequence: sequence,
            composition: composition,
            audioTrackMap: audioTrackMap
        ) {
            session.audioMix = audioMix
        }

        exportSession = session

        let progressTask = Task {
            while !Task.isCancelled {
                await MainActor.run { progressHandler(Double(session.progress)) }
                if session.status != .exporting { break }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }

        defer {
            progressTask.cancel()
            exportSession = nil
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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

    // MARK: - Validation

    private func validate(sequence: EditorSequence, project: Project) throws {
        let allVideoClips = sequence.videoTracks.flatMap(\.clips)
        let allAudioClips = sequence.audioTracks.flatMap(\.clips)

        for track in sequence.videoTracks {
            try validateTrack(track, in: project, kind: .video)
        }
        for track in sequence.audioTracks {
            try validateTrack(track, in: project, kind: .audio)
        }

        // Check for overlaps within each track
        for track in sequence.videoTracks + sequence.audioTracks {
            let sorted = track.clips.sorted { $0.timelineIn < $1.timelineIn }
            for (index, clip) in sorted.enumerated() where index > 0 {
                let previous = sorted[index - 1]
                if clip.timelineIn < previous.timelineIn + previous.duration {
                    throw RenderEngineError.unsupportedSequence("Overlapping clips are not supported")
                }
            }
        }

        _ = allVideoClips
        _ = allAudioClips
    }

    private func validateTrack(_ track: TimelineTrack, in project: Project, kind: TrackKind) throws {
        for clip in track.clips {
            if !clip.effects.isEmpty {
                throw RenderEngineError.unsupportedSequence("Effects are not supported for export yet")
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

    // MARK: - Composition Building

    /// Builds the AVMutableComposition from all video and audio tracks.
    /// Returns the composition plus maps from TimelineTrack → composition track for later use
    /// in video composition and audio mix building.
    private func buildComposition(
        sequence: EditorSequence,
        project: Project
    ) throws -> (
        composition: AVMutableComposition,
        videoTrackMap: [(timelineTrack: TimelineTrack, compositionTrack: AVMutableCompositionTrack)],
        audioTrackMap: [(timelineTrack: TimelineTrack, compositionTrack: AVMutableCompositionTrack)]
    ) {
        let composition = AVMutableComposition()
        var videoTrackMap: [(timelineTrack: TimelineTrack, compositionTrack: AVMutableCompositionTrack)] = []
        var audioTrackMap: [(timelineTrack: TimelineTrack, compositionTrack: AVMutableCompositionTrack)] = []

        for timelineTrack in sequence.videoTracks {
            guard let compTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            for clip in timelineTrack.clips.sorted(by: { $0.timelineIn < $1.timelineIn }) {
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
                let timeRange = CMTimeRange(
                    start: CMTime(seconds: max(0, clip.inTime), preferredTimescale: 600),
                    duration: CMTime(seconds: max(0, clip.duration), preferredTimescale: 600)
                )
                let insertTime = CMTime(seconds: max(0, clip.timelineIn), preferredTimescale: 600)
                try compTrack.insertTimeRange(timeRange, of: sourceTrack, at: insertTime)
            }

            videoTrackMap.append((timelineTrack: timelineTrack, compositionTrack: compTrack))
        }

        for timelineTrack in sequence.audioTracks {
            guard let compTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            for clip in timelineTrack.clips.sorted(by: { $0.timelineIn < $1.timelineIn }) {
                guard let asset = project.assets.first(where: { $0.id == clip.assetID }) else {
                    throw RenderEngineError.missingMedia("Asset missing for clip")
                }
                let url = URL(fileURLWithPath: asset.path)
                guard FileManager.default.fileExists(atPath: url.path()) else {
                    throw RenderEngineError.missingMedia("Missing file \(url.lastPathComponent)")
                }
                let source = AVURLAsset(url: url)
                guard let sourceTrack = source.tracks(withMediaType: .audio).first else {
                    continue // audio track in video file may be absent — skip silently
                }
                let timeRange = CMTimeRange(
                    start: CMTime(seconds: max(0, clip.inTime), preferredTimescale: 600),
                    duration: CMTime(seconds: max(0, clip.duration), preferredTimescale: 600)
                )
                let insertTime = CMTime(seconds: max(0, clip.timelineIn), preferredTimescale: 600)
                try compTrack.insertTimeRange(timeRange, of: sourceTrack, at: insertTime)
            }

            audioTrackMap.append((timelineTrack: timelineTrack, compositionTrack: compTrack))
        }

        return (composition, videoTrackMap, audioTrackMap)
    }

    // MARK: - Video Composition (Transforms + Multi-track Layering)

    /// Returns an AVMutableVideoComposition if needed — i.e. when there are multiple video tracks
    /// or any clip carries non-identity transforms. Returns nil when a simple passthrough suffices.
    private func buildVideoComposition(
        sequence: EditorSequence,
        composition: AVMutableComposition,
        videoTrackMap: [(timelineTrack: TimelineTrack, compositionTrack: AVMutableCompositionTrack)],
        preset: ExportPreset
    ) -> AVMutableVideoComposition? {
        guard !videoTrackMap.isEmpty else { return nil }

        let needsComposition = videoTrackMap.count > 1
            || sequence.videoTracks.flatMap(\.clips).contains(where: { !$0.transforms.isIdentity })

        guard needsComposition else { return nil }

        let renderSize = self.renderSize(for: preset)
        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = renderSize
        videoComp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(preset.fps))

        // Collect all time boundaries across all clips in all video tracks
        var timeEvents: Set<Double> = [0]
        let sequenceDuration = sequence.videoTracks.flatMap(\.clips).reduce(0.0) {
            max($0, $1.timelineIn + $1.duration)
        }
        if sequenceDuration > 0 { timeEvents.insert(sequenceDuration) }

        for track in sequence.videoTracks {
            for clip in track.clips {
                timeEvents.insert(clip.timelineIn)
                timeEvents.insert(clip.timelineIn + clip.duration)
            }
        }

        let sortedEvents = timeEvents.sorted()
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for i in 0..<(sortedEvents.count - 1) {
            let segStart = sortedEvents[i]
            let segEnd = sortedEvents[i + 1]
            guard segEnd > segStart else { continue }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(
                start: CMTime(seconds: segStart, preferredTimescale: 600),
                duration: CMTime(seconds: segEnd - segStart, preferredTimescale: 600)
            )

            var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []

            // Video tracks rendered back-to-front (last track in array = bottom layer).
            // Reverse so index 0 (topmost timeline track) composites on top.
            for entry in videoTrackMap.reversed() {
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: entry.compositionTrack
                )
                let atTime = CMTime(seconds: segStart, preferredTimescale: 600)

                // Find clip active during [segStart, segEnd)
                let activeClip = entry.timelineTrack.clips.first {
                    $0.timelineIn <= segStart && $0.timelineIn + $0.duration >= segEnd
                }

                if let clip = activeClip {
                    let t = clip.transforms
                    // Build affine transform: scale around center, then translate
                    var transform = CGAffineTransform.identity
                    transform = transform.scaledBy(x: t.scaleX, y: t.scaleY)
                    transform = transform.translatedBy(x: t.positionX, y: t.positionY)
                    layerInstruction.setTransform(transform, at: atTime)
                    layerInstruction.setOpacity(Float(t.opacity), at: atTime)
                } else {
                    // No clip active in this track during this segment — hide it
                    layerInstruction.setOpacity(0, at: atTime)
                }

                layerInstructions.append(layerInstruction)
            }

            instruction.layerInstructions = layerInstructions
            instructions.append(instruction)
        }

        videoComp.instructions = instructions
        return videoComp
    }

    // MARK: - Audio Mix (Per-clip Gain)

    /// Returns an AVMutableAudioMix applying per-clip gain when any clip has non-unity gain.
    /// Returns nil when all clips use the default gain of 1.0.
    private func buildAudioMix(
        sequence: EditorSequence,
        composition: AVMutableComposition,
        audioTrackMap: [(timelineTrack: TimelineTrack, compositionTrack: AVMutableCompositionTrack)]
    ) -> AVMutableAudioMix? {
        let hasNonUnityGain = sequence.audioTracks.flatMap(\.clips).contains { $0.gain != 1.0 }
        guard hasNonUnityGain else { return nil }

        let audioMix = AVMutableAudioMix()
        var inputParameters: [AVMutableAudioMixInputParameters] = []

        for entry in audioTrackMap {
            let params = AVMutableAudioMixInputParameters(track: entry.compositionTrack)
            for clip in entry.timelineTrack.clips where clip.gain != 1.0 {
                let clipStart = CMTime(seconds: clip.timelineIn, preferredTimescale: 600)
                let clipEnd = CMTime(seconds: clip.timelineIn + clip.duration, preferredTimescale: 600)
                let timeRange = CMTimeRange(start: clipStart, end: clipEnd)
                let volume = Float(max(0, min(2.0, clip.gain)))
                params.setVolumeRamp(fromStartVolume: volume, toEndVolume: volume, for: timeRange)
            }
            inputParameters.append(params)
        }

        audioMix.inputParameters = inputParameters
        return audioMix
    }

    // MARK: - Helpers

    private func renderSize(for preset: ExportPreset) -> CGSize {
        let parts = preset.resolution.split(separator: "x").compactMap { Int($0) }
        if parts.count == 2 {
            return CGSize(width: parts[0], height: parts[1])
        }
        return CGSize(width: 1920, height: 1080)
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
