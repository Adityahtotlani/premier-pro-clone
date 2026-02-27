import Foundation

public enum TimelineMode: String, Codable, CaseIterable, Sendable {
    case track
    case magnetic
}

public enum TrackKind: String, Codable, Sendable {
    case video
    case audio
}

public struct MediaAsset: Codable, Equatable, Identifiable, Sendable {
    public enum AssetType: String, Codable, Sendable {
        case video
        case audio
        case image
        case unknown
    }

    public var id: UUID
    public var name: String
    public var path: String
    public var type: AssetType
    public var duration: TimeInterval
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        type: AssetType,
        duration: TimeInterval,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.type = type
        self.duration = duration
        self.createdAt = createdAt
    }
}

public struct MediaBin: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var assetIDs: [UUID]

    public init(id: UUID = UUID(), name: String, assetIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.assetIDs = assetIDs
    }
}

public struct ClipTransform: Codable, Equatable, Sendable {
    public var positionX: Double
    public var positionY: Double
    public var scaleX: Double
    public var scaleY: Double
    public var opacity: Double

    public init(
        positionX: Double = 0,
        positionY: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        opacity: Double = 1
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.opacity = opacity
    }
}

public struct EffectRef: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var parameters: [String: Double]

    public init(id: UUID = UUID(), name: String, parameters: [String: Double] = [:]) {
        self.id = id
        self.name = name
        self.parameters = parameters
    }
}

public struct ClipRef: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var assetID: UUID
    public var inTime: TimeInterval
    public var outTime: TimeInterval
    public var timelineIn: TimeInterval
    public var linkedAudioIDs: [UUID]
    public var transforms: ClipTransform
    public var effects: [EffectRef]
    public var gain: Double

    public var duration: TimeInterval {
        max(0, outTime - inTime)
    }

    public init(
        id: UUID = UUID(),
        assetID: UUID,
        inTime: TimeInterval,
        outTime: TimeInterval,
        timelineIn: TimeInterval,
        linkedAudioIDs: [UUID] = [],
        transforms: ClipTransform = ClipTransform(),
        effects: [EffectRef] = [],
        gain: Double = 1
    ) {
        self.id = id
        self.assetID = assetID
        self.inTime = inTime
        self.outTime = outTime
        self.timelineIn = timelineIn
        self.linkedAudioIDs = linkedAudioIDs
        self.transforms = transforms
        self.effects = effects
        self.gain = gain
    }
}

public struct TimelineTrack: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: TrackKind
    public var isMuted: Bool
    public var isSolo: Bool
    public var clips: [ClipRef]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: TrackKind,
        isMuted: Bool = false,
        isSolo: Bool = false,
        clips: [ClipRef] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.clips = clips
    }
}

public struct TimelineMarker: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var time: TimeInterval
    public var label: String

    public init(id: UUID = UUID(), time: TimeInterval, label: String) {
        self.id = id
        self.time = time
        self.label = label
    }
}

public struct CaptionSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var confidence: Double

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        confidence: Double
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.confidence = confidence
    }
}

public struct CaptionTrack: Codable, Equatable, Sendable {
    public var language: String
    public var segments: [CaptionSegment]

    public init(language: String, segments: [CaptionSegment] = []) {
        self.language = language
        self.segments = segments
    }
}

public struct EditorSequence: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var mode: TimelineMode
    public var duration: TimeInterval
    public var videoTracks: [TimelineTrack]
    public var audioTracks: [TimelineTrack]
    public var markers: [TimelineMarker]
    public var captionTracks: [CaptionTrack]

    public init(
        id: UUID = UUID(),
        name: String,
        mode: TimelineMode,
        duration: TimeInterval = 0,
        videoTracks: [TimelineTrack] = [],
        audioTracks: [TimelineTrack] = [],
        markers: [TimelineMarker] = [],
        captionTracks: [CaptionTrack] = []
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.duration = duration
        self.videoTracks = videoTracks
        self.audioTracks = audioTracks
        self.markers = markers
        self.captionTracks = captionTracks
    }
}

public struct ProjectSettings: Codable, Equatable, Sendable {
    public var autosaveIntervalSeconds: Int
    public var audioDuckingPresetEnabled: Bool
    public var defaultQualityMode: String

    public init(
        autosaveIntervalSeconds: Int = 30,
        audioDuckingPresetEnabled: Bool = true,
        defaultQualityMode: String = "full"
    ) {
        self.autosaveIntervalSeconds = autosaveIntervalSeconds
        self.audioDuckingPresetEnabled = audioDuckingPresetEnabled
        self.defaultQualityMode = defaultQualityMode
    }
}

public struct MigrationEvent: Codable, Equatable, Sendable {
    public var fromVersion: Int
    public var toVersion: Int
    public var migratedAt: Date

    public init(fromVersion: Int, toVersion: Int, migratedAt: Date = Date()) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.migratedAt = migratedAt
    }
}

public struct ProjectMetadata: Codable, Equatable, Sendable {
    public var migrationLog: [MigrationEvent]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        migrationLog: [MigrationEvent] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.migrationLog = migrationLog
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Project: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var fps: Double
    public var colorSpace: String
    public var sequences: [EditorSequence]
    public var bins: [MediaBin]
    public var assets: [MediaAsset]
    public var settings: ProjectSettings
    public var metadata: ProjectMetadata

    public init(
        schemaVersion: Int = Project.currentSchemaVersion,
        id: UUID = UUID(),
        name: String,
        fps: Double,
        colorSpace: String = "Rec.709",
        sequences: [EditorSequence] = [],
        bins: [MediaBin] = [],
        assets: [MediaAsset] = [],
        settings: ProjectSettings = ProjectSettings(),
        metadata: ProjectMetadata = ProjectMetadata()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.fps = fps
        self.colorSpace = colorSpace
        self.sequences = sequences
        self.bins = bins
        self.assets = assets
        self.settings = settings
        self.metadata = metadata
    }
}

public struct ExportPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var container: String
    public var videoCodec: String
    public var audioCodec: String
    public var resolution: String
    public var bitrateMbps: Double
    public var fps: Double

    public init(
        id: String,
        name: String,
        container: String,
        videoCodec: String,
        audioCodec: String,
        resolution: String,
        bitrateMbps: Double,
        fps: Double
    ) {
        self.id = id
        self.name = name
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.resolution = resolution
        self.bitrateMbps = bitrateMbps
        self.fps = fps
    }
}
