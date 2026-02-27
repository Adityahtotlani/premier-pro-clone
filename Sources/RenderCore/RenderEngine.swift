import Foundation
import ProjectCore

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

    public var errorDescription: String? {
        switch self {
        case .queueBusy:
            return "Prototype queue supports one render at a time"
        case .unknownPreset:
            return "Unknown preset id"
        case .missingJob:
            return "Render job not found"
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
        return activeJob
    }
}
