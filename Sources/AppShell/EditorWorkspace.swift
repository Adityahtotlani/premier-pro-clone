import Foundation
import SwiftUI
import ProjectCore
import TimelineCore
import PlaybackCore
import RenderCore
import AICore
import IOAdapters
#if canImport(AVKit)
import AVKit
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif


public enum EditorCommand {
    public static let newProject = Notification.Name("EditorCommand.newProject")
    public static let openProject = Notification.Name("EditorCommand.openProject")
    public static let saveProject = Notification.Name("EditorCommand.saveProject")
    public static let importMedia = Notification.Name("EditorCommand.importMedia")
    public static let generateProxyManifest = Notification.Name("EditorCommand.generateProxyManifest")
    public static let restoreLatestAutosave = Notification.Name("EditorCommand.restoreLatestAutosave")
    public static let relinkFirstMissingAsset = Notification.Name("EditorCommand.relinkFirstMissingAsset")
    public static let retryLatestExport = Notification.Name("EditorCommand.retryLatestExport")
    public static let openLatestExport = Notification.Name("EditorCommand.openLatestExport")
    public static let revealLatestExport = Notification.Name("EditorCommand.revealLatestExport")
    public static let appendFirstAsset = Notification.Name("EditorCommand.appendFirstAsset")
    public static let splitFirstClip = Notification.Name("EditorCommand.splitFirstClip")
    public static let rippleDeleteFirstClip = Notification.Name("EditorCommand.rippleDeleteFirstClip")
    public static let undo = Notification.Name("EditorCommand.undo")
    public static let redo = Notification.Name("EditorCommand.redo")
    public static let newSequence = Notification.Name("EditorCommand.newSequence")
    public static let duplicateSequence = Notification.Name("EditorCommand.duplicateSequence")
    public static let addVideoTrack = Notification.Name("EditorCommand.addVideoTrack")
    public static let addAudioTrack = Notification.Name("EditorCommand.addAudioTrack")
    public static let toggleTimelineEditMode = Notification.Name("EditorCommand.toggleTimelineEditMode")
    public static let addMarker = Notification.Name("EditorCommand.addMarker")
    public static let nextMarker = Notification.Name("EditorCommand.nextMarker")
    public static let toggleTimelineMode = Notification.Name("EditorCommand.toggleTimelineMode")
    public static let toggleShortcutHelp = Notification.Name("EditorCommand.toggleShortcutHelp")
    public static let toggleBrowserPanel = Notification.Name("EditorCommand.toggleBrowserPanel")
    public static let toggleInspectorPanel = Notification.Name("EditorCommand.toggleInspectorPanel")
    public static let applyEditingWorkspacePreset = Notification.Name("EditorCommand.applyEditingWorkspacePreset")
    public static let applyFocusedWorkspacePreset = Notification.Name("EditorCommand.applyFocusedWorkspacePreset")
    public static let applyCaptionsWorkspacePreset = Notification.Name("EditorCommand.applyCaptionsWorkspacePreset")
    public static let moveInspectorLeft = Notification.Name("EditorCommand.moveInspectorLeft")
    public static let moveInspectorRight = Notification.Name("EditorCommand.moveInspectorRight")
    public static let resetWorkspaceLayout = Notification.Name("EditorCommand.resetWorkspaceLayout")
    public static let playPause = Notification.Name("EditorCommand.playPause")
    public static let jumpToStart = Notification.Name("EditorCommand.jumpToStart")
    public static let jumpToEnd = Notification.Name("EditorCommand.jumpToEnd")
    public static let stepBackwardFrame = Notification.Name("EditorCommand.stepBackwardFrame")
    public static let stepForwardFrame = Notification.Name("EditorCommand.stepForwardFrame")
    public static let shuttleBackward = Notification.Name("EditorCommand.shuttleBackward")
    public static let shuttleStop = Notification.Name("EditorCommand.shuttleStop")
    public static let shuttleForward = Notification.Name("EditorCommand.shuttleForward")
    public static let nextEditPoint = Notification.Name("EditorCommand.nextEditPoint")
    public static let previousEditPoint = Notification.Name("EditorCommand.previousEditPoint")
    public static let cyclePlaybackRate = Notification.Name("EditorCommand.cyclePlaybackRate")
    public static let togglePreviewMute = Notification.Name("EditorCommand.togglePreviewMute")
    public static let setInPoint = Notification.Name("EditorCommand.setInPoint")
    public static let setOutPoint = Notification.Name("EditorCommand.setOutPoint")
    public static let clearInOutPoints = Notification.Name("EditorCommand.clearInOutPoints")
    public static let toggleLoopPlayback = Notification.Name("EditorCommand.toggleLoopPlayback")

    public static func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

public enum TimelineEditMode: String, CaseIterable, Sendable {
    case insert
    case overwrite
}

@MainActor
public final class EditorWorkspace: ObservableObject {
    public struct SilenceSuggestion: Identifiable, Equatable {
        public var id: UUID
        public var start: TimeInterval
        public var end: TimeInterval
        public var reason: String

        public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, reason: String) {
            self.id = id
            self.start = start
            self.end = end
            self.reason = reason
        }
    }

    public struct ExportHistoryItem: Identifiable, Equatable, Codable, Sendable {
        public var id: UUID
        public var jobID: UUID
        public var sequenceID: UUID
        public var sequenceName: String
        public var presetID: String
        public var presetName: String
        public var resolution: String
        public var container: String
        public var outputURL: URL
        public var outputFileName: String?
        public var completedAt: Date

        public init(
            id: UUID = UUID(),
            jobID: UUID,
            sequenceID: UUID,
            sequenceName: String,
            presetID: String,
            presetName: String,
            resolution: String,
            container: String,
            outputURL: URL,
            outputFileName: String? = nil,
            completedAt: Date = Date()
        ) {
            self.id = id
            self.jobID = jobID
            self.sequenceID = sequenceID
            self.sequenceName = sequenceName
            self.presetID = presetID
            self.presetName = presetName
            self.resolution = resolution
            self.container = container
            self.outputURL = outputURL
            self.outputFileName = outputFileName
            self.completedAt = completedAt
        }
    }

    public struct RecentProject: Identifiable, Equatable, Codable, Sendable {
        public var id: UUID
        public var name: String
        public var path: String
        public var lastOpened: Date

        public init(id: UUID = UUID(), name: String, path: String, lastOpened: Date = Date()) {
            self.id = id
            self.name = name
            self.path = path
            self.lastOpened = lastOpened
        }

        public var url: URL {
            URL(fileURLWithPath: path)
        }
    }

    @Published public var project: Project
    @Published public var statusMessage: String
    @Published public var lastAIArtifact: AIArtifact?
    @Published public var activeSequenceID: UUID?
    @Published public var selectedAssetID: UUID?
    @Published public var selectedClipID: UUID?
    @Published public var currentProjectBundleURL: URL?
    @Published public var lastAutosaveURL: URL?
    @Published public var playheadTime: TimeInterval
    @Published public var isPlaying: Bool
    @Published public var showsShortcutHelp: Bool
    @Published public var exportProgress: Double
    @Published public var exportStatusMessage: String
    @Published public var completedExports: [RenderJob]
    @Published public var exportHistory: [ExportHistoryItem]
    @Published public var recentProjects: [RecentProject]
    @Published public var selectedClipIDs: Set<UUID>
    @Published public var previewVolume: Double
    @Published public var isPreviewMuted: Bool
    @Published public var playbackRate: Double
    @Published public var inPoint: TimeInterval?
    @Published public var outPoint: TimeInterval?
    @Published public var isLoopPlaybackEnabled: Bool
    @Published public var timelineEditMode: TimelineEditMode
    @Published public var targetedVideoTrackID: UUID?
    @Published public var targetedAudioTrackID: UUID?
    @Published public var lockedTrackIDs: Set<UUID>
    @Published public var sourcePlayheadTime: TimeInterval
    @Published public var sourceInPoint: TimeInterval?
    @Published public var sourceOutPoint: TimeInterval?
    @Published public var transcriptQuery: String
    @Published public var transcriptMatches: [CaptionSegment]
    @Published public var selectedCaptionSegmentID: UUID?
    @Published public var silenceSuggestions: [SilenceSuggestion]

    public let timelineEngine: TimelineEngine
    public let playbackEngine: PlaybackEngine
    public let renderEngine: RenderEngine
    public let aiService: AIAssistService

    private let projectStore: ProjectStore
    private let mediaImporter: MediaImporter
    private let proxyManager: ProxyManager
    private let userDefaults: UserDefaults
    private let recentProjectsKey = "PremierClone.RecentProjects"
    private let recentProjectsLimit = 8
    private var autosaveTimer: Timer?
    private var exportProgressTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var undoHistory: [Project]
    private var redoHistory: [Project]
    private var lastInspectorSnapshotAt: Date?

    public init(
        project: Project = ProjectFactory.starterProject(name: "Untitled Project"),
        timelineEngine: TimelineEngine = TimelineEngine(),
        playbackEngine: PlaybackEngine = PlaybackEngine(),
        renderEngine: RenderEngine = RenderEngine(),
        aiService: AIAssistService = AIAssistService(),
        projectStore: ProjectStore = ProjectStore(),
        mediaImporter: MediaImporter = MediaImporter(),
        proxyManager: ProxyManager = ProxyManager(),
        userDefaults: UserDefaults = .standard
    ) {
        self.project = project
        self.timelineEngine = timelineEngine
        self.playbackEngine = playbackEngine
        self.renderEngine = renderEngine
        self.aiService = aiService
        self.projectStore = projectStore
        self.mediaImporter = mediaImporter
        self.proxyManager = proxyManager
        self.userDefaults = userDefaults

        statusMessage = "Ready"
        playheadTime = 0
        isPlaying = false
        showsShortcutHelp = false
        activeSequenceID = project.sequences.first?.id
        selectedAssetID = project.assets.first?.id
        exportProgress = 0
        exportStatusMessage = "Idle"
        completedExports = []
        exportHistory = []
        recentProjects = []
        selectedClipIDs = []
        previewVolume = 1.0
        isPreviewMuted = false
        playbackRate = 1.0
        inPoint = nil
        outPoint = nil
        isLoopPlaybackEnabled = false
        timelineEditMode = .insert
        targetedVideoTrackID = project.sequences.first?.videoTracks.first?.id
        targetedAudioTrackID = project.sequences.first?.audioTracks.first?.id
        lockedTrackIDs = []
        sourcePlayheadTime = 0
        sourceInPoint = nil
        sourceOutPoint = nil
        transcriptQuery = ""
        transcriptMatches = []
        selectedCaptionSegmentID = nil
        silenceSuggestions = []
        undoHistory = []
        redoHistory = []
        lastInspectorSnapshotAt = nil
        recentProjects = loadRecentProjects()
        refreshTranscriptMatches()
    }

    public var activeSequence: EditorSequence? {
        if let activeSequenceID,
           let matched = project.sequences.first(where: { $0.id == activeSequenceID }) {
            return matched
        }
        return project.sequences.first
    }

    public var workspaceLayoutSettings: WorkspaceLayoutSettings {
        project.settings.workspaceLayout
    }

    public func updateWorkspaceLayoutSettings(_ settings: WorkspaceLayoutSettings) {
        project.settings.workspaceLayout = settings
    }

    public var canUndo: Bool {
        !undoHistory.isEmpty
    }

    public var canRedo: Bool {
        !redoHistory.isEmpty
    }

    private var selectedSourceAsset: MediaAsset? {
        if let selectedAssetID,
           let selected = project.assets.first(where: { $0.id == selectedAssetID }) {
            return selected
        }
        return project.assets.first
    }

    public var missingAssetIDs: [UUID] {
        project.assets
            .filter { !FileManager.default.fileExists(atPath: $0.path) }
            .map(\.id)
    }

    public var missingAssets: [MediaAsset] {
        project.assets.filter { missingAssetIDs.contains($0.id) }
    }

    public var latestAvailableAutosaveURL: URL? {
        guard let currentProjectBundleURL else {
            return nil
        }
        return try? projectStore.latestAutosaveURL(from: currentProjectBundleURL)
    }

    public var exportPresets: [ExportPreset] {
        ExportPresetRegistry.defaultPresets
    }

    public var exportSupportStatus: ExportSupportStatus {
        guard let sequence = activeSequence else {
            return .unsupported("No active sequence selected.")
        }

        if sequence.videoTracks.flatMap(\.clips).isEmpty
            && sequence.audioTracks.flatMap(\.clips).isEmpty {
            return .emptySequence
        }

        if let preflightError = renderEngine.preflight(project: project, sequence: sequence) {
            switch preflightError {
            case .missingMedia(let reason):
                return .missingMedia(reason)
            case .unsupportedSequence(let reason):
                return .unsupported(reason)
            case .queueBusy:
                return .unsupported("Another export is already running.")
            case .unknownPreset:
                return .unsupported("Unknown export preset.")
            case .missingJob:
                return .unsupported("Render job is unavailable.")
            case .exportFailed(let reason):
                return .unsupported(reason)
            }
        }

        return .ready
    }

    public var canExport: Bool {
        switch exportSupportStatus {
        case .ready:
            return true
        case .missingMedia, .emptySequence, .unsupported:
            return false
        }
    }

    public var canSlipSelectedClip: Bool {
        guard let sequence = activeSequence, let selection = clipSelection else {
            return false
        }
        let targets = linkedEditTargets(
            for: (clip: selection.clip, trackID: selection.trackID, kind: selection.kind),
            in: sequence
        )
        return !targets.isEmpty && !hasLockedTrack(in: targets)
    }

    public var exportSupportMessage: String {
        switch exportSupportStatus {
        case .ready:
            return "Export ready (prototype: 1 video + 1 audio track; no effects/transforms/gain yet)."
        case .missingMedia(let reason):
            return "Relink media before exporting: \(reason)"
        case .unsupported(let reason):
            return "Export not supported: \(reason)"
        case .emptySequence:
            return "Add clips to the sequence before exporting."
        }
    }

    public func exportPreset(id: String) -> ExportPreset? {
        exportPresets.first(where: { $0.id == id })
    }

    public var playbackRange: (start: TimeInterval, end: TimeInterval)? {
        normalizedPlaybackRange
    }

    public var sourceRange: (start: TimeInterval, end: TimeInterval)? {
        normalizedSourceRange
    }

    public var selectedClip: ClipRef? {
        clipSelection?.clip
    }

    public var selectedClipTrackKind: TrackKind? {
        clipSelection?.kind
    }

    private struct ClipEditTarget: Hashable {
        var clipID: UUID
        var trackID: UUID
        var kind: TrackKind
    }

    private struct SourceInsertionRange {
        var inTime: TimeInterval
        var outTime: TimeInterval
        var usesMarkedRange: Bool
    }

    private var clipSelection: (clip: ClipRef, kind: TrackKind, trackID: UUID)? {
        guard let selectedClipID else { return nil }
        guard let sequence = activeSequence else { return nil }

        for track in sequence.videoTracks {
            if let clip = track.clips.first(where: { $0.id == selectedClipID }) {
                return (clip, .video, track.id)
            }
        }

        for track in sequence.audioTracks {
            if let clip = track.clips.first(where: { $0.id == selectedClipID }) {
                return (clip, .audio, track.id)
            }
        }

        return nil
    }

    public func createNewProject(named name: String = "Untitled Project") {
        exportProgressTask?.cancel()
        exportProgressTask = nil
        stopPlaybackLoop()
        project = ProjectFactory.starterProject(name: name)
        currentProjectBundleURL = nil
        lastAutosaveURL = nil
        lastAIArtifact = nil
        selectedAssetID = nil
        clearClipSelection()
        activeSequenceID = project.sequences.first?.id
        playheadTime = 0
        exportProgress = 0
        exportStatusMessage = "Idle"
        completedExports = []
        exportHistory = []
        inPoint = nil
        outPoint = nil
        isLoopPlaybackEnabled = false
        timelineEditMode = .insert
        lockedTrackIDs = []
        targetedVideoTrackID = project.sequences.first?.videoTracks.first?.id
        targetedAudioTrackID = project.sequences.first?.audioTracks.first?.id
        sourcePlayheadTime = 0
        sourceInPoint = nil
        sourceOutPoint = nil
        transcriptQuery = ""
        transcriptMatches = []
        selectedCaptionSegmentID = nil
        silenceSuggestions = []
        undoHistory = []
        redoHistory = []
        lastInspectorSnapshotAt = nil
        refreshTranscriptMatches()
        statusMessage = "Created new project"
        restartAutosaveTimer()
        exportHistory = []
    }

    private func applyLoadedProject(
        _ loaded: Project,
        bundleURL: URL,
        status: String,
        restoredAutosaveURL: URL? = nil
    ) {
        project = loaded
        currentProjectBundleURL = bundleURL
        lastAutosaveURL = restoredAutosaveURL
        selectedAssetID = loaded.assets.first?.id
        clearClipSelection()
        activeSequenceID = loaded.sequences.first?.id
        playheadTime = 0
        exportProgress = 0
        exportStatusMessage = "Idle"
        completedExports = []
        exportHistory = []
        inPoint = nil
        outPoint = nil
        isLoopPlaybackEnabled = false
        timelineEditMode = .insert
        lockedTrackIDs = []
        targetedVideoTrackID = loaded.sequences.first?.videoTracks.first?.id
        targetedAudioTrackID = loaded.sequences.first?.audioTracks.first?.id
        sourcePlayheadTime = 0
        sourceInPoint = nil
        sourceOutPoint = nil
        transcriptQuery = ""
        transcriptMatches = []
        selectedCaptionSegmentID = nil
        silenceSuggestions = []
        undoHistory = []
        redoHistory = []
        lastInspectorSnapshotAt = nil
        refreshTranscriptMatches()
        exportHistory = loadExportHistory()
        registerRecentProject(bundleURL: bundleURL, name: loaded.name)
        statusMessage = status
        restartAutosaveTimer()
    }

    public func openProject(at bundleURL: URL) {
        do {
            exportProgressTask?.cancel()
            exportProgressTask = nil
            stopPlaybackLoop()
            let loaded = try projectStore.load(from: bundleURL)
            applyLoadedProject(loaded, bundleURL: bundleURL, status: "Opened \(bundleURL.lastPathComponent)")
        } catch {
            do {
                let autosaveURL = try projectStore.latestAutosaveURL(from: bundleURL)
                if let recovered = try projectStore.recoverLatestAutosave(from: bundleURL) {
                    stopPlaybackLoop()
                    let restoredLabel = autosaveURL?.lastPathComponent ?? bundleURL.lastPathComponent
                    applyLoadedProject(
                        recovered,
                        bundleURL: bundleURL,
                        status: "Recovered latest autosave from \(restoredLabel)",
                        restoredAutosaveURL: autosaveURL
                    )
                    return
                }
                statusMessage = "Failed to open project: \(error.localizedDescription)"
            } catch {
                statusMessage = "Project open failed and no autosave recovery available"
            }
        }
    }

    public func saveProject() {
        guard let currentProjectBundleURL else {
            saveProjectAsUsingDialog()
            return
        }

        do {
            try projectStore.save(project: project, to: currentProjectBundleURL)
            statusMessage = "Saved \(currentProjectBundleURL.lastPathComponent)"
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    public func saveProjectAs(to bundleURL: URL) {
        do {
            try projectStore.createProjectBundle(at: bundleURL, with: project)
            currentProjectBundleURL = bundleURL
            let persistedHistory = loadExportHistory()
            if !persistedHistory.isEmpty || exportHistory.isEmpty {
                exportHistory = persistedHistory
            }
            registerRecentProject(bundleURL: bundleURL, name: project.name)
            statusMessage = "Saved as \(bundleURL.lastPathComponent)"
            restartAutosaveTimer()
        } catch {
            statusMessage = "Save as failed: \(error.localizedDescription)"
        }
    }

    public func switchTimelineMode() {
        guard let sequence = activeSequence else { return }

        stopPlaybackLoop()
        let nextMode: TimelineMode = sequence.mode == .track ? .magnetic : .track
        recordUndoSnapshot()

        do {
            let result = try timelineEngine.apply(
                operation: .changeMode(sequenceID: sequence.id, mode: nextMode),
                to: project
            )
            project = result.0
            sanitizeSelectedClip()
            playheadTime = min(playheadTime, result.1.resultingDuration)
            statusMessage = "Switched to \(nextMode.rawValue) mode"
        } catch {
            statusMessage = "Mode switch failed: \(error.localizedDescription)"
        }
    }

    public func appendFirstAssetToTimeline() {
        guard let firstAsset = project.assets.first else {
            statusMessage = "Import media before inserting clips"
            return
        }

        selectAsset(firstAsset.id)
        appendAssetToTimeline(assetID: firstAsset.id)
    }

    public func appendAssetToTimeline(assetID: UUID) {
        insertAssetToTimeline(assetID: assetID, at: playheadTime)
    }

    public func insertAssetToTimeline(assetID: UUID, at timelineTime: TimeInterval) {
        insertAssetToTimeline(assetID: assetID, timelineTime: timelineTime, usingMarkedSourceRange: true)
    }

    public func appendSelectedSourceRangeToTimeline() {
        guard let selectedAssetID else {
            statusMessage = "Select an asset in the browser first"
            return
        }
        appendAssetToTimeline(assetID: selectedAssetID)
    }

    public func appendSelectedAssetToTimelineEnd() {
        guard let selectedAssetID else {
            statusMessage = "Select an asset in the browser first"
            return
        }
        let sequenceEnd = activeSequence?.duration ?? 0
        insertAssetToTimeline(assetID: selectedAssetID, at: sequenceEnd)
    }

    private func insertAssetToTimeline(
        assetID: UUID,
        timelineTime: TimeInterval,
        usingMarkedSourceRange: Bool
    ) {
        guard let asset = project.assets.first(where: { $0.id == assetID }) else {
            statusMessage = "Asset not found"
            return
        }
        if selectedAssetID != assetID {
            sourcePlayheadTime = 0
            sourceInPoint = nil
            sourceOutPoint = nil
        }
        selectedAssetID = assetID

        guard let sequence = activeSequence,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequence.id }) else {
            statusMessage = "No active sequence"
            return
        }

        var workingProject = project
        let tracks = ensurePrimaryTracks(in: &workingProject, sequenceIndex: sequenceIndex)
        let sourceRange = sourceInsertionRange(for: asset, usingMarkedRange: usingMarkedSourceRange)
        let clipDuration = sourceRange.outTime - sourceRange.inTime
        let insertionTime = max(0, timelineTime)
        let insertionEnd = insertionTime + clipDuration

        let requiresVideoTrack = asset.type == .video || asset.type == .image || asset.type == .unknown
        let requiresAudioTrack = asset.type == .video || asset.type == .audio

        if (requiresVideoTrack && isTrackLocked(tracks.videoTrackID)) ||
            (requiresAudioTrack && isTrackLocked(tracks.audioTrackID)) {
            statusMessage = "Target track is locked"
            return
        }

        recordUndoSnapshot()

        if timelineEditMode == .overwrite {
            if requiresVideoTrack {
                applyOverwrite(
                    in: &workingProject.sequences[sequenceIndex],
                    trackID: tracks.videoTrackID,
                    kind: .video,
                    start: insertionTime,
                    end: insertionEnd
                )
            }
            if requiresAudioTrack {
                applyOverwrite(
                    in: &workingProject.sequences[sequenceIndex],
                    trackID: tracks.audioTrackID,
                    kind: .audio,
                    start: insertionTime,
                    end: insertionEnd
                )
            }
        } else if workingProject.sequences[sequenceIndex].mode == .magnetic {
            shiftClipsForMagneticInsert(
                in: &workingProject.sequences[sequenceIndex],
                insertionTime: insertionTime,
                shiftBy: clipDuration
            )
        }

        do {
            var selectedClipAfterInsert: UUID?

            switch asset.type {
            case .video:
                var videoClip = ClipRef(
                    assetID: asset.id,
                    inTime: sourceRange.inTime,
                    outTime: sourceRange.outTime,
                    timelineIn: insertionTime
                )
                var linkedAudio = ClipRef(
                    assetID: asset.id,
                    inTime: sourceRange.inTime,
                    outTime: sourceRange.outTime,
                    timelineIn: insertionTime,
                    linkedAudioIDs: [videoClip.id]
                )
                videoClip.linkedAudioIDs = [linkedAudio.id]
                linkedAudio.linkedAudioIDs = [videoClip.id]

                let insertedVideo = try timelineEngine.apply(
                    operation: .insertClip(
                        sequenceID: sequence.id,
                        trackID: tracks.videoTrackID,
                        trackKind: .video,
                        clip: videoClip
                    ),
                    to: workingProject
                )
                workingProject = insertedVideo.0

                let insertedAudio = try timelineEngine.apply(
                    operation: .insertClip(
                        sequenceID: sequence.id,
                        trackID: tracks.audioTrackID,
                        trackKind: .audio,
                        clip: linkedAudio
                    ),
                    to: workingProject
                )
                workingProject = insertedAudio.0

                selectedClipAfterInsert = videoClip.id

            case .audio:
                let audioClip = ClipRef(
                    assetID: asset.id,
                    inTime: sourceRange.inTime,
                    outTime: sourceRange.outTime,
                    timelineIn: insertionTime
                )
                let insertedAudio = try timelineEngine.apply(
                    operation: .insertClip(
                        sequenceID: sequence.id,
                        trackID: tracks.audioTrackID,
                        trackKind: .audio,
                        clip: audioClip
                    ),
                    to: workingProject
                )
                workingProject = insertedAudio.0
                selectedClipAfterInsert = audioClip.id

            case .image, .unknown:
                let videoClip = ClipRef(
                    assetID: asset.id,
                    inTime: sourceRange.inTime,
                    outTime: sourceRange.outTime,
                    timelineIn: insertionTime
                )
                let insertedVideo = try timelineEngine.apply(
                    operation: .insertClip(
                        sequenceID: sequence.id,
                        trackID: tracks.videoTrackID,
                        trackKind: .video,
                        clip: videoClip
                    ),
                    to: workingProject
                )
                workingProject = insertedVideo.0
                selectedClipAfterInsert = videoClip.id
            }

            project = workingProject
            selectClip(selectedClipAfterInsert)
            playheadTime = insertionTime + clipDuration
            let sourceLabel = sourceRange.usesMarkedRange ? " \(timecode(sourceRange.inTime))-\(timecode(sourceRange.outTime))" : ""
            statusMessage = "\(timelineEditMode.rawValue.capitalized) \(asset.name)\(sourceLabel) at \(timecode(insertionTime))"
        } catch {
            statusMessage = "Insert failed: \(error.localizedDescription)"
        }
    }

    public func splitFirstClipAtPlayhead() {
        splitSelectedClipAtPlayhead()
    }

    public func splitSelectedClipAtPlayhead() {
        guard let sequence = activeSequence else {
            statusMessage = "No active sequence"
            return
        }

        guard let target = resolveEditableTarget(in: sequence) else {
            statusMessage = "No clip available to split"
            return
        }
        selectClip(target.clip.id)

        guard target.clip.duration > 0.2 else {
            statusMessage = "Clip too short to split"
            return
        }

        let splitTime = min(max(target.clip.timelineIn + 0.1, playheadTime), target.clip.timelineIn + target.clip.duration - 0.1)
        let splitTargets = linkedEditTargets(for: target, in: sequence)
        guard !hasLockedTrack(in: splitTargets) else {
            statusMessage = "Track is locked"
            return
        }
        recordUndoSnapshot()

        var workingProject = project
        var splitCount = 0
        var selectedTrailingID: UUID?

        do {
            for candidate in splitTargets {
                do {
                    let result = try timelineEngine.apply(
                        operation: .splitClip(
                            sequenceID: sequence.id,
                            trackID: candidate.trackID,
                            trackKind: candidate.kind,
                            clipID: candidate.clipID,
                            splitTime: splitTime
                        ),
                        to: workingProject
                    )
                    workingProject = result.0
                    splitCount += 1

                    if candidate.clipID == target.clip.id {
                        selectedTrailingID = result.1.affectedClipIDs.last
                    }
                } catch TimelineEngineError.invalidTimeRange {
                    continue
                }
            }

            guard splitCount > 0 else {
                statusMessage = "Playhead must be inside a clip to split"
                return
            }

            project = workingProject
            if let selectedTrailingID {
                selectClip(selectedTrailingID)
            }
            sanitizeSelectedClip()
            statusMessage = splitCount > 1 ? "Split linked clips at \(timecode(splitTime))" : "Split clip at \(timecode(splitTime))"
        } catch {
            statusMessage = "Split failed: \(error.localizedDescription)"
        }
    }

    public func rippleDeleteFirstClip() {
        rippleDeleteSelectedOrFirstClip()
    }

    private func rippleDeleteSelectedOrFirstClip() {
        guard let sequence = activeSequence else {
            statusMessage = "No active sequence"
            return
        }

        guard let target = resolveEditableTarget(in: sequence) else {
            statusMessage = "No clip available to ripple delete"
            return
        }
        selectClip(target.clip.id)

        let deleteTargets = linkedEditTargets(for: target, in: sequence)
        guard !hasLockedTrack(in: deleteTargets) else {
            statusMessage = "Track is locked"
            return
        }
        recordUndoSnapshot()
        var workingProject = project
        var deleteCount = 0

        do {
            for candidate in deleteTargets {
                do {
                    let result = try timelineEngine.apply(
                        operation: .rippleDelete(
                            sequenceID: sequence.id,
                            trackID: candidate.trackID,
                            trackKind: candidate.kind,
                            clipID: candidate.clipID
                        ),
                        to: workingProject
                    )
                    workingProject = result.0
                    deleteCount += 1
                } catch TimelineEngineError.clipNotFound {
                    continue
                }
            }

            guard deleteCount > 0 else {
                statusMessage = "Nothing deleted"
                return
            }

            project = workingProject
            sanitizeSelectedClip()
            playheadTime = min(playheadTime, activeSequence?.duration ?? playheadTime)
            statusMessage = deleteCount > 1 ? "Ripple deleted linked clips" : "Ripple deleted clip"
        } catch {
            statusMessage = "Ripple delete failed: \(error.localizedDescription)"
        }
    }

    public func runAutoCaptions() {
        guard let sequence = activeSequence,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequence.id }) else {
            return
        }
        guard sequence.duration > 0 else {
            statusMessage = "Add timeline clips before generating captions"
            return
        }

        do {
            lastAIArtifact = try aiService.run(taskType: .autoCaptions, sequenceID: sequence.id, options: [:], in: project)
            recordUndoSnapshot()
            var updatedProject = project
            let segmentLength: TimeInterval = 2.8
            var segments: [CaptionSegment] = []
            var cursor: TimeInterval = 0
            var index = 1

            while cursor < sequence.duration {
                let end = min(sequence.duration, cursor + segmentLength)
                segments.append(
                    CaptionSegment(
                        start: cursor,
                        end: end,
                        text: "Caption \(index)",
                        confidence: 0.85
                    )
                )
                cursor = end
                index += 1
            }

            if updatedProject.sequences[sequenceIndex].captionTracks.isEmpty {
                updatedProject.sequences[sequenceIndex].captionTracks = [CaptionTrack(language: "en", segments: segments)]
            } else {
                updatedProject.sequences[sequenceIndex].captionTracks[0].segments = segments
                updatedProject.sequences[sequenceIndex].captionTracks[0].language = "en"
            }

            project = updatedProject
            selectedCaptionSegmentID = segments.first?.id
            refreshTranscriptMatches()
            statusMessage = "Generated \(segments.count) captions"
        } catch {
            statusMessage = "Caption generation failed"
        }
    }

    public func runSilenceSuggestions() {
        guard let sequence = activeSequence else { return }

        do {
            lastAIArtifact = try aiService.run(taskType: .silenceRemoval, sequenceID: sequence.id, options: [:], in: project)

            let anchorClips = sequence.audioTracks.flatMap(\.clips).sorted(by: { $0.timelineIn < $1.timelineIn })
            let fallbackClips = sequence.videoTracks.flatMap(\.clips).sorted(by: { $0.timelineIn < $1.timelineIn })
            let scanClips = anchorClips.isEmpty ? fallbackClips : anchorClips
            guard !scanClips.isEmpty else {
                silenceSuggestions = []
                statusMessage = "No clips available to analyze silence"
                return
            }

            var suggestions: [SilenceSuggestion] = []
            let threshold: TimeInterval = 0.35

            if let first = scanClips.first, first.timelineIn > threshold {
                suggestions.append(
                    SilenceSuggestion(start: 0, end: first.timelineIn, reason: "Leading silence")
                )
            }

            for pair in zip(scanClips, scanClips.dropFirst()) {
                let leftEnd = pair.0.timelineIn + pair.0.duration
                let rightStart = pair.1.timelineIn
                let gap = rightStart - leftEnd
                if gap > threshold {
                    suggestions.append(
                        SilenceSuggestion(
                            start: leftEnd,
                            end: rightStart,
                            reason: "Gap \(String(format: "%.2fs", gap))"
                        )
                    )
                }
            }

            if let last = scanClips.last {
                let sequenceEnd = max(sequence.duration, last.timelineIn + last.duration)
                let tailGap = sequenceEnd - (last.timelineIn + last.duration)
                if tailGap > threshold {
                    suggestions.append(
                        SilenceSuggestion(
                            start: last.timelineIn + last.duration,
                            end: sequenceEnd,
                            reason: "Trailing silence"
                        )
                    )
                }
            }

            silenceSuggestions = suggestions
            statusMessage = suggestions.isEmpty ? "No silence gaps detected" : "Detected \(suggestions.count) silence gaps"
        } catch {
            statusMessage = "Silence detection failed"
        }
    }

    public func runHighlightSuggestions() {
        guard let sequence = activeSequence else { return }

        do {
            lastAIArtifact = try aiService.run(taskType: .highlightSuggestions, sequenceID: sequence.id, options: [:], in: project)
            statusMessage = "Generated highlights"
        } catch {
            statusMessage = "Highlight generation failed"
        }
    }

    public func updateTranscriptQuery(_ value: String) {
        transcriptQuery = value
        refreshTranscriptMatches()
        runTranscriptSearchArtifact()
    }

    public func jumpToTranscriptSegment(_ segmentID: UUID) {
        guard let segment = activeSequence?.captionTracks.flatMap(\.segments).first(where: { $0.id == segmentID }) else {
            return
        }
        selectedCaptionSegmentID = segmentID
        updatePlayhead(to: segment.start)
        statusMessage = "Jumped to caption segment"
    }

    public func updateCaptionSegmentText(_ segmentID: UUID, text: String) {
        guard let sequenceID = activeSequenceID ?? project.sequences.first?.id,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequenceID }) else {
            return
        }
        guard let trackIndex = project.sequences[sequenceIndex].captionTracks.indices.first else {
            return
        }
        guard let segmentIndex = project.sequences[sequenceIndex].captionTracks[trackIndex].segments.firstIndex(where: { $0.id == segmentID }) else {
            return
        }

        if project.sequences[sequenceIndex].captionTracks[trackIndex].segments[segmentIndex].text == text {
            return
        }

        maybeRecordInspectorSnapshot()
        var updatedProject = project
        updatedProject.sequences[sequenceIndex].captionTracks[trackIndex].segments[segmentIndex].text = text
        project = updatedProject
        selectedCaptionSegmentID = segmentID
        refreshTranscriptMatches()
    }

    public func applySilenceSuggestion(_ suggestionID: UUID) {
        guard let suggestion = silenceSuggestions.first(where: { $0.id == suggestionID }) else {
            return
        }

        let removed = closeTimelineGap(start: suggestion.start, end: suggestion.end)
        if removed {
            silenceSuggestions.removeAll(where: { $0.id == suggestionID })
            statusMessage = "Applied silence cut"
            runSilenceSuggestions()
        } else {
            statusMessage = "Unable to apply selected silence cut"
        }
    }

    public func applyAllSilenceSuggestions() {
        let ordered = silenceSuggestions.sorted(by: { $0.start < $1.start })
        guard !ordered.isEmpty else {
            statusMessage = "No silence suggestions to apply"
            return
        }

        var applied = 0
        for suggestion in ordered.reversed() {
            if closeTimelineGap(start: suggestion.start, end: suggestion.end) {
                applied += 1
            }
        }

        runSilenceSuggestions()
        statusMessage = applied > 0 ? "Applied \(applied) silence cuts" : "No silence cuts applied"
    }

    public func applySmartReframePreset(_ aspect: String) {
        guard selectedClipTrackKind == .video, selectedClip != nil else {
            statusMessage = "Select a video clip first"
            return
        }

        do {
            if let sequence = activeSequence {
                lastAIArtifact = try aiService.run(
                    taskType: .smartReframe,
                    sequenceID: sequence.id,
                    options: ["aspect": aspect],
                    in: project
                )
            }
        } catch {
            // Ignore artifact error; transform preset still applies.
        }

        let preset: (scale: Double, x: Double, y: Double)
        switch aspect {
        case "9:16":
            preset = (1.34, 0, 0)
        case "1:1":
            preset = (1.18, 0, 0)
        case "16:9":
            preset = (1.0, 0, 0)
        default:
            preset = (1.0, 0, 0)
        }

        recordUndoSnapshot()
        mutateSelectedClip(recordSnapshot: false) { clip in
            clip.transforms.scaleX = preset.scale
            clip.transforms.scaleY = preset.scale
            clip.transforms.positionX = preset.x
            clip.transforms.positionY = preset.y
        }
        statusMessage = "Applied smart reframe \(aspect)"
    }

    public func enqueueExport(presetID: String = "youtube-1080p-h264") {
        guard let sequence = activeSequence else {
            statusMessage = "No active sequence to export"
            return
        }
        guard canExport else {
            exportStatusMessage = "Blocked"
            statusMessage = exportSupportMessage
            return
        }
        guard let preset = exportPreset(id: presetID) else {
            statusMessage = "Unknown export preset"
            return
        }

        do {
            _ = try renderEngine.enqueue(projectID: project.id, sequenceID: sequence.id, presetID: presetID)
            exportProgress = 0
            exportStatusMessage = "Rendering \(preset.name)"
            statusMessage = "Export job started (\(preset.name))"
            startExportTask(sequence: sequence, preset: preset)
        } catch {
            exportStatusMessage = "Failed"
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    public func cancelExport() {
        exportProgressTask?.cancel()
        exportProgressTask = nil
        exportProgress = 0
        exportStatusMessage = "Cancelled"
        renderEngine.cancelCurrentExport()
        _ = try? renderEngine.failCurrentJob()
        statusMessage = "Export cancelled"
    }

    public func retryExport(using item: ExportHistoryItem) {
        if activeSequenceID != item.sequenceID {
            setActiveSequence(item.sequenceID)
        }
        enqueueExport(presetID: item.presetID)
    }

    public func openLatestExport() {
        guard let item = exportHistory.first else {
            statusMessage = "No recent export to open"
            return
        }
        openExportOutput(item)
    }

    public func openExportOutput(_ item: ExportHistoryItem) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(exportOutputURL(for: item))
        #else
        statusMessage = "Open export output is only available on macOS"
        #endif
    }

    public func revealExportOutput(_ item: ExportHistoryItem) {
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([exportOutputURL(for: item)])
        #else
        statusMessage = "Reveal export output is only available on macOS"
        #endif
    }

    public func retryLatestExport() {
        guard let item = exportHistory.first else {
            statusMessage = "No recent export to retry"
            return
        }
        retryExport(using: item)
    }

    public func revealLatestExport() {
        guard let item = exportHistory.first else {
            statusMessage = "No recent export to reveal"
            return
        }
        revealExportOutput(item)
    }

    public func restoreLatestAutosave() {
        guard let bundleURL = currentProjectBundleURL else {
            statusMessage = "Save or open a project before restoring autosave"
            return
        }

        do {
            guard let autosaveURL = try projectStore.latestAutosaveURL(from: bundleURL),
                  let recovered = try projectStore.recoverLatestAutosave(from: bundleURL) else {
                statusMessage = "No autosave available to restore"
                return
            }

            stopPlaybackLoop()
            applyLoadedProject(
                recovered,
                bundleURL: bundleURL,
                status: "Restored latest autosave from \(autosaveURL.lastPathComponent)",
                restoredAutosaveURL: autosaveURL
            )
        } catch {
            statusMessage = "Autosave restore failed: \(error.localizedDescription)"
        }
    }

    public func importMedia(urls: [URL]) {
        let result = mediaImporter.import(urls: urls)
        guard !result.importedAssets.isEmpty else {
            statusMessage = result.warnings.isEmpty ? "No files imported" : result.warnings.joined(separator: " | ")
            return
        }

        var updatedAssets = project.assets
        var insertedAssets: [MediaAsset] = []

        for asset in result.importedAssets {
            if !updatedAssets.contains(where: { $0.path == asset.path }) {
                updatedAssets.append(asset)
                insertedAssets.append(asset)
            }
        }

        guard !insertedAssets.isEmpty else {
            let duplicateMessage = "All selected files are already in the browser"
            statusMessage = result.warnings.isEmpty ?
                duplicateMessage :
                "\(duplicateMessage) | \(result.warnings.joined(separator: " | "))"
            return
        }

        recordUndoSnapshot()

        var updatedProject = project
        updatedProject.assets = updatedAssets

        if updatedProject.bins.isEmpty {
            updatedProject.bins = [MediaBin(name: "Imported")]
        }

        if let importedBinIndex = updatedProject.bins.firstIndex(where: {
            $0.name.compare("Imported", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) ?? updatedProject.bins.indices.first {
            var ids = updatedProject.bins[importedBinIndex].assetIDs
            for asset in insertedAssets where !ids.contains(asset.id) {
                ids.append(asset.id)
            }
            updatedProject.bins[importedBinIndex].assetIDs = ids
        }

        project = updatedProject
        if selectedAssetID == nil, let firstImported = insertedAssets.first {
            selectAsset(firstImported.id)
        }
        sanitizeSelectedClip()
        let duplicateCount = max(0, result.importedAssets.count - insertedAssets.count)
        var message = "Imported \(insertedAssets.count) assets"
        if duplicateCount > 0 {
            message += " (\(duplicateCount) already in browser)"
        }
        if !result.warnings.isEmpty {
            message += " | \(result.warnings.joined(separator: " | "))"
        }
        statusMessage = message
    }

    public func createBin(named proposedName: String? = nil) {
        let baseName = sanitizeBinName(proposedName) ?? "Bin"
        let uniqueName = uniqueBinName(from: baseName)

        recordUndoSnapshot()
        var updatedProject = project
        updatedProject.bins.append(MediaBin(name: uniqueName))
        project = updatedProject
        statusMessage = "Created bin \(uniqueName)"
    }

    public func renameBin(binID: UUID, to proposedName: String) {
        guard let binIndex = project.bins.firstIndex(where: { $0.id == binID }) else {
            statusMessage = "Bin not found"
            return
        }
        guard let sanitized = sanitizeBinName(proposedName) else {
            statusMessage = "Bin name cannot be empty"
            return
        }

        let originalName = project.bins[binIndex].name
        let uniqueName = uniqueBinName(from: sanitized, excluding: binID)
        guard originalName != uniqueName else {
            statusMessage = "Bin name unchanged"
            return
        }

        recordUndoSnapshot()
        var updatedProject = project
        updatedProject.bins[binIndex].name = uniqueName
        project = updatedProject
        statusMessage = "Renamed bin to \(uniqueName)"
    }

    public func deleteBin(binID: UUID) {
        guard let binIndex = project.bins.firstIndex(where: { $0.id == binID }) else {
            statusMessage = "Bin not found"
            return
        }

        recordUndoSnapshot()
        var updatedProject = project
        let removedName = updatedProject.bins[binIndex].name
        updatedProject.bins.remove(at: binIndex)
        if updatedProject.bins.isEmpty {
            updatedProject.bins = [MediaBin(name: "Imported")]
        }
        project = updatedProject
        statusMessage = "Deleted bin \(removedName)"
    }

    public func addAsset(_ assetID: UUID, toBin binID: UUID) {
        guard project.assets.contains(where: { $0.id == assetID }) else {
            statusMessage = "Asset not found"
            return
        }
        guard let binIndex = project.bins.firstIndex(where: { $0.id == binID }) else {
            statusMessage = "Bin not found"
            return
        }
        guard !project.bins[binIndex].assetIDs.contains(assetID) else {
            statusMessage = "Asset already in \(project.bins[binIndex].name)"
            return
        }

        recordUndoSnapshot()
        var updatedProject = project
        updatedProject.bins[binIndex].assetIDs.append(assetID)
        let binName = updatedProject.bins[binIndex].name
        project = updatedProject
        statusMessage = "Added asset to \(binName)"
    }

    public func removeAsset(_ assetID: UUID, fromBin binID: UUID) {
        guard let binIndex = project.bins.firstIndex(where: { $0.id == binID }) else {
            statusMessage = "Bin not found"
            return
        }
        guard let assetIndex = project.bins[binIndex].assetIDs.firstIndex(of: assetID) else {
            statusMessage = "Asset is not in \(project.bins[binIndex].name)"
            return
        }

        recordUndoSnapshot()
        var updatedProject = project
        updatedProject.bins[binIndex].assetIDs.remove(at: assetIndex)
        let binName = updatedProject.bins[binIndex].name
        project = updatedProject
        statusMessage = "Removed asset from \(binName)"
    }

    public func moveAsset(_ assetID: UUID, inBin binID: UUID, before targetID: UUID? = nil) {
        guard project.assets.contains(where: { $0.id == assetID }) else {
            statusMessage = "Asset not found"
            return
        }
        guard let binIndex = project.bins.firstIndex(where: { $0.id == binID }) else {
            statusMessage = "Bin not found"
            return
        }

        var ids = project.bins[binIndex].assetIDs
        guard let fromIndex = ids.firstIndex(of: assetID) else {
            recordUndoSnapshot()
            var updatedProject = project
            if let targetID, let targetIndex = ids.firstIndex(of: targetID) {
                ids.insert(assetID, at: targetIndex)
            } else {
                ids.append(assetID)
            }
            updatedProject.bins[binIndex].assetIDs = ids
            project = updatedProject
            statusMessage = "Added asset to \(project.bins[binIndex].name)"
            return
        }

        if let targetID, targetID == assetID {
            statusMessage = "Asset already positioned"
            return
        }

        recordUndoSnapshot()
        ids.remove(at: fromIndex)

        let insertIndex: Int
        if let targetID, let targetIndex = ids.firstIndex(of: targetID) {
            insertIndex = targetIndex
        } else {
            insertIndex = ids.count
        }

        ids.insert(assetID, at: insertIndex)
        var updatedProject = project
        updatedProject.bins[binIndex].assetIDs = ids
        project = updatedProject
        statusMessage = "Reordered assets in \(project.bins[binIndex].name)"
    }

    public func selectClip(_ clipID: UUID?) {
        if let clipID {
            selectedClipID = clipID
            selectedClipIDs = [clipID]
        } else {
            selectedClipID = nil
            selectedClipIDs = []
        }
    }

    public func selectClips(_ clipIDs: [UUID], primary: UUID? = nil) {
        let unique = Array(Set(clipIDs))
        guard !unique.isEmpty else {
            selectedClipID = nil
            selectedClipIDs = []
            return
        }
        selectedClipIDs = Set(unique)
        if let primary, selectedClipIDs.contains(primary) {
            selectedClipID = primary
        } else {
            selectedClipID = unique.first
        }
    }

    public func clearClipSelection() {
        selectedClipID = nil
        selectedClipIDs = []
    }

    private func resolvedSelectedClipIDs() -> Set<UUID> {
        if !selectedClipIDs.isEmpty {
            return selectedClipIDs
        }
        if let selectedClipID {
            return [selectedClipID]
        }
        return []
    }

    public func selectAsset(_ assetID: UUID?) {
        if selectedAssetID == assetID {
            return
        }
        selectedAssetID = assetID
        sourcePlayheadTime = 0
        sourceInPoint = nil
        sourceOutPoint = nil
    }

    public func appendSelectedAssetToTimeline() {
        guard let selectedAssetID else {
            statusMessage = "Select an asset in the browser first"
            return
        }
        appendAssetToTimeline(assetID: selectedAssetID)
    }

    public func setTimelineEditMode(_ mode: TimelineEditMode) {
        timelineEditMode = mode
        statusMessage = "\(mode.rawValue.capitalized) edit mode"
    }

    public func toggleTimelineEditMode() {
        setTimelineEditMode(timelineEditMode == .insert ? .overwrite : .insert)
    }

    public func setTargetedTrack(_ trackID: UUID, kind: TrackKind) {
        switch kind {
        case .video:
            guard activeSequence?.videoTracks.contains(where: { $0.id == trackID }) == true else { return }
            targetedVideoTrackID = trackID
            statusMessage = "Targeted video track"
        case .audio:
            guard activeSequence?.audioTracks.contains(where: { $0.id == trackID }) == true else { return }
            targetedAudioTrackID = trackID
            statusMessage = "Targeted audio track"
        }
    }

    public func toggleTrackMute(trackID: UUID, kind: TrackKind) {
        guard let sequenceID = activeSequenceID ?? project.sequences.first?.id,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequenceID }) else {
            return
        }
        recordUndoSnapshot()
        var updatedProject = project
        switch kind {
        case .video:
            guard let trackIndex = updatedProject.sequences[sequenceIndex].videoTracks.firstIndex(where: { $0.id == trackID }) else { return }
            updatedProject.sequences[sequenceIndex].videoTracks[trackIndex].isMuted.toggle()
        case .audio:
            guard let trackIndex = updatedProject.sequences[sequenceIndex].audioTracks.firstIndex(where: { $0.id == trackID }) else { return }
            updatedProject.sequences[sequenceIndex].audioTracks[trackIndex].isMuted.toggle()
        }
        project = updatedProject
        statusMessage = "Track mute updated"
    }

    public func toggleTrackSolo(trackID: UUID, kind: TrackKind) {
        guard let sequenceID = activeSequenceID ?? project.sequences.first?.id,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequenceID }) else {
            return
        }
        recordUndoSnapshot()
        var updatedProject = project
        switch kind {
        case .video:
            guard let trackIndex = updatedProject.sequences[sequenceIndex].videoTracks.firstIndex(where: { $0.id == trackID }) else { return }
            updatedProject.sequences[sequenceIndex].videoTracks[trackIndex].isSolo.toggle()
        case .audio:
            guard let trackIndex = updatedProject.sequences[sequenceIndex].audioTracks.firstIndex(where: { $0.id == trackID }) else { return }
            updatedProject.sequences[sequenceIndex].audioTracks[trackIndex].isSolo.toggle()
        }
        project = updatedProject
        statusMessage = "Track solo updated"
    }

    public func toggleTrackLock(trackID: UUID) {
        if lockedTrackIDs.contains(trackID) {
            lockedTrackIDs.remove(trackID)
            statusMessage = "Track unlocked"
        } else {
            lockedTrackIDs.insert(trackID)
            statusMessage = "Track locked"
        }
    }

    public func isTrackLocked(_ trackID: UUID) -> Bool {
        lockedTrackIDs.contains(trackID)
    }

    public func addTrack(kind: TrackKind) {
        guard let sequenceID = activeSequenceID ?? project.sequences.first?.id,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequenceID }) else {
            return
        }
        recordUndoSnapshot()
        var updatedProject = project

        switch kind {
        case .video:
            let name = "V\(updatedProject.sequences[sequenceIndex].videoTracks.count + 1)"
            let track = TimelineTrack(name: name, kind: .video)
            updatedProject.sequences[sequenceIndex].videoTracks.append(track)
            targetedVideoTrackID = track.id
            statusMessage = "Added video track \(name)"
        case .audio:
            let name = "A\(updatedProject.sequences[sequenceIndex].audioTracks.count + 1)"
            let track = TimelineTrack(name: name, kind: .audio)
            updatedProject.sequences[sequenceIndex].audioTracks.append(track)
            targetedAudioTrackID = track.id
            statusMessage = "Added audio track \(name)"
        }

        project = updatedProject
    }

    public func removeTrack(trackID: UUID, kind: TrackKind) {
        guard let sequenceID = activeSequenceID ?? project.sequences.first?.id,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequenceID }) else {
            return
        }
        var updatedProject = project

        switch kind {
        case .video:
            guard updatedProject.sequences[sequenceIndex].videoTracks.count > 1 else {
                statusMessage = "Cannot remove the last video track"
                return
            }
            guard let trackIndex = updatedProject.sequences[sequenceIndex].videoTracks.firstIndex(where: { $0.id == trackID }) else {
                return
            }
            recordUndoSnapshot()
            let removedTrack = updatedProject.sequences[sequenceIndex].videoTracks.remove(at: trackIndex)
            if targetedVideoTrackID == removedTrack.id {
                targetedVideoTrackID = updatedProject.sequences[sequenceIndex].videoTracks.first?.id
            }
            let removedIDs = Set(removedTrack.clips.map(\.id))
            if !selectedClipIDs.isDisjoint(with: removedIDs) {
                selectedClipIDs.subtract(removedIDs)
                syncPrimarySelection()
            }
            lockedTrackIDs.remove(removedTrack.id)
            statusMessage = "Removed video track \(removedTrack.name)"
        case .audio:
            guard updatedProject.sequences[sequenceIndex].audioTracks.count > 1 else {
                statusMessage = "Cannot remove the last audio track"
                return
            }
            guard let trackIndex = updatedProject.sequences[sequenceIndex].audioTracks.firstIndex(where: { $0.id == trackID }) else {
                return
            }
            recordUndoSnapshot()
            let removedTrack = updatedProject.sequences[sequenceIndex].audioTracks.remove(at: trackIndex)
            if targetedAudioTrackID == removedTrack.id {
                targetedAudioTrackID = updatedProject.sequences[sequenceIndex].audioTracks.first?.id
            }
            let removedIDs = Set(removedTrack.clips.map(\.id))
            if !selectedClipIDs.isDisjoint(with: removedIDs) {
                selectedClipIDs.subtract(removedIDs)
                syncPrimarySelection()
            }
            lockedTrackIDs.remove(removedTrack.id)
            statusMessage = "Removed audio track \(removedTrack.name)"
        }

        updatedProject.sequences[sequenceIndex].duration = TimelineDurationCalculator.duration(of: updatedProject.sequences[sequenceIndex])
        project = updatedProject
        sanitizeSelectedClip()
    }

    public func moveTrack(trackID: UUID, kind: TrackKind, direction: Int) {
        guard direction != 0 else { return }
        guard let sequenceID = activeSequenceID ?? project.sequences.first?.id,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequenceID }) else {
            return
        }
        var updatedProject = project

        switch kind {
        case .video:
            guard let trackIndex = updatedProject.sequences[sequenceIndex].videoTracks.firstIndex(where: { $0.id == trackID }) else {
                return
            }
            let destination = trackIndex + direction
            guard updatedProject.sequences[sequenceIndex].videoTracks.indices.contains(destination) else { return }
            recordUndoSnapshot()
            updatedProject.sequences[sequenceIndex].videoTracks.swapAt(trackIndex, destination)
            statusMessage = direction < 0 ? "Moved video track up" : "Moved video track down"
        case .audio:
            guard let trackIndex = updatedProject.sequences[sequenceIndex].audioTracks.firstIndex(where: { $0.id == trackID }) else {
                return
            }
            let destination = trackIndex + direction
            guard updatedProject.sequences[sequenceIndex].audioTracks.indices.contains(destination) else { return }
            recordUndoSnapshot()
            updatedProject.sequences[sequenceIndex].audioTracks.swapAt(trackIndex, destination)
            statusMessage = direction < 0 ? "Moved audio track up" : "Moved audio track down"
        }

        project = updatedProject
    }

    public func programClip(at timelineTime: TimeInterval) -> ClipRef? {
        guard let sequence = activeSequence else { return nil }
        if let video = playbackClipAtTime(in: sequence.videoTracks, timelineTime: timelineTime, preferHigherTrack: true) {
            return video
        }
        return playbackClipAtTime(in: sequence.audioTracks, timelineTime: timelineTime, preferHigherTrack: false)
    }

    public func setActiveSequence(_ sequenceID: UUID) {
        guard project.sequences.contains(where: { $0.id == sequenceID }) else { return }
        stopPlaybackLoop()
        activeSequenceID = sequenceID
        clearClipSelection()
        selectedCaptionSegmentID = nil
        inPoint = nil
        outPoint = nil
        isLoopPlaybackEnabled = false
        timelineEditMode = .insert
        lockedTrackIDs = []
        targetedVideoTrackID = activeSequence?.videoTracks.first?.id
        targetedAudioTrackID = activeSequence?.audioTracks.first?.id
        sourcePlayheadTime = 0
        sourceInPoint = nil
        sourceOutPoint = nil
        playheadTime = 0
        refreshTranscriptMatches()
        silenceSuggestions = []
        statusMessage = "Switched sequence"
    }

    public func undo() {
        guard let previous = undoHistory.popLast() else {
            statusMessage = "Nothing to undo"
            return
        }

        stopPlaybackLoop()
        redoHistory.append(project)
        project = previous
        if let activeSequenceID,
           !project.sequences.contains(where: { $0.id == activeSequenceID }) {
            self.activeSequenceID = project.sequences.first?.id
        }
        sanitizeSelectedClip()
        refreshTranscriptMatches()
        statusMessage = "Undo"
    }

    public func redo() {
        guard let next = redoHistory.popLast() else {
            statusMessage = "Nothing to redo"
            return
        }

        stopPlaybackLoop()
        undoHistory.append(project)
        project = next
        if let activeSequenceID,
           !project.sequences.contains(where: { $0.id == activeSequenceID }) {
            self.activeSequenceID = project.sequences.first?.id
        }
        sanitizeSelectedClip()
        refreshTranscriptMatches()
        statusMessage = "Redo"
    }

    public func createSequence(named name: String? = nil) {
        stopPlaybackLoop()
        recordUndoSnapshot()
        var updatedProject = project
        let defaultName = "Sequence \(updatedProject.sequences.count + 1)"
        let sequenceName = name?.isEmpty == false ? name! : defaultName

        let newSequence = EditorSequence(
            name: sequenceName,
            mode: .track,
            duration: 0,
            videoTracks: [TimelineTrack(name: "V1", kind: .video)],
            audioTracks: [TimelineTrack(name: "A1", kind: .audio)]
        )

        updatedProject.sequences.append(newSequence)
        project = updatedProject
        activeSequenceID = newSequence.id
        clearClipSelection()
        selectedCaptionSegmentID = nil
        inPoint = nil
        outPoint = nil
        isLoopPlaybackEnabled = false
        timelineEditMode = .insert
        lockedTrackIDs = []
        targetedVideoTrackID = newSequence.videoTracks.first?.id
        targetedAudioTrackID = newSequence.audioTracks.first?.id
        sourcePlayheadTime = 0
        sourceInPoint = nil
        sourceOutPoint = nil
        playheadTime = 0
        refreshTranscriptMatches()
        silenceSuggestions = []
        statusMessage = "Created \(sequenceName)"
    }

    public func duplicateActiveSequence() {
        guard let sequence = activeSequence else { return }
        stopPlaybackLoop()
        recordUndoSnapshot()
        var duplicated = sequence
        duplicated.id = UUID()
        duplicated.name = "\(sequence.name) Copy"
        duplicated.markers = []

        for trackIndex in duplicated.videoTracks.indices {
            for clipIndex in duplicated.videoTracks[trackIndex].clips.indices {
                duplicated.videoTracks[trackIndex].clips[clipIndex].id = UUID()
            }
        }

        for trackIndex in duplicated.audioTracks.indices {
            for clipIndex in duplicated.audioTracks[trackIndex].clips.indices {
                duplicated.audioTracks[trackIndex].clips[clipIndex].id = UUID()
            }
        }

        var updatedProject = project
        updatedProject.sequences.append(duplicated)
        project = updatedProject
        activeSequenceID = duplicated.id
        clearClipSelection()
        selectedCaptionSegmentID = nil
        inPoint = nil
        outPoint = nil
        isLoopPlaybackEnabled = false
        timelineEditMode = .insert
        lockedTrackIDs = []
        targetedVideoTrackID = duplicated.videoTracks.first?.id
        targetedAudioTrackID = duplicated.audioTracks.first?.id
        sourcePlayheadTime = 0
        sourceInPoint = nil
        sourceOutPoint = nil
        playheadTime = 0
        refreshTranscriptMatches()
        silenceSuggestions = []
        statusMessage = "Duplicated sequence"
    }

    public func addMarkerAtPlayhead(label: String = "Marker") {
        guard let activeSequenceID,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == activeSequenceID }) else { return }
        recordUndoSnapshot()
        var updatedProject = project
        let marker = TimelineMarker(time: playheadTime, label: label)
        updatedProject.sequences[sequenceIndex].markers.append(marker)
        updatedProject.sequences[sequenceIndex].markers.sort { $0.time < $1.time }
        project = updatedProject
        statusMessage = "Marker added at \(timecode(playheadTime))"
    }

    public func jumpToNextMarker() {
        guard let sequence = activeSequence else { return }
        let markers = sequence.markers.sorted { $0.time < $1.time }
        guard let marker = markers.first(where: { $0.time > playheadTime + 0.001 }) else {
            statusMessage = "No next marker"
            return
        }
        updatePlayhead(to: marker.time)
        statusMessage = "Jumped to marker: \(marker.label)"
    }

    public func nudgeSelectedClip(by seconds: TimeInterval) {
        guard let sequence = activeSequence, let selection = clipSelection else {
            statusMessage = "Select a clip first"
            return
        }
        let moveTargets = linkedEditTargets(
            for: (clip: selection.clip, trackID: selection.trackID, kind: selection.kind),
            in: sequence
        )
        guard !hasLockedTrack(in: moveTargets) else {
            statusMessage = "Track is locked"
            return
        }
        recordUndoSnapshot()
        var workingProject = project

        do {
            for target in moveTargets {
                guard let sourceTimelineIn = timelineInOfClip(target.clipID, in: sequence) else {
                    continue
                }
                let targetTime = max(0, sourceTimelineIn + seconds)
                let result = try timelineEngine.apply(
                    operation: .moveClip(
                        sequenceID: sequence.id,
                        trackID: target.trackID,
                        trackKind: target.kind,
                        clipID: target.clipID,
                        newTimelineIn: targetTime
                    ),
                    to: workingProject
                )
                workingProject = result.0
            }
            project = workingProject
            let selectedTargetTime = max(0, selection.clip.timelineIn + seconds)
            statusMessage = moveTargets.count > 1 ?
                "Moved linked clips to \(timecode(selectedTargetTime))" :
                "Moved clip to \(timecode(selectedTargetTime))"
        } catch {
            statusMessage = "Move failed: \(error.localizedDescription)"
        }
    }

    public func slipSelectedClip(by seconds: TimeInterval) {
        guard let sequence = activeSequence, let selection = clipSelection else {
            statusMessage = "Select a clip first"
            return
        }
        let slipTargets = linkedEditTargets(
            for: (clip: selection.clip, trackID: selection.trackID, kind: selection.kind),
            in: sequence
        )
        guard !hasLockedTrack(in: slipTargets) else {
            statusMessage = "Track is locked"
            return
        }
        recordUndoSnapshot()
        var workingProject = project

        do {
            for target in slipTargets {
                let result = try timelineEngine.apply(
                    operation: .slipClip(
                        sequenceID: sequence.id,
                        trackID: target.trackID,
                        trackKind: target.kind,
                        clipID: target.clipID,
                        deltaSource: seconds
                    ),
                    to: workingProject
                )
                workingProject = result.0
            }
            project = workingProject
            let deltaText = String(format: "%+.1fs", seconds)
            statusMessage = slipTargets.count > 1 ?
                "Slipped linked clips by \(deltaText)" :
                "Slipped clip by \(deltaText)"
        } catch {
            statusMessage = "Slip failed: \(error.localizedDescription)"
        }
    }

    public func trimSelectedClipLeading(by delta: TimeInterval) {
        guard let sequence = activeSequence, let selection = clipSelection else {
            statusMessage = "Select a clip first"
            return
        }
        guard !isTrackLocked(selection.trackID) else {
            statusMessage = "Track is locked"
            return
        }
        recordUndoSnapshot()

        let maxStart = selection.clip.outTime - 0.2
        let newIn = min(maxStart, max(0, selection.clip.inTime + delta))

        do {
            let result = try timelineEngine.apply(
                operation: .trimClip(
                    sequenceID: sequence.id,
                    trackID: selection.trackID,
                    trackKind: selection.kind,
                    clipID: selection.clip.id,
                    newIn: newIn,
                    newOut: selection.clip.outTime
                ),
                to: project
            )
            project = result.0
            statusMessage = "Trimmed clip start"
        } catch {
            statusMessage = "Trim failed: \(error.localizedDescription)"
        }
    }

    public func trimSelectedClipTrailing(by delta: TimeInterval) {
        guard let sequence = activeSequence, let selection = clipSelection else {
            statusMessage = "Select a clip first"
            return
        }
        guard !isTrackLocked(selection.trackID) else {
            statusMessage = "Track is locked"
            return
        }
        recordUndoSnapshot()

        let minEnd = selection.clip.inTime + 0.2
        let newOut = max(minEnd, selection.clip.outTime + delta)

        do {
            let result = try timelineEngine.apply(
                operation: .trimClip(
                    sequenceID: sequence.id,
                    trackID: selection.trackID,
                    trackKind: selection.kind,
                    clipID: selection.clip.id,
                    newIn: selection.clip.inTime,
                    newOut: newOut
                ),
                to: project
            )
            project = result.0
            statusMessage = "Trimmed clip end"
        } catch {
            statusMessage = "Trim failed: \(error.localizedDescription)"
        }
    }

    public func rippleDeleteSelectedClip() {
        let selectedIDs = resolvedSelectedClipIDs()
        if selectedIDs.count > 1 {
            rippleDeleteSelectedClips()
            return
        }
        guard clipSelection != nil else {
            statusMessage = "Select a clip first"
            return
        }
        rippleDeleteSelectedOrFirstClip()
    }

    public func rippleDeleteSelectedClips() {
        guard let sequence = activeSequence else {
            statusMessage = "No active sequence"
            return
        }

        let selectedIDs = resolvedSelectedClipIDs()
        guard !selectedIDs.isEmpty else {
            statusMessage = "Select clips first"
            return
        }

        let targets = clipTargets(for: selectedIDs, in: sequence)
        guard !targets.isEmpty else {
            statusMessage = "Select clips first"
            return
        }

        let unlocked = targets.filter { !isTrackLocked($0.trackID) }
        guard !unlocked.isEmpty else {
            statusMessage = "Track is locked"
            return
        }

        recordUndoSnapshot()
        var workingProject = project
        var deleteCount = 0

        for target in unlocked.sorted(by: { $0.clip.timelineIn > $1.clip.timelineIn }) {
            do {
                let result = try timelineEngine.apply(
                    operation: .rippleDelete(
                        sequenceID: sequence.id,
                        trackID: target.trackID,
                        trackKind: target.kind,
                        clipID: target.clip.id
                    ),
                    to: workingProject
                )
                workingProject = result.0
                deleteCount += 1
            } catch {
                continue
            }
        }

        guard deleteCount > 0 else {
            statusMessage = "No clips deleted"
            return
        }

        project = workingProject
        let deletedIDs = Set(unlocked.map(\.clip.id))
        selectedClipIDs.subtract(deletedIDs)
        syncPrimarySelection()
        sanitizeSelectedClip()
        statusMessage = deleteCount > 1 ? "Ripple deleted \(deleteCount) clips" : "Ripple deleted clip"
    }

    public func nudgeSelectedClips(by seconds: TimeInterval) {
        guard let sequence = activeSequence else {
            statusMessage = "No active sequence"
            return
        }

        let selectedIDs = resolvedSelectedClipIDs()
        guard !selectedIDs.isEmpty else {
            statusMessage = "Select clips to nudge"
            return
        }

        let targets = clipTargets(for: selectedIDs, in: sequence)
        guard !targets.isEmpty else {
            statusMessage = "Select clips to nudge"
            return
        }

        recordUndoSnapshot()
        var workingProject = project
        var moveCount = 0

        for target in targets {
            guard !isTrackLocked(target.trackID) else {
                continue
            }
            let newTime = max(0, target.clip.timelineIn + seconds)
            if abs(newTime - target.clip.timelineIn) < 0.0001 {
                continue
            }
            do {
                let result = try timelineEngine.apply(
                    operation: .moveClip(
                        sequenceID: sequence.id,
                        trackID: target.trackID,
                        trackKind: target.kind,
                        clipID: target.clip.id,
                        newTimelineIn: newTime
                    ),
                    to: workingProject
                )
                workingProject = result.0
                moveCount += 1
            } catch {
                continue
            }
        }

        guard moveCount > 0 else {
            statusMessage = "No clips moved"
            return
        }

        project = workingProject
        statusMessage = moveCount > 1 ? "Nudged \(moveCount) clips" : "Nudged clip"
    }

    public func updateSelectedClipPositionX(_ value: Double) {
        updateSelectedClip { clip in
            clip.transforms.positionX = value
        }
    }

    public func updateSelectedClipPositionY(_ value: Double) {
        updateSelectedClip { clip in
            clip.transforms.positionY = value
        }
    }

    public func updateSelectedClipScale(_ value: Double) {
        let safeScale = max(0.1, value)
        updateSelectedClip { clip in
            clip.transforms.scaleX = safeScale
            clip.transforms.scaleY = safeScale
        }
    }

    public func updateSelectedClipOpacity(_ value: Double) {
        let safeOpacity = min(1.0, max(0.0, value))
        updateSelectedClip { clip in
            clip.transforms.opacity = safeOpacity
        }
    }

    public func updateSelectedClipGain(_ value: Double) {
        updateSelectedClip { clip in
            clip.gain = min(2.0, max(0.0, value))
        }
    }

    public func generateProxyManifest() {
        guard let bundleURL = currentProjectBundleURL else {
            statusMessage = "Save project before generating proxies"
            return
        }

        guard !project.assets.isEmpty else {
            statusMessage = "No assets available for proxy manifest"
            return
        }

        do {
            let paths = ProjectPaths(bundleURL: bundleURL)
            let manifestURL = try proxyManager.createProxyManifest(for: project.assets, in: paths.cacheDirectoryURL)
            statusMessage = "Proxy manifest written to \(manifestURL.lastPathComponent)"
        } catch {
            statusMessage = "Proxy manifest failed: \(error.localizedDescription)"
        }
    }

    public func relinkAsset(_ assetID: UUID, to newURL: URL) {
        guard let assetIndex = project.assets.firstIndex(where: { $0.id == assetID }) else {
            statusMessage = "Asset not found"
            return
        }

        let standardizedURL = newURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path()) else {
            statusMessage = "Relink target does not exist"
            return
        }

        let originalPath = project.assets[assetIndex].path
        guard originalPath != standardizedURL.path() else {
            statusMessage = "Asset already points to that file"
            return
        }

        recordUndoSnapshot()
        var updatedProject = project
        updatedProject.assets[assetIndex].path = standardizedURL.path()
        project = updatedProject
        statusMessage = "Relinked \(updatedProject.assets[assetIndex].name)"
    }

    public func relinkSelectedAssetUsingDialog() {
        guard let selectedAssetID,
              let asset = project.assets.first(where: { $0.id == selectedAssetID }) else {
            statusMessage = "Select an asset in the browser first"
            return
        }
        presentRelinkDialog(for: asset)
    }

    public func relinkFirstMissingAssetUsingDialog() {
        guard let asset = missingAssets.first else {
            statusMessage = "No missing media to relink"
            return
        }
        presentRelinkDialog(for: asset)
    }

    private func presentRelinkDialog(for asset: MediaAsset) {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose replacement media for \(asset.name)"
        #if canImport(UniformTypeIdentifiers)
        switch asset.type {
        case .video:
            panel.allowedContentTypes = [.movie]
        case .audio:
            panel.allowedContentTypes = [.audio]
        case .image:
            panel.allowedContentTypes = [.image]
        case .unknown:
            break
        }
        #endif

        if panel.runModal() == .OK, let url = panel.url {
            relinkAsset(asset.id, to: url)
        }
        #else
        statusMessage = "Relink is only available on macOS"
        #endif
    }

    public func toggleShortcutHelp() {
        showsShortcutHelp.toggle()
    }

    public func togglePlayback() {
        if isPlaying {
            pausePlayback(userInitiated: true)
        } else {
            startPlayback()
        }
    }

    public func startPlayback() {
        guard let sequence = activeSequence else {
            statusMessage = "No active sequence"
            return
        }

        guard sequence.duration > 0 else {
            statusMessage = "Timeline is empty"
            return
        }

        let range = normalizedPlaybackRange
        let playbackStart: TimeInterval
        if isLoopPlaybackEnabled, let range {
            playbackStart = (playheadTime < range.start || playheadTime >= range.end) ? range.start : playheadTime
        } else {
            playbackStart = playheadTime >= sequence.duration ? 0 : playheadTime
        }

        playheadTime = playbackStart

        _ = playbackEngine.play(
            sequenceID: sequence.id,
            startTime: playbackStart,
            qualityMode: playbackQualityMode()
        )
        isPlaying = true
        statusMessage = "Playing"
        startPlaybackLoop()
    }

    public func pausePlayback(userInitiated: Bool = false) {
        guard isPlaying else { return }
        stopPlaybackLoop()
        if userInitiated {
            statusMessage = "Paused at \(timecode(playheadTime))"
        }
    }

    public func jumpToStart() {
        stopPlaybackLoop()
        updatePlayhead(to: 0)
        statusMessage = "Playhead at start"
    }

    public func jumpToEnd() {
        stopPlaybackLoop()
        updatePlayhead(to: activeSequence?.duration ?? 0)
        statusMessage = "Playhead at end"
    }

    public func setInPointAtPlayhead() {
        let clamped = max(0, playheadTime)
        inPoint = clamped
        if let outPoint, outPoint <= clamped {
            self.outPoint = min(max(0, activeSequence?.duration ?? outPoint), clamped + (1.0 / max(1, project.fps)))
        }
        statusMessage = "Set In at \(timecode(clamped))"
    }

    public func setOutPointAtPlayhead() {
        let sequenceDuration = max(0, activeSequence?.duration ?? playheadTime)
        let clamped = min(sequenceDuration, max(0, playheadTime))
        outPoint = clamped
        if let inPoint, inPoint >= clamped {
            self.inPoint = max(0, clamped - (1.0 / max(1, project.fps)))
        }
        statusMessage = "Set Out at \(timecode(clamped))"
    }

    public func clearInOutPoints() {
        inPoint = nil
        outPoint = nil
        isLoopPlaybackEnabled = false
        statusMessage = "Cleared In/Out range"
    }

    public func toggleLoopPlayback() {
        if normalizedPlaybackRange == nil {
            statusMessage = "Set both In and Out points first"
            return
        }
        isLoopPlaybackEnabled.toggle()
        statusMessage = isLoopPlaybackEnabled ? "Loop playback on" : "Loop playback off"
    }

    public func jumpToNextEditPoint() {
        guard let sequence = activeSequence else { return }
        let points = editPoints(in: sequence)
        guard let next = points.first(where: { $0 > playheadTime + 0.001 }) else {
            statusMessage = "No next edit point"
            return
        }
        updatePlayhead(to: next)
        statusMessage = "Jumped to next edit"
    }

    public func jumpToPreviousEditPoint() {
        guard let sequence = activeSequence else { return }
        let points = editPoints(in: sequence)
        guard let previous = points.reversed().first(where: { $0 < playheadTime - 0.001 }) else {
            statusMessage = "No previous edit point"
            return
        }
        updatePlayhead(to: previous)
        statusMessage = "Jumped to previous edit"
    }

    public func stepFrame(_ deltaFrames: Int) {
        guard deltaFrames != 0 else { return }
        stopPlaybackLoop()
        let frameDuration = 1.0 / max(1, project.fps)
        updatePlayhead(to: playheadTime + (Double(deltaFrames) * frameDuration))
        statusMessage = deltaFrames > 0 ? "Stepped forward" : "Stepped backward"
    }

    public func shuttleBackward() {
        pausePlayback(userInitiated: false)
        seekBy(-1)
        statusMessage = "Shuttled backward"
    }

    public func shuttleStop() {
        pausePlayback(userInitiated: true)
    }

    public func shuttleForward() {
        if isPlaying {
            playbackRate = playbackRate >= 1.9 ? 1.0 : 2.0
            statusMessage = "Playback speed \(String(format: "%.1fx", playbackRate))"
            return
        }
        playbackRate = max(1.0, playbackRate)
        startPlayback()
    }

    public func seekBy(_ seconds: TimeInterval) {
        updatePlayhead(to: playheadTime + seconds)
    }

    public func updatePlayheadFromPlayback(_ newTime: TimeInterval) {
        // Real playback updates should not stop the user playback session.
        playheadTime = min(max(0, newTime), activeSequence?.duration ?? newTime)
    }

    public func updateSourcePlayhead(to newTime: TimeInterval) {
        let maxTime = sourceDuration(for: selectedSourceAsset)
        sourcePlayheadTime = min(maxTime, max(0, newTime))
    }

    public func setSourceInPointAtPlayhead() {
        let clamped = min(sourceDuration(for: selectedSourceAsset), max(0, sourcePlayheadTime))
        sourceInPoint = clamped
        if let sourceOutPoint, sourceOutPoint <= clamped {
            self.sourceOutPoint = min(sourceDuration(for: selectedSourceAsset), clamped + (1.0 / max(1, project.fps)))
        }
        statusMessage = "Set source In at \(timecode(clamped))"
    }

    public func setSourceOutPointAtPlayhead() {
        let sourceDuration = sourceDuration(for: selectedSourceAsset)
        let clamped = min(sourceDuration, max(0, sourcePlayheadTime))
        sourceOutPoint = clamped
        if let sourceInPoint, sourceInPoint >= clamped {
            self.sourceInPoint = max(0, clamped - (1.0 / max(1, project.fps)))
        }
        statusMessage = "Set source Out at \(timecode(clamped))"
    }

    public func clearSourceInOutPoints() {
        sourceInPoint = nil
        sourceOutPoint = nil
        statusMessage = "Cleared source In/Out"
    }

    public func updatePreviewVolume(_ value: Double) {
        previewVolume = min(1.0, max(0, value))
        if previewVolume > 0.001 {
            isPreviewMuted = false
        }
    }

    public func togglePreviewMute() {
        isPreviewMuted.toggle()
    }

    public func cyclePlaybackRate() {
        let rates: [Double] = [0.5, 1.0, 1.5, 2.0]
        if let currentIndex = rates.firstIndex(where: { abs($0 - playbackRate) < 0.001 }) {
            playbackRate = rates[(currentIndex + 1) % rates.count]
        } else {
            playbackRate = 1.0
        }
        statusMessage = "Playback speed \(String(format: "%.1fx", playbackRate))"
    }

    public func resetSelectedClipAdjustments() {
        guard selectedClip != nil else {
            statusMessage = "Select a clip first"
            return
        }
        recordUndoSnapshot()
        mutateSelectedClip(recordSnapshot: false) { clip in
            clip.transforms = ClipTransform()
            clip.gain = 1.0
            clip.effects = []
        }
        statusMessage = "Reset selected clip adjustments"
    }

    public func updatePlayhead(to newTime: TimeInterval) {
        let maxTime = max(0, activeSequence?.duration ?? newTime)
        playheadTime = min(maxTime, max(0, newTime))
        if playbackEngine.currentSession() != nil {
            _ = playbackEngine.seek(to: playheadTime)
        }
    }

    public func performAutosave() {
        guard let currentProjectBundleURL else {
            return
        }

        do {
            lastAutosaveURL = try projectStore.autosave(project: project, to: currentProjectBundleURL)
        } catch {
            statusMessage = "Autosave failed: \(error.localizedDescription)"
        }
    }

    public func openProjectUsingDialog() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project bundle folder"

        if panel.runModal() == .OK, let url = panel.url {
            openProject(at: url)
        }
        #endif
    }

    public func saveProjectAsUsingDialog() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(project.name).pcloneproj"
        panel.message = "Choose where to save the project bundle"

        if panel.runModal() == .OK, var url = panel.url {
            if url.pathExtension.isEmpty {
                url.appendPathExtension("pcloneproj")
            }
            saveProjectAs(to: url)
        }
        #endif
    }

    public func importMediaUsingDialog() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        #if canImport(UniformTypeIdentifiers)
        panel.allowedContentTypes = [.movie, .audio, .image]
        #endif

        if panel.runModal() == .OK {
            importMedia(urls: panel.urls)
        }
        #endif
    }

    private func ensurePrimaryTracks(in project: inout Project, sequenceIndex: Int) -> (videoTrackID: UUID, audioTrackID: UUID) {
        if project.sequences[sequenceIndex].videoTracks.isEmpty {
            project.sequences[sequenceIndex].videoTracks.append(TimelineTrack(name: "V1", kind: .video))
        }
        if project.sequences[sequenceIndex].audioTracks.isEmpty {
            project.sequences[sequenceIndex].audioTracks.append(TimelineTrack(name: "A1", kind: .audio))
        }

        let videoTrackID: UUID
        if let targetedVideoTrackID,
           project.sequences[sequenceIndex].videoTracks.contains(where: { $0.id == targetedVideoTrackID }) {
            videoTrackID = targetedVideoTrackID
        } else {
            videoTrackID = project.sequences[sequenceIndex].videoTracks[0].id
            self.targetedVideoTrackID = videoTrackID
        }

        let audioTrackID: UUID
        if let targetedAudioTrackID,
           project.sequences[sequenceIndex].audioTracks.contains(where: { $0.id == targetedAudioTrackID }) {
            audioTrackID = targetedAudioTrackID
        } else {
            audioTrackID = project.sequences[sequenceIndex].audioTracks[0].id
            self.targetedAudioTrackID = audioTrackID
        }

        return (
            videoTrackID,
            audioTrackID
        )
    }

    private func applyOverwrite(
        in sequence: inout EditorSequence,
        trackID: UUID,
        kind: TrackKind,
        start: TimeInterval,
        end: TimeInterval
    ) {
        guard end > start else { return }

        switch kind {
        case .video:
            guard let trackIndex = sequence.videoTracks.firstIndex(where: { $0.id == trackID }) else { return }
            sequence.videoTracks[trackIndex].clips = overwrittenClips(
                sequence.videoTracks[trackIndex].clips,
                start: start,
                end: end
            )
        case .audio:
            guard let trackIndex = sequence.audioTracks.firstIndex(where: { $0.id == trackID }) else { return }
            sequence.audioTracks[trackIndex].clips = overwrittenClips(
                sequence.audioTracks[trackIndex].clips,
                start: start,
                end: end
            )
        }
    }

    private func overwrittenClips(
        _ clips: [ClipRef],
        start: TimeInterval,
        end: TimeInterval
    ) -> [ClipRef] {
        let epsilon = 1.0 / max(1, project.fps)
        var output: [ClipRef] = []

        for clip in clips.sorted(by: { $0.timelineIn < $1.timelineIn }) {
            let clipStart = clip.timelineIn
            let clipEnd = clip.timelineIn + clip.duration

            if clipEnd <= start || clipStart >= end {
                output.append(clip)
                continue
            }

            if clipStart < start && clipEnd > end {
                var left = clip
                left.outTime = left.inTime + (start - clipStart)
                if left.duration > epsilon {
                    output.append(left)
                }

                var right = clip
                right.id = UUID()
                right.inTime = clip.inTime + (end - clipStart)
                right.timelineIn = end
                if right.duration > epsilon {
                    output.append(right)
                }
                continue
            }

            if clipStart < start && clipEnd > start {
                var left = clip
                left.outTime = left.inTime + (start - clipStart)
                if left.duration > epsilon {
                    output.append(left)
                }
                continue
            }

            if clipStart < end && clipEnd > end {
                var right = clip
                right.inTime = clip.inTime + (end - clipStart)
                right.timelineIn = end
                if right.duration > epsilon {
                    output.append(right)
                }
                continue
            }
        }

        return output.sorted(by: { $0.timelineIn < $1.timelineIn })
    }

    private func hasLockedTrack(in targets: [ClipEditTarget]) -> Bool {
        targets.contains(where: { isTrackLocked($0.trackID) })
    }

    private func shiftClipsForMagneticInsert(
        in sequence: inout EditorSequence,
        insertionTime: TimeInterval,
        shiftBy: TimeInterval
    ) {
        guard shiftBy > 0 else { return }

        for trackIndex in sequence.videoTracks.indices {
            for clipIndex in sequence.videoTracks[trackIndex].clips.indices {
                if sequence.videoTracks[trackIndex].clips[clipIndex].timelineIn >= insertionTime {
                    sequence.videoTracks[trackIndex].clips[clipIndex].timelineIn += shiftBy
                }
            }
            sequence.videoTracks[trackIndex].clips.sort { $0.timelineIn < $1.timelineIn }
        }

        for trackIndex in sequence.audioTracks.indices {
            for clipIndex in sequence.audioTracks[trackIndex].clips.indices {
                if sequence.audioTracks[trackIndex].clips[clipIndex].timelineIn >= insertionTime {
                    sequence.audioTracks[trackIndex].clips[clipIndex].timelineIn += shiftBy
                }
            }
            sequence.audioTracks[trackIndex].clips.sort { $0.timelineIn < $1.timelineIn }
        }
    }

    private func resolveEditableTarget(in sequence: EditorSequence) -> (clip: ClipRef, trackID: UUID, kind: TrackKind)? {
        if let selection = clipSelection {
            return (clip: selection.clip, trackID: selection.trackID, kind: selection.kind)
        }

        if let firstVideoTrack = sequence.videoTracks.first(where: { !$0.clips.isEmpty }),
           let firstVideoClip = firstVideoTrack.clips.sorted(by: { $0.timelineIn < $1.timelineIn }).first {
            return (firstVideoClip, firstVideoTrack.id, .video)
        }

        if let firstAudioTrack = sequence.audioTracks.first(where: { !$0.clips.isEmpty }),
           let firstAudioClip = firstAudioTrack.clips.sorted(by: { $0.timelineIn < $1.timelineIn }).first {
            return (firstAudioClip, firstAudioTrack.id, .audio)
        }

        return nil
    }

    private func linkedEditTargets(
        for target: (clip: ClipRef, trackID: UUID, kind: TrackKind),
        in sequence: EditorSequence
    ) -> [ClipEditTarget] {
        var orderedTargets: [ClipEditTarget] = [
            ClipEditTarget(clipID: target.clip.id, trackID: target.trackID, kind: target.kind)
        ]
        let linkedIDs = Set(target.clip.linkedAudioIDs)

        if target.kind == .video {
            for track in sequence.audioTracks {
                for clip in track.clips where clip.linkedAudioIDs.contains(target.clip.id) || linkedIDs.contains(clip.id) {
                    orderedTargets.append(
                        ClipEditTarget(clipID: clip.id, trackID: track.id, kind: .audio)
                    )
                }
            }
        } else {
            for track in sequence.videoTracks {
                for clip in track.clips where linkedIDs.contains(clip.id) || clip.linkedAudioIDs.contains(target.clip.id) {
                    orderedTargets.append(
                        ClipEditTarget(clipID: clip.id, trackID: track.id, kind: .video)
                    )
                }
            }
        }

        var seen = Set<ClipEditTarget>()
        return orderedTargets.filter { seen.insert($0).inserted }
    }

    private func timelineInOfClip(_ clipID: UUID, in sequence: EditorSequence) -> TimeInterval? {
        for track in sequence.videoTracks {
            if let clip = track.clips.first(where: { $0.id == clipID }) {
                return clip.timelineIn
            }
        }

        for track in sequence.audioTracks {
            if let clip = track.clips.first(where: { $0.id == clipID }) {
                return clip.timelineIn
            }
        }

        return nil
    }

    private func editPoints(in sequence: EditorSequence) -> [TimeInterval] {
        var points = Set<TimeInterval>()
        for clip in sequence.videoTracks.flatMap(\.clips) {
            points.insert(clip.timelineIn)
            points.insert(clip.timelineIn + clip.duration)
        }
        for clip in sequence.audioTracks.flatMap(\.clips) {
            points.insert(clip.timelineIn)
            points.insert(clip.timelineIn + clip.duration)
        }
        return points.sorted()
    }

    private func playbackEligibleTracks(from tracks: [TimelineTrack]) -> [TimelineTrack] {
        let soloed = tracks.filter { $0.isSolo && !$0.isMuted }
        if !soloed.isEmpty {
            return soloed
        }
        return tracks.filter { !$0.isMuted }
    }

    private func playbackClipAtTime(
        in tracks: [TimelineTrack],
        timelineTime: TimeInterval,
        preferHigherTrack: Bool
    ) -> ClipRef? {
        let eligibleTracks = playbackEligibleTracks(from: tracks)
        let orderedTracks: [TimelineTrack]
        if preferHigherTrack {
            orderedTracks = eligibleTracks.reversed()
        } else {
            orderedTracks = eligibleTracks
        }

        for track in orderedTracks {
            if let clip = track.clips
                .sorted(by: { $0.timelineIn < $1.timelineIn })
                .first(where: { clipContainsTimelineTime($0, timelineTime: timelineTime) }) {
                return clip
            }
        }
        return nil
    }

    private func clipContainsTimelineTime(_ clip: ClipRef, timelineTime: TimeInterval) -> Bool {
        let start = clip.timelineIn
        let end = clip.timelineIn + clip.duration
        return timelineTime >= (start - 0.0001) && timelineTime <= (end + 0.0001)
    }

    private func playbackQualityMode() -> PlaybackQualityMode {
        switch project.settings.defaultQualityMode.lowercased() {
        case "half":
            return .half
        case "quarter":
            return .quarter
        default:
            return .full
        }
    }

    private var normalizedPlaybackRange: (start: TimeInterval, end: TimeInterval)? {
        guard let inPoint, let outPoint else { return nil }
        let maxDuration = max(0, activeSequence?.duration ?? 0)
        let start = min(max(0, inPoint), maxDuration)
        let end = min(max(0, outPoint), maxDuration)
        let minRange = 1.0 / max(1, project.fps)
        guard end - start >= minRange else { return nil }
        return (start, end)
    }

    private func sourceDuration(for asset: MediaAsset?) -> TimeInterval {
        guard let asset else { return 0 }
        let fallbackDuration = asset.duration > 0 ? asset.duration : 4.0
        let minDuration = 1.0 / max(1, project.fps)
        return max(minDuration, fallbackDuration)
    }

    private var normalizedSourceRange: (start: TimeInterval, end: TimeInterval)? {
        guard let sourceInPoint, let sourceOutPoint else { return nil }
        let maxDuration = sourceDuration(for: selectedSourceAsset)
        guard maxDuration > 0 else { return nil }
        let start = min(max(0, sourceInPoint), maxDuration)
        let end = min(max(0, sourceOutPoint), maxDuration)
        let minRange = 1.0 / max(1, project.fps)
        guard end - start >= minRange else { return nil }
        return (start, end)
    }

    private func sourceInsertionRange(
        for asset: MediaAsset,
        usingMarkedRange: Bool
    ) -> SourceInsertionRange {
        let defaultDuration = sourceDuration(for: asset)
        let minRange = 1.0 / max(1, project.fps)

        guard usingMarkedRange,
              selectedAssetID == asset.id,
              let markedRange = normalizedSourceRange else {
            return SourceInsertionRange(inTime: 0, outTime: defaultDuration, usesMarkedRange: false)
        }

        let start = min(max(0, markedRange.start), defaultDuration)
        let end = min(max(0, markedRange.end), defaultDuration)
        guard end - start >= minRange else {
            return SourceInsertionRange(inTime: 0, outTime: defaultDuration, usesMarkedRange: false)
        }

        return SourceInsertionRange(inTime: start, outTime: end, usesMarkedRange: true)
    }

    private func sanitizeBinName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedBinNameKey(_ name: String) -> String {
        name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale.current
        )
    }

    private func uniqueBinName(from base: String, excluding excludedBinID: UUID? = nil) -> String {
        let baseName = sanitizeBinName(base) ?? "Bin"
        let existingNames = Set(
            project.bins
                .filter { $0.id != excludedBinID }
                .map { normalizedBinNameKey($0.name) }
        )
        var candidate = baseName
        var suffix = 2
        while existingNames.contains(normalizedBinNameKey(candidate)) {
            candidate = "\(baseName) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private struct ExportArtifact {
        let bundleURL: URL
        let outputFileURL: URL
    }

    private func exportArtifactsRootURL() -> URL {
        if let currentProjectBundleURL {
            let paths = ProjectPaths(bundleURL: currentProjectBundleURL)
            return paths.cacheDirectoryURL.appendingPathComponent("exports", isDirectory: true)
        }

        return FileManager.default.temporaryDirectory
            .appendingPathComponent("PremierCloneExports", isDirectory: true)
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
    }

    private func writeExportArtifact(for job: RenderJob, preset: ExportPreset, sequence: EditorSequence) throws -> ExportArtifact {
        let fileManager = FileManager.default
        let rootURL = exportArtifactsRootURL()
        if !fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let bundleName = "\(safeFilenameComponent(sequence.name))-\(safeFilenameComponent(preset.name))-\(timestamp)"
        let bundleURL = rootURL.appendingPathComponent(bundleName, isDirectory: true)
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let outputFileName = "export.\(preset.container.lowercased())"
        let outputFileURL = bundleURL.appendingPathComponent(outputFileName, isDirectory: false)
        let receiptURL = bundleURL.appendingPathComponent("export-info.txt", isDirectory: false)
        let receipt = [
            "PremierClone Export Bundle",
            "Project: \(project.name)",
            "Sequence: \(sequence.name)",
            "Preset: \(preset.name)",
            "Resolution: \(preset.resolution)",
            "Container: \(preset.container.uppercased())",
            "Codec: \(preset.videoCodec) / \(preset.audioCodec)",
            "FPS: \(String(format: "%.2f", preset.fps))",
            "Job ID: \(job.id.uuidString)",
            "Output: \(outputFileName)",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))"
        ].joined(separator: "\n")
        guard let receiptData = receipt.data(using: String.Encoding.utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try receiptData.write(to: receiptURL, options: Data.WritingOptions.atomic)

        return ExportArtifact(bundleURL: bundleURL, outputFileURL: outputFileURL)
    }

    private func buildExportHistoryItem(for job: RenderJob, artifact: ExportArtifact) -> ExportHistoryItem? {
        guard let preset = exportPreset(id: job.presetID),
              let sequence = project.sequences.first(where: { $0.id == job.sequenceID }) else {
            return nil
        }

        do {
            let item = ExportHistoryItem(
                jobID: job.id,
                sequenceID: sequence.id,
                sequenceName: sequence.name,
                presetID: preset.id,
                presetName: preset.name,
                resolution: preset.resolution,
                container: preset.container,
                outputURL: artifact.bundleURL,
                outputFileName: artifact.outputFileURL.lastPathComponent
            )
            try writeExportHistoryMetadata(item)
            return item
        } catch {
            statusMessage = "Export artifact write failed: \(error.localizedDescription)"
            return nil
        }
    }

    private func safeFilenameComponent(_ value: String) -> String {
        let replaced = value.replacingOccurrences(
            of: "[^A-Za-z0-9_-]+",
            with: "-",
            options: .regularExpression
        )
        let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmed.isEmpty ? "untitled" : trimmed
    }

    private func exportHistoryMetadataURL(for outputURL: URL) -> URL {
        outputURL.appendingPathComponent("export-history.json", isDirectory: false)
    }

    private func exportOutputURL(for item: ExportHistoryItem) -> URL {
        guard let outputFileName = item.outputFileName else {
            return item.outputURL
        }
        let fileURL = item.outputURL.appendingPathComponent(outputFileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: fileURL.path()) {
            return fileURL
        }
        return item.outputURL
    }

    private func writeExportHistoryMetadata(_ item: ExportHistoryItem) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(item)
        try data.write(to: exportHistoryMetadataURL(for: item.outputURL), options: .atomic)
    }

    private func loadExportHistory() -> [ExportHistoryItem] {
        guard let currentProjectBundleURL else { return [] }

        let rootURL = ProjectPaths(bundleURL: currentProjectBundleURL)
            .cacheDirectoryURL
            .appendingPathComponent("exports", isDirectory: true)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let bundleURLs = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let items = bundleURLs.compactMap { bundleURL -> ExportHistoryItem? in
                let metadataURL = exportHistoryMetadataURL(for: bundleURL)
                guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }
                guard let data = try? Data(contentsOf: metadataURL) else { return nil }
                return try? decoder.decode(ExportHistoryItem.self, from: data)
            }

            return items.sorted(by: { $0.completedAt > $1.completedAt })
        } catch {
            statusMessage = "Export history load failed: \(error.localizedDescription)"
            return []
        }
    }

    private func loadRecentProjects() -> [RecentProject] {
        guard let data = userDefaults.data(forKey: recentProjectsKey) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([RecentProject].self, from: data) else {
            return []
        }

        let fileManager = FileManager.default
        return decoded
            .filter { fileManager.fileExists(atPath: $0.path) }
            .sorted(by: { $0.lastOpened > $1.lastOpened })
    }

    private func persistRecentProjects(_ projects: [RecentProject]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(projects) else { return }
        userDefaults.set(data, forKey: recentProjectsKey)
    }

    private func registerRecentProject(bundleURL: URL, name: String) {
        let standardizedPath = bundleURL.standardizedFileURL.path
        var updated = recentProjects.filter { $0.path != standardizedPath }
        updated.insert(RecentProject(name: name, path: standardizedPath, lastOpened: Date()), at: 0)

        if updated.count > recentProjectsLimit {
            updated = Array(updated.prefix(recentProjectsLimit))
        }

        recentProjects = updated
        persistRecentProjects(updated)
    }

    public func openRecentProject(_ recent: RecentProject) {
        let url = recent.url
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "Recent project not found"
            removeRecentProject(recent)
            return
        }
        openProject(at: url)
    }

    public func removeRecentProject(_ recent: RecentProject) {
        recentProjects.removeAll { $0.id == recent.id }
        persistRecentProjects(recentProjects)
    }

    public func clearRecentProjects() {
        recentProjects = []
        userDefaults.removeObject(forKey: recentProjectsKey)
    }

    public func revealRecentProject(_ recent: RecentProject) {
        #if canImport(AppKit)
        let url = recent.url
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #else
        statusMessage = "Reveal project is only available on macOS"
        #endif
    }

    private func refreshTranscriptMatches() {
        let allSegments = activeSequence?.captionTracks.flatMap(\.segments)
            .sorted(by: { $0.start < $1.start }) ?? []

        if transcriptQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            transcriptMatches = allSegments
            return
        }

        transcriptMatches = allSegments.filter {
            $0.text.localizedCaseInsensitiveContains(transcriptQuery)
        }
    }

    private func runTranscriptSearchArtifact() {
        guard let sequence = activeSequence else { return }
        do {
            lastAIArtifact = try aiService.run(
                taskType: .transcriptSearch,
                sequenceID: sequence.id,
                options: ["query": transcriptQuery],
                in: project
            )
        } catch {
            // Non-blocking for transcript UI.
        }
    }

    private func closeTimelineGap(start: TimeInterval, end: TimeInterval) -> Bool {
        guard let sequenceID = activeSequenceID ?? project.sequences.first?.id,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequenceID }) else {
            return false
        }

        let gap = max(0, end - start)
        guard gap > 0 else { return false }
        recordUndoSnapshot()

        var updatedProject = project

        for trackIndex in updatedProject.sequences[sequenceIndex].videoTracks.indices {
            for clipIndex in updatedProject.sequences[sequenceIndex].videoTracks[trackIndex].clips.indices {
                if updatedProject.sequences[sequenceIndex].videoTracks[trackIndex].clips[clipIndex].timelineIn >= end {
                    updatedProject.sequences[sequenceIndex].videoTracks[trackIndex].clips[clipIndex].timelineIn -= gap
                }
            }
            updatedProject.sequences[sequenceIndex].videoTracks[trackIndex].clips.sort { $0.timelineIn < $1.timelineIn }
        }

        for trackIndex in updatedProject.sequences[sequenceIndex].audioTracks.indices {
            for clipIndex in updatedProject.sequences[sequenceIndex].audioTracks[trackIndex].clips.indices {
                if updatedProject.sequences[sequenceIndex].audioTracks[trackIndex].clips[clipIndex].timelineIn >= end {
                    updatedProject.sequences[sequenceIndex].audioTracks[trackIndex].clips[clipIndex].timelineIn -= gap
                }
            }
            updatedProject.sequences[sequenceIndex].audioTracks[trackIndex].clips.sort { $0.timelineIn < $1.timelineIn }
        }

        updatedProject.sequences[sequenceIndex].duration = TimelineDurationCalculator.duration(of: updatedProject.sequences[sequenceIndex])
        project = updatedProject
        sanitizeSelectedClip()
        playheadTime = min(playheadTime, updatedProject.sequences[sequenceIndex].duration)
        return true
    }

    private func restartAutosaveTimer() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil

        guard currentProjectBundleURL != nil else {
            return
        }

        let interval = max(10, project.settings.autosaveIntervalSeconds)
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performAutosave()
            }
        }
    }

    private func startExportTask(sequence: EditorSequence, preset: ExportPreset) {
        exportProgressTask?.cancel()
        exportProgressTask = Task { [weak self] in
            guard let self else { return }
            guard let job = self.renderEngine.currentJob() else {
                await MainActor.run {
                    self.exportStatusMessage = "Failed"
                    self.statusMessage = "Export failed: no active render job"
                }
                return
            }

            do {
                let artifact = try self.writeExportArtifact(for: job, preset: preset, sequence: sequence)
                try await self.renderEngine.export(
                    project: self.project,
                    sequence: sequence,
                    preset: preset,
                    outputURL: artifact.outputFileURL
                ) { progress in
                    Task { @MainActor in
                        self.exportProgress = progress
                    }
                }

                let completed = try self.renderEngine.completeCurrentJob()
                await MainActor.run {
                    self.exportProgress = 1
                    self.exportStatusMessage = "Completed"
                    self.completedExports.insert(completed, at: 0)
                    if let historyItem = self.buildExportHistoryItem(for: completed, artifact: artifact) {
                        self.exportHistory.insert(historyItem, at: 0)
                    }
                    self.statusMessage = "Export completed"
                }
            } catch {
                _ = try? self.renderEngine.failCurrentJob()
                await MainActor.run {
                    self.exportProgress = 0
                    self.exportStatusMessage = "Failed"
                    self.statusMessage = "Export failed: \(error.localizedDescription)"
                }
            }

            await MainActor.run {
                self.exportProgressTask = nil
            }
        }
    }

    private func startPlaybackLoop() {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                let baseFrameDuration = 1.0 / max(1, self?.project.fps ?? 30)
                let sleepNanos = UInt64(baseFrameDuration * 1_000_000_000)
                try? await Task.sleep(nanoseconds: max(5_000_000, sleepNanos))
                guard let self else { return }

                await MainActor.run {
                    guard self.isPlaying else { return }
                    let sequenceDuration = max(0, self.activeSequence?.duration ?? 0)
                    guard sequenceDuration > 0 else {
                        self.stopPlaybackLoop()
                        self.statusMessage = "Timeline is empty"
                        return
                    }

                    let speed = min(4.0, max(0.25, self.playbackRate))
                    let nextTime = self.playheadTime + (baseFrameDuration * speed)

                    if self.isLoopPlaybackEnabled, let range = self.normalizedPlaybackRange {
                        if nextTime >= range.end {
                            self.updatePlayhead(to: range.start)
                        } else {
                            self.updatePlayhead(to: nextTime)
                        }
                        return
                    }

                    if nextTime >= sequenceDuration {
                        self.updatePlayhead(to: sequenceDuration)
                        self.stopPlaybackLoop()
                        self.statusMessage = "Reached end of sequence"
                    } else {
                        self.updatePlayhead(to: nextTime)
                    }
                }
            }
        }
    }

    private func stopPlaybackLoop() {
        playbackTask?.cancel()
        playbackTask = nil
        _ = playbackEngine.pause()
        isPlaying = false
    }

    private func recordUndoSnapshot() {
        undoHistory.append(project)
        if undoHistory.count > 80 {
            undoHistory.removeFirst(undoHistory.count - 80)
        }
        redoHistory.removeAll()
        lastInspectorSnapshotAt = nil
    }

    private func maybeRecordInspectorSnapshot() {
        let now = Date()
        if let lastInspectorSnapshotAt, now.timeIntervalSince(lastInspectorSnapshotAt) < 0.35 {
            return
        }
        undoHistory.append(project)
        if undoHistory.count > 80 {
            undoHistory.removeFirst(undoHistory.count - 80)
        }
        redoHistory.removeAll()
        lastInspectorSnapshotAt = now
    }

    public func timecode(_ seconds: TimeInterval) -> String {
        let totalFrames = Int((seconds * project.fps).rounded())
        let fps = max(1, Int(project.fps.rounded()))
        let frames = totalFrames % fps
        let totalSeconds = totalFrames / fps
        let ss = totalSeconds % 60
        let mm = (totalSeconds / 60) % 60
        let hh = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, frames)
    }

    private func updateSelectedClip(_ mutation: (inout ClipRef) -> Void) {
        mutateSelectedClip(recordSnapshot: true, mutation)
    }

    private func mutateSelectedClip(recordSnapshot: Bool = true, _ mutation: (inout ClipRef) -> Void) {
        guard let selectedClipID else { return }
        guard let sequenceID = activeSequenceID ?? project.sequences.first?.id,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequenceID }) else { return }
        if recordSnapshot {
            maybeRecordInspectorSnapshot()
        }

        var project = self.project
        var updated = false
        var blockedByLock = false

        for trackIndex in project.sequences[sequenceIndex].videoTracks.indices {
            if let clipIndex = project.sequences[sequenceIndex].videoTracks[trackIndex].clips.firstIndex(where: { $0.id == selectedClipID }) {
                if isTrackLocked(project.sequences[sequenceIndex].videoTracks[trackIndex].id) {
                    blockedByLock = true
                    break
                }
                mutation(&project.sequences[sequenceIndex].videoTracks[trackIndex].clips[clipIndex])
                updated = true
                break
            }
        }

        if !updated && !blockedByLock {
            for trackIndex in project.sequences[sequenceIndex].audioTracks.indices {
                if let clipIndex = project.sequences[sequenceIndex].audioTracks[trackIndex].clips.firstIndex(where: { $0.id == selectedClipID }) {
                    if isTrackLocked(project.sequences[sequenceIndex].audioTracks[trackIndex].id) {
                        blockedByLock = true
                        break
                    }
                    mutation(&project.sequences[sequenceIndex].audioTracks[trackIndex].clips[clipIndex])
                    updated = true
                    break
                }
            }
        }

        if blockedByLock {
            statusMessage = "Track is locked"
            return
        }

        guard updated else { return }
        self.project = project
    }

    private func sanitizeSelectedClip() {
        if let selectedClipID {
            let existsInVideo = activeSequence?.videoTracks.contains(where: { track in
                track.clips.contains(where: { $0.id == selectedClipID })
            }) ?? false
            let existsInAudio = activeSequence?.audioTracks.contains(where: { track in
                track.clips.contains(where: { $0.id == selectedClipID })
            }) ?? false

            if !(existsInVideo || existsInAudio) {
                self.selectedClipID = nil
            }
        }

        let validIDs = Set(
            (activeSequence?.videoTracks.flatMap(\.clips).map(\.id) ?? []) +
            (activeSequence?.audioTracks.flatMap(\.clips).map(\.id) ?? [])
        )
        if !selectedClipIDs.isEmpty {
            selectedClipIDs = selectedClipIDs.intersection(validIDs)
        }
        syncPrimarySelection()

        if let selectedAssetID,
           !project.assets.contains(where: { $0.id == selectedAssetID }) {
            self.selectedAssetID = project.assets.first?.id
            sourcePlayheadTime = 0
            sourceInPoint = nil
            sourceOutPoint = nil
        }

        let sourceMax = sourceDuration(for: selectedSourceAsset)
        sourcePlayheadTime = min(sourceMax, max(0, sourcePlayheadTime))

        if sourceInPoint != nil, sourceOutPoint != nil, normalizedSourceRange == nil {
            sourceInPoint = nil
            sourceOutPoint = nil
        }

        guard let sequence = activeSequence else {
            targetedVideoTrackID = nil
            targetedAudioTrackID = nil
            lockedTrackIDs = []
            return
        }

        if let targetedVideoTrackID,
           !sequence.videoTracks.contains(where: { $0.id == targetedVideoTrackID }) {
            self.targetedVideoTrackID = sequence.videoTracks.first?.id
        } else if self.targetedVideoTrackID == nil {
            self.targetedVideoTrackID = sequence.videoTracks.first?.id
        }

        if let targetedAudioTrackID,
           !sequence.audioTracks.contains(where: { $0.id == targetedAudioTrackID }) {
            self.targetedAudioTrackID = sequence.audioTracks.first?.id
        } else if self.targetedAudioTrackID == nil {
            self.targetedAudioTrackID = sequence.audioTracks.first?.id
        }

        let validTrackIDs = Set(sequence.videoTracks.map(\.id) + sequence.audioTracks.map(\.id))
        lockedTrackIDs = Set(lockedTrackIDs.filter { validTrackIDs.contains($0) })
    }

    private func syncPrimarySelection() {
        if let selectedClipID, selectedClipIDs.contains(selectedClipID) {
            return
        }
        selectedClipID = selectedClipIDs.first
    }

    private func clipTargets(
        for clipIDs: Set<UUID>,
        in sequence: EditorSequence
    ) -> [(clip: ClipRef, trackID: UUID, kind: TrackKind)] {
        guard !clipIDs.isEmpty else { return [] }
        var results: [(clip: ClipRef, trackID: UUID, kind: TrackKind)] = []
        for track in sequence.videoTracks {
            for clip in track.clips where clipIDs.contains(clip.id) {
                results.append((clip, track.id, .video))
            }
        }
        for track in sequence.audioTracks {
            for clip in track.clips where clipIDs.contains(clip.id) {
                results.append((clip, track.id, .audio))
            }
        }
        return results
    }
}

public struct EditorRootView: View {
    @EnvironmentObject private var workspace: EditorWorkspace
    #if canImport(AVKit) && canImport(AVFoundation)
    @StateObject private var programPlayer = TimelineProgramPlayer()
    #endif
    @State private var workspaceStage: WorkspaceStage = .home
    @State private var browserTab: BrowserTab = .libraries
    @State private var inspectorTab: InspectorTab = .video
    @State private var isBrowserPanelVisible = true
    @State private var isInspectorPanelVisible = true
    @State private var inspectorPlacement: WorkspaceLayoutSettings.InspectorPlacement = .right
    @State private var workspacePreset: WorkspacePreset = .editing
    @State private var isRestoringWorkspaceLayout = false
    @State private var browserPanelWidth: CGFloat = 290
    @State private var inspectorPanelWidth: CGFloat = 285
    @State private var viewerPaneHeight: CGFloat = 360
    @State private var viewerLayout: WorkspaceLayoutSettings.ViewerLayout = .auto
    @State private var trackLaneHeight: CGFloat = 54
    @State private var selectedExportPresetID = "youtube-1080p-h264"
    @State private var showsExportQueue = false
    @State private var timelineZoom: Double = 1.0
    @State private var sourceViewerZoom: Double = 1.0
    @State private var programViewerZoom: Double = 1.0
    @State private var selectedBrowserBinID: UUID?
    @State private var editingBrowserBinID: UUID?
    @State private var editingBrowserBinName = ""
    @State private var draggingClipID: UUID?
    @State private var dragTranslationX: CGFloat = 0
    @State private var isGroupDragging = false
    @State private var marqueeTrackID: UUID?
    @State private var marqueeTrackKind: TrackKind?
    @State private var marqueeStartX: CGFloat?
    @State private var marqueeCurrentX: CGFloat?
    @State private var isMarqueeSelecting = false
    @State private var lastMarqueeSelectionAt: Date?
    @State private var leftResizeStartWidth: CGFloat?
    @State private var rightResizeStartWidth: CGFloat?
    @State private var centerResizeStartHeight: CGFloat?
    @State private var showsExportBlockedAlert = false
    private let timelineZoomBounds: ClosedRange<Double> = 0.6...2.2
    private let viewerZoomBounds: ClosedRange<Double> = 0.6...2.5
    private let panelWidthBounds: ClosedRange<Double> = 145...420
    private let viewerPaneHeightBounds: ClosedRange<Double> = 220...900
    private let trackLaneHeightBounds: ClosedRange<Double> = 44...96
    @State private var isScrubbingProgramPlayback = false

    public init() {}

    private struct ExportBlockedAlertModifier: ViewModifier {
        @Binding var isPresented: Bool
        @Binding var showsExportQueue: Bool
        @ObservedObject var workspace: EditorWorkspace
        var enterEditor: () -> Void

        func body(content: Content) -> some View {
            content.alert("Export Unavailable", isPresented: $isPresented) {
                if case .missingMedia = workspace.exportSupportStatus {
                    Button("Relink Missing Media") {
                        enterEditor()
                        workspace.relinkFirstMissingAssetUsingDialog()
                    }
                } else if case .emptySequence = workspace.exportSupportStatus {
                    Button("Append First Clip") {
                        enterEditor()
                        workspace.appendFirstAssetToTimeline()
                    }
                } else if case .unsupported = workspace.exportSupportStatus {
                    Button("Open Export Queue") {
                        enterEditor()
                        showsExportQueue = true
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(workspace.exportSupportMessage)
            }
        }
    }

    private enum WorkspaceStage {
        case home
        case editor
    }

    private enum BrowserTab: String, CaseIterable, Identifiable {
        case libraries = "Libraries"
        case media = "Media"
        case timelineIndex = "Index"
        case effects = "Effects"

        var id: String { rawValue }
    }

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case video = "Video"
        case audio = "Audio"
        case captions = "Captions"
        case info = "Info"

        var id: String { rawValue }
    }

    private enum WorkspacePreset: String {
        case editing
        case focused
        case captions
        case custom

        var title: String {
            switch self {
            case .editing:
                return "Editing"
            case .focused:
                return "Focused"
            case .captions:
                return "Captions"
            case .custom:
                return "Custom"
            }
        }
    }

    private enum SidePanelKind {
        case browser
        case inspector
    }

    private var activeSequence: EditorSequence? {
        workspace.activeSequence
    }

    private var videoTracks: [TimelineTrack] {
        activeSequence?.videoTracks ?? []
    }

    private var audioTracks: [TimelineTrack] {
        activeSequence?.audioTracks ?? []
    }

    private var videoClips: [ClipRef] {
        videoTracks
            .flatMap(\.clips)
            .sorted(by: { $0.timelineIn < $1.timelineIn })
    }

    private var audioClips: [ClipRef] {
        audioTracks
            .flatMap(\.clips)
            .sorted(by: { $0.timelineIn < $1.timelineIn })
    }

    private var browserBins: [MediaBin] {
        workspace.project.bins
    }

    private var selectedBrowserBin: MediaBin? {
        guard let selectedBrowserBinID else { return nil }
        return browserBins.first(where: { $0.id == selectedBrowserBinID })
    }

    private var browserAssets: [MediaAsset] {
        guard browserTab == .libraries, let selectedBrowserBin else {
            return workspace.project.assets
        }

        let assetLookup = Dictionary(uniqueKeysWithValues: workspace.project.assets.map { ($0.id, $0) })
        return selectedBrowserBin.assetIDs.compactMap { assetLookup[$0] }
    }

    private var canAddSelectedAssetToActiveBin: Bool {
        guard let selectedAssetID = workspace.selectedAssetID,
              let selectedBrowserBin else {
            return false
        }
        return !selectedBrowserBin.assetIDs.contains(selectedAssetID)
    }

    private var canRemoveSelectedAssetFromActiveBin: Bool {
        guard let selectedAssetID = workspace.selectedAssetID,
              let selectedBrowserBin else {
            return false
        }
        return selectedBrowserBin.assetIDs.contains(selectedAssetID)
    }

    private func isAssetMissing(_ asset: MediaAsset) -> Bool {
        workspace.missingAssetIDs.contains(asset.id)
    }

    private var selectedExportPreset: ExportPreset? {
        workspace.exportPreset(id: selectedExportPresetID) ?? workspace.exportPresets.first
    }

    private var activeExportJob: RenderJob? {
        workspace.renderEngine.currentJob()
    }

    private var activeExportPresetName: String {
        guard let job = activeExportJob,
              let preset = workspace.exportPreset(id: job.presetID) else {
            return selectedExportPreset?.name ?? "Export"
        }
        return preset.name
    }

    private var clipCount: Int {
        videoClips.count
    }

    private var captionSegments: [CaptionSegment] {
        activeSequence?.captionTracks
            .flatMap(\.segments)
            .sorted(by: { $0.start < $1.start }) ?? []
    }

    private var activeCaptionAtPlayhead: CaptionSegment? {
        captionSegments.first(where: {
            workspace.playheadTime >= $0.start && workspace.playheadTime <= $0.end
        })
    }

    private enum ViewerKind {
        case source
        case program
    }

    private struct ViewerDescriptor {
        var asset: MediaAsset?
        var headline: String
        var detail: String
        var seekTime: TimeInterval?
        var shouldPlay: Bool
    }

    private var sourceAsset: MediaAsset? {
        if let selectedAssetID = workspace.selectedAssetID,
           let selected = workspace.project.assets.first(where: { $0.id == selectedAssetID }) {
            return selected
        }
        return workspace.project.assets.first
    }

    private var sourceAssetDuration: TimeInterval {
        guard let sourceAsset else { return 1.0 }
        let fallbackDuration = sourceAsset.duration > 0 ? sourceAsset.duration : 4.0
        let minDuration = 1.0 / max(1, workspace.project.fps)
        return max(minDuration, fallbackDuration)
    }

    private var sourceViewerDescriptor: ViewerDescriptor {
        if let asset = sourceAsset {
            let sourceRangeLabel: String
            if let sourceRange = workspace.sourceRange {
                sourceRangeLabel = " • I/O \(workspace.timecode(sourceRange.start))-\(workspace.timecode(sourceRange.end))"
            } else {
                sourceRangeLabel = " • Full Clip"
            }
            return ViewerDescriptor(
                asset: asset,
                headline: asset.name,
                detail: "\(asset.type.rawValue.capitalized) • \(workspace.timecode(sourceAssetDuration))\(sourceRangeLabel)",
                seekTime: workspace.sourcePlayheadTime,
                shouldPlay: false
            )
        }

        return ViewerDescriptor(
            asset: nil,
            headline: "No Source Selected",
            detail: "Choose media in Browser to preview",
            seekTime: nil,
            shouldPlay: false
        )
    }

    private var programViewerDescriptor: ViewerDescriptor {
        guard let clip = timelineProgramClip else {
            return ViewerDescriptor(
                asset: nil,
                headline: "No Program Clip",
                detail: "Append clips to timeline to preview sequence",
                seekTime: nil,
                shouldPlay: false
            )
        }

        let asset = workspace.project.assets.first(where: { $0.id == clip.assetID })
        let sourceTime = programSourceTime(for: clip)
        let detail = "Timeline \(workspace.timecode(workspace.playheadTime)) • Source \(workspace.timecode(sourceTime))"
        return ViewerDescriptor(
            asset: asset,
            headline: asset?.name ?? "Clip",
            detail: detail,
            seekTime: sourceTime,
            shouldPlay: workspace.isPlaying
        )
    }

    private var timelineProgramClip: ClipRef? {
        workspace.programClip(at: workspace.playheadTime)
    }

    private func programSourceTime(for clip: ClipRef) -> TimeInterval {
        let offset = workspace.playheadTime - clip.timelineIn
        let unclamped = clip.inTime + offset
        return min(clip.outTime, max(clip.inTime, unclamped))
    }

    private func viewerZoom(for kind: ViewerKind) -> Double {
        kind == .source ? sourceViewerZoom : programViewerZoom
    }

    private func adjustViewerZoom(for kind: ViewerKind, delta: Double) {
        if kind == .source {
            sourceViewerZoom = clamped(sourceViewerZoom + delta, in: viewerZoomBounds)
        } else {
            programViewerZoom = clamped(programViewerZoom + delta, in: viewerZoomBounds)
        }
    }

    private func clamped(_ value: Double, in bounds: ClosedRange<Double>) -> Double {
        min(bounds.upperBound, max(bounds.lowerBound, value))
    }

    private func shouldStackViewers(compact: Bool, panelsVisible: Bool) -> Bool {
        switch viewerLayout {
        case .auto:
            return compact && panelsVisible
        case .sideBySide:
            return false
        case .stacked:
            return true
        }
    }

    private var viewerLayoutTitle: String {
        switch viewerLayout {
        case .auto:
            return "Auto"
        case .sideBySide:
            return "SideBySide"
        case .stacked:
            return "Stacked"
        }
    }

    public var body: some View {
        let baseView = AnyView(
            GeometryReader { geometry in
                let width = geometry.size.width
                let compactEditor = width < 1320
                let narrowEditor = width < 1120

                ZStack {
                    Color(red: 0.11, green: 0.11, blue: 0.12)
                    .ignoresSafeArea()

                    if workspaceStage == .home {
                        homeScreen(compact: width < 1100)
                    } else {
                        editorWorkspace(compact: compactEditor, narrow: narrowEditor)
                            .overlay(alignment: .topTrailing) {
                                if workspace.showsShortcutHelp {
                                    shortcutsOverlay
                                        .padding(14)
                                }
                            }
                    }
                }
            }
        )

        return AnyView(
            baseView
                .frame(minWidth: 960, minHeight: 620)
                .modifier(
                    ExportBlockedAlertModifier(
                        isPresented: $showsExportBlockedAlert,
                        showsExportQueue: $showsExportQueue,
                        workspace: workspace,
                        enterEditor: { enterEditor() }
                    )
                )
                .sheet(isPresented: $showsExportQueue) {
                    exportQueueSheet
                }
                .onReceive(NotificationCenter.default.publisher(for: EditorCommand.newProject)) { _ in
                    workspace.createNewProject()
                    enterEditor()
                }
                .onReceive(NotificationCenter.default.publisher(for: EditorCommand.openProject)) { _ in
                    let previousProjectURL = workspace.currentProjectBundleURL
                    workspace.openProjectUsingDialog()
                    if workspace.currentProjectBundleURL != nil || workspace.currentProjectBundleURL != previousProjectURL {
                        enterEditor()
                    }
                }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.saveProject)) { _ in
            enterEditor()
            workspace.saveProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.importMedia)) { _ in
            enterEditor()
            workspace.importMediaUsingDialog()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.generateProxyManifest)) { _ in
            enterEditor()
            workspace.generateProxyManifest()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.restoreLatestAutosave)) { _ in
            enterEditor()
            workspace.restoreLatestAutosave()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.relinkFirstMissingAsset)) { _ in
            enterEditor()
            workspace.relinkFirstMissingAssetUsingDialog()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.retryLatestExport)) { _ in
            enterEditor()
            if let item = workspace.exportHistory.first {
                selectedExportPresetID = item.presetID
            }
            workspace.retryLatestExport()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.openLatestExport)) { _ in
            workspace.openLatestExport()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.revealLatestExport)) { _ in
            enterEditor()
            workspace.revealLatestExport()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.appendFirstAsset)) { _ in
            enterEditor()
            workspace.appendFirstAssetToTimeline()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.splitFirstClip)) { _ in
            enterEditor()
            workspace.splitFirstClipAtPlayhead()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.rippleDeleteFirstClip)) { _ in
            enterEditor()
            workspace.rippleDeleteFirstClip()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.playPause)) { _ in
            enterEditor()
            toggleProgramPlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.jumpToStart)) { _ in
            enterEditor()
            seekProgram(to: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.jumpToEnd)) { _ in
            enterEditor()
            seekProgram(to: workspace.activeSequence?.duration ?? 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.stepBackwardFrame)) { _ in
            enterEditor()
            stepProgramFrame(-1)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.stepForwardFrame)) { _ in
            enterEditor()
            stepProgramFrame(1)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.shuttleBackward)) { _ in
            enterEditor()
            seekProgramBy(-1)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.shuttleStop)) { _ in
            enterEditor()
            pauseProgramPlayback(userInitiated: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.shuttleForward)) { _ in
            enterEditor()
            startProgramPlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.previousEditPoint)) { _ in
            enterEditor()
            workspace.jumpToPreviousEditPoint()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.nextEditPoint)) { _ in
            enterEditor()
            workspace.jumpToNextEditPoint()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.cyclePlaybackRate)) { _ in
            enterEditor()
            workspace.cyclePlaybackRate()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.togglePreviewMute)) { _ in
            enterEditor()
            workspace.togglePreviewMute()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.setInPoint)) { _ in
            enterEditor()
            workspace.setInPointAtPlayhead()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.setOutPoint)) { _ in
            enterEditor()
            workspace.setOutPointAtPlayhead()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.clearInOutPoints)) { _ in
            enterEditor()
            workspace.clearInOutPoints()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.toggleLoopPlayback)) { _ in
            enterEditor()
            workspace.toggleLoopPlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.undo)) { _ in
            enterEditor()
            workspace.undo()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.redo)) { _ in
            enterEditor()
            workspace.redo()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.newSequence)) { _ in
            enterEditor()
            workspace.createSequence()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.duplicateSequence)) { _ in
            enterEditor()
            workspace.duplicateActiveSequence()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.addVideoTrack)) { _ in
            enterEditor()
            workspace.addTrack(kind: .video)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.addAudioTrack)) { _ in
            enterEditor()
            workspace.addTrack(kind: .audio)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.toggleTimelineEditMode)) { _ in
            enterEditor()
            workspace.toggleTimelineEditMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.addMarker)) { _ in
            enterEditor()
            workspace.addMarkerAtPlayhead()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.nextMarker)) { _ in
            enterEditor()
            workspace.jumpToNextMarker()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.toggleTimelineMode)) { _ in
            enterEditor()
            workspace.switchTimelineMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.toggleShortcutHelp)) { _ in
            enterEditor()
            workspace.toggleShortcutHelp()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.toggleBrowserPanel)) { _ in
            enterEditor()
            toggleBrowserPanelVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.toggleInspectorPanel)) { _ in
            enterEditor()
            toggleInspectorPanelVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.applyEditingWorkspacePreset)) { _ in
            enterEditor()
            applyWorkspacePreset(.editing)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.applyFocusedWorkspacePreset)) { _ in
            enterEditor()
            applyWorkspacePreset(.focused)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.applyCaptionsWorkspacePreset)) { _ in
            enterEditor()
            applyWorkspacePreset(.captions)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.moveInspectorLeft)) { _ in
            enterEditor()
            setInspectorPlacement(.left)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.moveInspectorRight)) { _ in
            enterEditor()
            setInspectorPlacement(.right)
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.resetWorkspaceLayout)) { _ in
            enterEditor()
            resetWorkspaceLayoutToDefaults()
        }
        .onAppear {
            restoreWorkspaceLayoutFromProject()
            ensureSelectedBrowserBin()
            rebuildProgramPlayer()
        }
        .onChange(of: workspace.project.id) { _ in
            workspaceStage = .editor
            restoreWorkspaceLayoutFromProject()
            ensureSelectedBrowserBin()
            rebuildProgramPlayer()
        }
        .onChange(of: workspace.currentProjectBundleURL) { _ in
            restoreWorkspaceLayoutFromProject()
        }
        .onChange(of: workspace.activeSequenceID) { _ in
            rebuildProgramPlayer()
        }
        .onChange(of: workspace.project.sequences) { _ in
            rebuildProgramPlayer()
        }
        .onChange(of: workspace.project.bins.map(\.id)) { _ in
            ensureSelectedBrowserBin()
        }
        .onChange(of: browserTab) { _ in
            syncWorkspacePreset()
            if browserTab == .libraries {
                ensureSelectedBrowserBin()
            }
        }
        .onChange(of: inspectorTab) { _ in
            syncWorkspacePreset()
        }
        .onChange(of: timelineZoom) { _ in
            persistWorkspaceLayout()
        }
        .onChange(of: sourceViewerZoom) { _ in
            persistWorkspaceLayout()
        }
        .onChange(of: programViewerZoom) { _ in
            persistWorkspaceLayout()
        }
        .onChange(of: workspace.playheadTime) { _ in
            // When the user scrubs or jumps while paused, we want the real program player to seek.
            guard !workspace.isPlaying else { return }
            guard !isScrubbingProgramPlayback else { return }
            seekProgram(to: workspace.playheadTime)
        }
        .onChange(of: workspace.playbackRate) { _ in
            syncProgramPlaybackRate()
        }
        .onChange(of: workspace.previewVolume) { _ in
            syncProgramAudioSettings()
        }
        .onChange(of: workspace.isPreviewMuted) { _ in
            syncProgramAudioSettings()
        }
        .onChange(of: inspectorPlacement) { _ in
            persistWorkspaceLayout()
        }
        .onChange(of: browserPanelWidth) { _ in
            persistWorkspaceLayout()
        }
        .onChange(of: inspectorPanelWidth) { _ in
            persistWorkspaceLayout()
        }
        .onChange(of: viewerPaneHeight) { _ in
            persistWorkspaceLayout()
        }
        .onChange(of: viewerLayout) { _ in
            persistWorkspaceLayout()
        }
        .onChange(of: trackLaneHeight) { _ in
            persistWorkspaceLayout()
        }
        )
    }

    private func editorWorkspace(compact: Bool, narrow: Bool) -> some View {
        let leftPanelKind: SidePanelKind = inspectorPlacement == .left ? .inspector : .browser
        let rightPanelKind: SidePanelKind = inspectorPlacement == .left ? .browser : .inspector
        let leftPanelVisible = isPanelVisible(leftPanelKind)
        let rightPanelVisible = isPanelVisible(rightPanelKind)

        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    if leftPanelVisible {
                        sidePanel(for: leftPanelKind)
                            .frame(width: panelWidth(for: leftPanelKind, compact: compact, narrow: narrow))
                            .background(panelBackgroundColor(for: leftPanelKind))

                        resizeHandle {
                            if leftResizeStartWidth == nil {
                                leftResizeStartWidth = panelWidth(for: leftPanelKind, compact: compact, narrow: narrow)
                            }
                            let start = leftResizeStartWidth ?? panelWidth(for: leftPanelKind, compact: compact, narrow: narrow)
                            setPanelWidth(
                                start + $0,
                                for: leftPanelKind,
                                compact: compact,
                                narrow: narrow
                            )
                        } onEnded: {
                            leftResizeStartWidth = nil
                        }
                    }

                    centerWorkspace(
                        compact: compact,
                        panelsVisible: leftPanelVisible || rightPanelVisible
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if rightPanelVisible {
                        resizeHandle {
                            if rightResizeStartWidth == nil {
                                rightResizeStartWidth = panelWidth(for: rightPanelKind, compact: compact, narrow: narrow)
                            }
                            let start = rightResizeStartWidth ?? panelWidth(for: rightPanelKind, compact: compact, narrow: narrow)
                            setPanelWidth(
                                start - $0,
                                for: rightPanelKind,
                                compact: compact,
                                narrow: narrow
                            )
                        } onEnded: {
                            rightResizeStartWidth = nil
                        }

                        sidePanel(for: rightPanelKind)
                            .frame(width: panelWidth(for: rightPanelKind, compact: compact, narrow: narrow))
                            .background(panelBackgroundColor(for: rightPanelKind))
                    }
                }
                .background(Color(red: 0.12, green: 0.12, blue: 0.13))

                if !isBrowserPanelVisible || !isInspectorPanelVisible {
                    HStack {
                        if !isBrowserPanelVisible {
                            Button {
                                toggleBrowserPanelVisibility()
                            } label: {
                                Label("Show Browser", systemImage: "sidebar.left")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.33, green: 0.33, blue: 0.36))
                        }

                        Spacer()

                        if !isInspectorPanelVisible {
                            Button {
                                toggleInspectorPanelVisibility()
                            } label: {
                                Label("Show Inspector", systemImage: "sidebar.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.33, green: 0.33, blue: 0.36))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                }
            }

            bottomBar
                .background(Color(red: 0.10, green: 0.10, blue: 0.11))
        }
    }

    @ViewBuilder
    private func sidePanel(for kind: SidePanelKind) -> some View {
        switch kind {
        case .browser:
            browserPanel
        case .inspector:
            inspectorPanel
        }
    }

    private func panelBackgroundColor(for kind: SidePanelKind) -> Color {
        switch kind {
        case .browser:
            return Color(red: 0.12, green: 0.12, blue: 0.13)
        case .inspector:
            return Color(red: 0.12, green: 0.12, blue: 0.13)
        }
    }

    private func resizeHandle(
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.09))
            .frame(width: 4)
            .overlay(Rectangle().fill(Color.white.opacity(0.20)).frame(width: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onChanged(value.translation.width)
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
    }

    private func isPanelVisible(_ kind: SidePanelKind) -> Bool {
        switch kind {
        case .browser:
            return isBrowserPanelVisible
        case .inspector:
            return isInspectorPanelVisible
        }
    }

    private func panelWidth(for kind: SidePanelKind, compact: Bool, narrow: Bool) -> CGFloat {
        let sourceWidth = (kind == .browser) ? browserPanelWidth : inspectorPanelWidth
        return constrainedPanelWidth(sourceWidth, compact: compact, narrow: narrow)
    }

    private func setPanelWidth(_ value: CGFloat, for kind: SidePanelKind, compact: Bool, narrow: Bool) {
        let constrained = constrainedPanelWidth(value, compact: compact, narrow: narrow)
        switch kind {
        case .browser:
            browserPanelWidth = constrained
        case .inspector:
            inspectorPanelWidth = constrained
        }
    }

    private func constrainedPanelWidth(_ width: CGFloat, compact: Bool, narrow: Bool) -> CGFloat {
        let dynamicMin = narrow ? 145.0 : 210.0
        let dynamicMax = compact ? 360.0 : 420.0
        let lowerBound = max(panelWidthBounds.lowerBound, dynamicMin)
        let upperBound = min(panelWidthBounds.upperBound, dynamicMax)
        return CGFloat(clamped(Double(width), in: lowerBound...upperBound))
    }

    private func centerWorkspace(compact: Bool, panelsVisible: Bool) -> some View {
        GeometryReader { proxy in
            let totalHeight = max(420, proxy.size.height)
            let viewerHeight = constrainedViewerPaneHeight(
                viewerPaneHeight,
                totalHeight: totalHeight,
                compact: compact
            )

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    topToolbar(compact: compact)
                    viewerWorkbench(stacked: shouldStackViewers(compact: compact, panelsVisible: panelsVisible))
                }
                .padding(8)
                .background(Color(red: 0.13, green: 0.13, blue: 0.14))
                .frame(height: viewerHeight)

                verticalResizeHandle {
                    if centerResizeStartHeight == nil {
                        centerResizeStartHeight = viewerHeight
                    }
                    let start = centerResizeStartHeight ?? viewerHeight
                    viewerPaneHeight = constrainedViewerPaneHeight(
                        start + $0,
                        totalHeight: totalHeight,
                        compact: compact
                    )
                } onEnded: {
                    centerResizeStartHeight = nil
                }

                timelinePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.15, green: 0.15, blue: 0.16))
            }
        }
    }

    private func verticalResizeHandle(
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 4)
            .overlay(Rectangle().fill(Color.white.opacity(0.20)).frame(height: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onChanged(value.translation.height)
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
    }

    private func constrainedViewerPaneHeight(
        _ height: CGFloat,
        totalHeight: CGFloat,
        compact: Bool
    ) -> CGFloat {
        let minViewer = compact ? 220.0 : 260.0
        let minTimeline = compact ? 180.0 : 220.0
        let maxViewerByWindow = max(minViewer, totalHeight - minTimeline - 4.0)
        let lower = max(viewerPaneHeightBounds.lowerBound, minViewer)
        let upper = min(viewerPaneHeightBounds.upperBound, maxViewerByWindow)
        return CGFloat(clamped(Double(height), in: lower...upper))
    }

    private func homeScreen(compact: Bool) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 16)

            VStack(spacing: 10) {
                Text("PremierClone Studio")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                Text("Create fast edits with a magnetic timeline, transcript tools, and creator exports.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 700)
            }

            if compact {
                VStack(spacing: 10) {
                    Button("New Project") {
                        workspace.createNewProject()
                        enterEditor()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open Project") {
                        let previousProjectURL = workspace.currentProjectBundleURL
                        workspace.openProjectUsingDialog()
                        if workspace.currentProjectBundleURL != nil || workspace.currentProjectBundleURL != previousProjectURL {
                            enterEditor()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Open Editor") {
                        enterEditor()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 10) {
                    Button("New Project") {
                        workspace.createNewProject()
                        enterEditor()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open Project") {
                        let previousProjectURL = workspace.currentProjectBundleURL
                        workspace.openProjectUsingDialog()
                        if workspace.currentProjectBundleURL != nil || workspace.currentProjectBundleURL != previousProjectURL {
                            enterEditor()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Open Editor") {
                        enterEditor()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if compact {
                VStack(spacing: 12) {
                    homeCard(title: "Timeline", detail: "\(clipCount) clips in active sequence")
                    homeCard(title: "Captions", detail: "\(captionSegments.count) segments")
                    homeCard(title: "Exports", detail: "\(workspace.exportHistory.count) recent jobs")
                }
                .frame(maxWidth: 840)
            } else {
                HStack(spacing: 12) {
                    homeCard(title: "Timeline", detail: "\(clipCount) clips in active sequence")
                    homeCard(title: "Captions", detail: "\(captionSegments.count) segments")
                    homeCard(title: "Exports", detail: "\(workspace.exportHistory.count) recent jobs")
                }
                .frame(maxWidth: 840)
            }

            if compact {
                VStack(spacing: 12) {
                    quickStartHomePanel
                    projectHealthHomePanel
                    exportSupportBanner
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    quickStartHomePanel
                    projectHealthHomePanel
                }
                .frame(maxWidth: 860)
                exportSupportBanner
            }

            if !workspace.recentProjects.isEmpty {
                recentProjectsHomePanel
                    .frame(maxWidth: 720)
            }

            if !workspace.exportHistory.isEmpty {
                recentExportsHomePanel
                    .frame(maxWidth: 720)
            }

            Spacer()
        }
        .padding(24)
    }

    private var homeNextStepSummary: String {
        if workspace.project.assets.isEmpty {
            return "Import media to start building the first sequence."
        }
        if !workspace.missingAssets.isEmpty {
            return "Relink missing media before preview and export so playback stays reliable."
        }
        if clipCount == 0 {
            return "Insert the first clip to make the timeline editable."
        }
        if captionSegments.isEmpty {
            return "Generate captions next if you want text-based review and silence cleanup."
        }
        if workspace.exportHistory.isEmpty {
            return "Pick a creator preset and export a first draft once the cut feels good."
        }
        return "Project is in a healthy state. Resume editing or reopen a recent export."
    }

    private var quickStartHomePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Start")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("1. Import media")
                .foregroundStyle(.secondary)
            Text("2. Mark In/Out in Event Viewer and insert")
                .foregroundStyle(.secondary)
            Text("3. Play and trim")
                .foregroundStyle(.secondary)
            Text("4. Generate captions")
                .foregroundStyle(.secondary)
            Text("5. Export for YouTube/TikTok")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                quickStartActionButton("Import", systemImage: "tray.and.arrow.down") {
                    enterEditor()
                    workspace.importMediaUsingDialog()
                }
                quickStartActionButton("Insert First Clip", systemImage: "plus.rectangle.on.rectangle") {
                    enterEditor()
                    workspace.appendFirstAssetToTimeline()
                }
            }

            HStack(spacing: 8) {
                quickStartActionButton("Captions", systemImage: "captions.bubble") {
                    enterEditor()
                    workspace.runAutoCaptions()
                }
                quickStartActionButton("Export", systemImage: "square.and.arrow.up") {
                    enterEditor()
                    if workspace.canExport {
                        workspace.enqueueExport(presetID: selectedExportPreset?.id ?? "youtube-1080p-h264")
                    } else {
                        workspace.statusMessage = workspace.exportSupportMessage
                    }
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var projectHealthHomePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Project Health")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text(homeNextStepSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            homeStatusRow(
                title: "Project",
                detail: workspace.currentProjectBundleURL?.lastPathComponent ?? "Unsaved draft"
            )
            homeStatusRow(
                title: "Autosave",
                detail: latestAutosaveSummary
            )
            homeStatusRow(
                title: "Missing Media",
                detail: workspace.missingAssets.isEmpty ? "All files linked" : "\(workspace.missingAssets.count) clips need relink"
            )
            homeStatusRow(
                title: "Prep",
                detail: workspace.currentProjectBundleURL == nil ? "Save project before writing proxies" : "\(workspace.project.assets.count) assets ready for proxy manifest"
            )

            HStack(spacing: 8) {
                quickStartActionButton("Resume", systemImage: "play.rectangle") {
                    enterEditor()
                }
                quickStartActionButton("Restore Autosave", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                    enterEditor()
                    workspace.restoreLatestAutosave()
                }
                .disabled(workspace.latestAvailableAutosaveURL == nil)
            }

            HStack(spacing: 8) {
                quickStartActionButton("Relink Missing", systemImage: "link.badge.plus") {
                    enterEditor()
                    workspace.relinkFirstMissingAssetUsingDialog()
                }
                .disabled(workspace.missingAssets.isEmpty)

                quickStartActionButton("Create Proxy Manifest", systemImage: "externaldrive.badge.plus") {
                    enterEditor()
                    workspace.generateProxyManifest()
                }
                .disabled(workspace.currentProjectBundleURL == nil || workspace.project.assets.isEmpty)
                .help("Writes a proxy manifest only; no proxy media is generated in this prototype.")
            }

            HStack(spacing: 8) {
                quickStartActionButton("Open Last Export", systemImage: "arrow.up.forward.app") {
                    workspace.openLatestExport()
                }
                .disabled(workspace.exportHistory.isEmpty)

                quickStartActionButton("Reveal Last Export", systemImage: "folder") {
                    workspace.revealLatestExport()
                }
                .disabled(workspace.exportHistory.isEmpty)
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var latestAutosaveSummary: String {
        guard let autosaveURL = workspace.latestAvailableAutosaveURL ?? workspace.lastAutosaveURL else {
            return "No autosave available yet"
        }

        if let modified = try? autosaveURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            return modified.formatted(date: .abbreviated, time: .shortened)
        }

        return autosaveURL.lastPathComponent
    }

    private var recentExportsHomePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Exports")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(workspace.exportHistory.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(workspace.exportHistory.prefix(3))) { item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.sequenceName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("\(item.presetName) • \(item.resolution)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Retry") {
                        enterEditor()
                        selectedExportPresetID = item.presetID
                        workspace.retryExport(using: item)
                    }
                    .buttonStyle(.bordered)
                    Button("Open") {
                        workspace.openExportOutput(item)
                    }
                    .buttonStyle(.bordered)
                    Button("Reveal") {
                        workspace.revealExportOutput(item)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var recentProjectsHomePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Projects")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Clear") {
                    workspace.clearRecentProjects()
                }
                .buttonStyle(.bordered)
            }

            ForEach(Array(workspace.recentProjects.prefix(5))) { recent in
                let exists = FileManager.default.fileExists(atPath: recent.path)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recent.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(recentProjectDetail(recent))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !exists {
                        Text("Missing")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.32))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.16))
                            .clipShape(Capsule())
                    }
                    Button("Open") {
                        enterEditor()
                        workspace.openRecentProject(recent)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!exists)
                    Button("Reveal") {
                        workspace.revealRecentProject(recent)
                    }
                    .buttonStyle(.bordered)
                    Button("Remove") {
                        workspace.removeRecentProject(recent)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func recentProjectDetail(_ recent: EditorWorkspace.RecentProject) -> String {
        let filename = URL(fileURLWithPath: recent.path).lastPathComponent
        return "\(filename) • \(recent.lastOpened.formatted(date: .abbreviated, time: .shortened))"
    }

    private var exportSupportBanner: some View {
        HStack {
            Image(systemName: "info.circle")
            Text(workspace.exportSupportMessage)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func enterEditor() {
        workspaceStage = .editor
    }

    private func rebuildProgramPlayer() {
        #if canImport(AVKit) && canImport(AVFoundation)
        programPlayer.onTimeUpdate = { [weak workspace] seconds in
            Task { @MainActor in
                guard let workspace else { return }
                guard workspace.isPlaying else { return }
                workspace.updatePlayheadFromPlayback(seconds)
            }
        }
        programPlayer.onPlaybackEnded = { [weak workspace] in
            Task { @MainActor in
                guard let workspace else { return }
                workspace.isPlaying = false
                workspace.statusMessage = "Reached end"
            }
        }
        programPlayer.rebuild(sequence: workspace.activeSequence, assets: workspace.project.assets, fps: workspace.project.fps)
        // Keep the program player aligned to the current playhead when rebuilding.
        programPlayer.seek(to: workspace.playheadTime)
        syncProgramAudioSettings()
        syncProgramPlaybackRate()
        #endif
    }

    private func syncProgramAudioSettings() {
        #if canImport(AVKit) && canImport(AVFoundation)
        programPlayer.player.isMuted = workspace.isPreviewMuted
        programPlayer.player.volume = Float(min(1.0, max(0, workspace.previewVolume)))
        #endif
    }

    private func syncProgramPlaybackRate() {
        #if canImport(AVKit) && canImport(AVFoundation)
        guard workspace.isPlaying else { return }
        programPlayer.player.rate = Float(min(4.0, max(0.25, workspace.playbackRate)))
        #endif
    }

    private func toggleProgramPlayback() {
        if workspace.isPlaying {
            pauseProgramPlayback(userInitiated: true)
        } else {
            startProgramPlayback()
        }
    }

    private func startProgramPlayback() {
        guard let sequence = workspace.activeSequence else {
            workspace.statusMessage = "No active sequence"
            return
        }
        guard sequence.duration > 0 else {
            workspace.statusMessage = "Timeline is empty"
            return
        }
        #if canImport(AVKit) && canImport(AVFoundation)
        // Stop the legacy simulated loop by flipping the flag before real playback begins.
        workspace.isPlaying = false
        rebuildProgramPlayer()
        programPlayer.seek(to: workspace.playheadTime)
        programPlayer.play(rate: workspace.playbackRate)
        workspace.isPlaying = true
        workspace.statusMessage = "Playing"
        #else
        workspace.startPlayback()
        #endif
    }

    private func pauseProgramPlayback(userInitiated: Bool) {
        #if canImport(AVKit) && canImport(AVFoundation)
        programPlayer.pause()
        workspace.isPlaying = false
        if userInitiated {
            workspace.statusMessage = "Paused at \(workspace.timecode(workspace.playheadTime))"
        }
        #else
        workspace.pausePlayback(userInitiated: userInitiated)
        #endif
    }

    private func seekProgram(to newTime: TimeInterval) {
        let clamped = min(max(0, newTime), workspace.activeSequence?.duration ?? newTime)
        isScrubbingProgramPlayback = true
        workspace.updatePlayhead(to: clamped)
        isScrubbingProgramPlayback = false
        #if canImport(AVKit) && canImport(AVFoundation)
        programPlayer.seek(to: clamped)
        #endif
    }

    private func seekProgramBy(_ seconds: TimeInterval) {
        seekProgram(to: workspace.playheadTime + seconds)
    }

    private func stepProgramFrame(_ deltaFrames: Int) {
        let frameDuration = 1.0 / max(1, workspace.project.fps)
        seekProgram(to: workspace.playheadTime + (Double(deltaFrames) * frameDuration))
    }

    private func ensureSelectedBrowserBin() {
        guard !browserBins.isEmpty else {
            selectedBrowserBinID = nil
            editingBrowserBinID = nil
            editingBrowserBinName = ""
            return
        }
        if let selectedBrowserBinID,
           browserBins.contains(where: { $0.id == selectedBrowserBinID }) {
            return
        }
        selectedBrowserBinID = browserBins.first?.id
    }

    private func startEditingBin(_ bin: MediaBin) {
        selectedBrowserBinID = bin.id
        editingBrowserBinID = bin.id
        editingBrowserBinName = bin.name
    }

    private func commitEditingBin(_ binID: UUID) {
        workspace.renameBin(binID: binID, to: editingBrowserBinName)
        editingBrowserBinID = nil
        editingBrowserBinName = ""
    }

    private func cancelEditingBin() {
        editingBrowserBinID = nil
        editingBrowserBinName = ""
    }

    private func toggleBrowserPanelVisibility() {
        isBrowserPanelVisible.toggle()
        syncWorkspacePreset()
    }

    private func toggleInspectorPanelVisibility() {
        isInspectorPanelVisible.toggle()
        syncWorkspacePreset()
    }

    private func setInspectorPlacement(_ placement: WorkspaceLayoutSettings.InspectorPlacement) {
        inspectorPlacement = placement
    }

    private func resetWorkspaceLayoutToDefaults() {
        isBrowserPanelVisible = true
        isInspectorPanelVisible = true
        inspectorPlacement = .right
        browserTab = .media
        inspectorTab = .video
        browserPanelWidth = 290
        inspectorPanelWidth = 285
        viewerPaneHeight = 360
        viewerLayout = .auto
        trackLaneHeight = 54
        timelineZoom = 1.0
        sourceViewerZoom = 1.0
        programViewerZoom = 1.0
        leftResizeStartWidth = nil
        rightResizeStartWidth = nil
        centerResizeStartHeight = nil
        syncWorkspacePreset()
    }

    private func applyWorkspacePreset(_ preset: WorkspacePreset) {
        switch preset {
        case .editing:
            isBrowserPanelVisible = true
            isInspectorPanelVisible = true
            browserTab = .media
            inspectorTab = .video
        case .focused:
            isBrowserPanelVisible = false
            isInspectorPanelVisible = false
        case .captions:
            isBrowserPanelVisible = true
            isInspectorPanelVisible = true
            browserTab = .timelineIndex
            inspectorTab = .captions
        case .custom:
            break
        }
        syncWorkspacePreset()
    }

    private func syncWorkspacePreset() {
        if isBrowserPanelVisible && isInspectorPanelVisible {
            if browserTab == .timelineIndex && inspectorTab == .captions {
                workspacePreset = .captions
            } else {
                workspacePreset = .editing
            }
        } else if !isBrowserPanelVisible && !isInspectorPanelVisible {
            workspacePreset = .focused
        } else {
            workspacePreset = .custom
        }
        persistWorkspaceLayout()
    }

    private func restoreWorkspaceLayoutFromProject() {
        let stored = workspace.workspaceLayoutSettings
        isRestoringWorkspaceLayout = true
        isBrowserPanelVisible = stored.isBrowserPanelVisible
        isInspectorPanelVisible = stored.isInspectorPanelVisible
        inspectorPlacement = stored.inspectorPlacement
        browserTab = browserTab(from: stored.browserTab)
        inspectorTab = inspectorTab(from: stored.inspectorTab)
        browserPanelWidth = CGFloat(normalizedZoom(stored.browserPanelWidth, fallback: 290, bounds: panelWidthBounds))
        inspectorPanelWidth = CGFloat(normalizedZoom(stored.inspectorPanelWidth, fallback: 285, bounds: panelWidthBounds))
        viewerPaneHeight = CGFloat(normalizedZoom(stored.viewerPaneHeight, fallback: 360, bounds: viewerPaneHeightBounds))
        viewerLayout = stored.viewerLayout
        trackLaneHeight = CGFloat(normalizedZoom(stored.trackLaneHeight, fallback: 54, bounds: trackLaneHeightBounds))
        timelineZoom = normalizedZoom(stored.timelineZoom, fallback: 1.0, bounds: timelineZoomBounds)
        sourceViewerZoom = normalizedZoom(stored.sourceViewerZoom, fallback: 1.0, bounds: viewerZoomBounds)
        programViewerZoom = normalizedZoom(stored.programViewerZoom, fallback: 1.0, bounds: viewerZoomBounds)
        leftResizeStartWidth = nil
        rightResizeStartWidth = nil
        centerResizeStartHeight = nil
        workspacePreset = workspacePreset(from: stored.preset)
        syncWorkspacePreset()
        isRestoringWorkspaceLayout = false
    }

    private func persistWorkspaceLayout() {
        guard !isRestoringWorkspaceLayout else { return }

        let persistedSettings = WorkspaceLayoutSettings(
            preset: storedPreset(from: workspacePreset),
            isBrowserPanelVisible: isBrowserPanelVisible,
            isInspectorPanelVisible: isInspectorPanelVisible,
            browserTab: storedBrowserTab(from: browserTab),
            inspectorTab: storedInspectorTab(from: inspectorTab),
            inspectorPlacement: inspectorPlacement,
            browserPanelWidth: clamped(Double(browserPanelWidth), in: panelWidthBounds),
            inspectorPanelWidth: clamped(Double(inspectorPanelWidth), in: panelWidthBounds),
            viewerPaneHeight: clamped(Double(viewerPaneHeight), in: viewerPaneHeightBounds),
            viewerLayout: viewerLayout,
            trackLaneHeight: clamped(Double(trackLaneHeight), in: trackLaneHeightBounds),
            timelineZoom: clamped(timelineZoom, in: timelineZoomBounds),
            sourceViewerZoom: clamped(sourceViewerZoom, in: viewerZoomBounds),
            programViewerZoom: clamped(programViewerZoom, in: viewerZoomBounds)
        )

        if workspace.workspaceLayoutSettings != persistedSettings {
            workspace.updateWorkspaceLayoutSettings(persistedSettings)
        }
    }

    private func storedPreset(from preset: WorkspacePreset) -> WorkspaceLayoutSettings.Preset {
        switch preset {
        case .editing:
            return .editing
        case .focused:
            return .focused
        case .captions:
            return .captions
        case .custom:
            return .custom
        }
    }

    private func workspacePreset(from preset: WorkspaceLayoutSettings.Preset) -> WorkspacePreset {
        switch preset {
        case .editing:
            return .editing
        case .focused:
            return .focused
        case .captions:
            return .captions
        case .custom:
            return .custom
        }
    }

    private func storedBrowserTab(from tab: BrowserTab) -> WorkspaceLayoutSettings.BrowserTab {
        switch tab {
        case .libraries:
            return .libraries
        case .media:
            return .media
        case .timelineIndex:
            return .timelineIndex
        case .effects:
            return .effects
        }
    }

    private func browserTab(from tab: WorkspaceLayoutSettings.BrowserTab) -> BrowserTab {
        switch tab {
        case .libraries:
            return .libraries
        case .media:
            return .media
        case .timelineIndex:
            return .timelineIndex
        case .effects:
            return .effects
        }
    }

    private func storedInspectorTab(from tab: InspectorTab) -> WorkspaceLayoutSettings.InspectorTab {
        switch tab {
        case .video:
            return .video
        case .audio:
            return .audio
        case .captions:
            return .captions
        case .info:
            return .info
        }
    }

    private func inspectorTab(from tab: WorkspaceLayoutSettings.InspectorTab) -> InspectorTab {
        switch tab {
        case .video:
            return .video
        case .audio:
            return .audio
        case .captions:
            return .captions
        case .info:
            return .info
        }
    }

    private func normalizedZoom(
        _ value: Double,
        fallback: Double,
        bounds: ClosedRange<Double>
    ) -> Double {
        guard value.isFinite else {
            return fallback
        }
        return clamped(value, in: bounds)
    }

    private func homeCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func homeStatusRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func quickStartActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Color.white.opacity(0.28))
    }

    private var browserPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Browser")
                    .font(.headline)
                Spacer()
                if !workspace.missingAssets.isEmpty {
                    Text("\(workspace.missingAssets.count) missing")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.32))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.16))
                        .clipShape(Capsule())
                }
                Button {
                    workspace.importMediaUsingDialog()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down.on.square.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            Picker("Browser", selection: $browserTab) {
                ForEach(BrowserTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)

            if browserTab == .libraries || browserTab == .media {
                mediaBrowserContent(showBins: browserTab == .libraries)
            } else if browserTab == .timelineIndex {
                timelineIndexPanel
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    effectRow(name: "Basic Fade", detail: "Cross dissolve transition")
                    effectRow(name: "Punch In", detail: "Scale + position keyframe")
                    effectRow(name: "Voice Enhance", detail: "Noise reduction + EQ")
                }
                .padding(10)
            }

            Spacer()
        }
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }

    @ViewBuilder
    private func mediaBrowserContent(showBins: Bool) -> some View {
        if workspace.project.assets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "film.stack")
                    .font(.title)
                    .foregroundStyle(Color(red: 0.76, green: 0.76, blue: 0.80))
                Text("No media in browser")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Import clips to start building your storyline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Import Clips") {
                    workspace.importMediaUsingDialog()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(10)
        } else {
            if showBins {
                browserBinsSection
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            }

            if !workspace.missingAssets.isEmpty {
                missingMediaBanner
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            }

            HStack(spacing: 6) {
                Button("Append Selected") {
                    workspace.appendSelectedAssetToTimeline()
                }
                .buttonStyle(.borderedProminent)
                .disabled(workspace.selectedAssetID == nil)

                if showBins {
                    Button("Add To Bin") {
                        guard let selectedAssetID = workspace.selectedAssetID,
                              let selectedBrowserBinID else { return }
                        workspace.addAsset(selectedAssetID, toBin: selectedBrowserBinID)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canAddSelectedAssetToActiveBin)

                    Button("Remove") {
                        guard let selectedAssetID = workspace.selectedAssetID,
                              let selectedBrowserBinID else { return }
                        workspace.removeAsset(selectedAssetID, fromBin: selectedBrowserBinID)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canRemoveSelectedAssetFromActiveBin)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)

            if showBins,
               let selectedBrowserBin,
               browserAssets.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No assets in \(selectedBrowserBin.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Drag clips onto a bin, or use Add To Bin.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)
                .padding(.top, 2)
            }

            List(browserAssets) { asset in
                HStack(spacing: 8) {
                    Image(systemName: symbol(for: asset.type))
                        .foregroundStyle(
                            isAssetMissing(asset) ?
                            Color(red: 0.98, green: 0.78, blue: 0.32) :
                            .white.opacity(0.9)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(asset.name)
                                .foregroundStyle(.white)
                            if isAssetMissing(asset) {
                                Text("Missing")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.32))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.16))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(
                            isAssetMissing(asset) ?
                            "Offline media • \(URL(fileURLWithPath: asset.path).lastPathComponent)" :
                            "\(asset.type.rawValue.capitalized) • \(workspace.timecode(asset.duration))"
                        )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if showBins, let selectedBrowserBin {
                        Text(selectedBrowserBin.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .listRowBackground(
                    workspace.selectedAssetID == asset.id ?
                    Color.white.opacity(0.12) :
                    Color.clear
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    workspace.selectAsset(asset.id)
                }
                .onTapGesture(count: 2) {
                    workspace.selectAsset(asset.id)
                    workspace.appendAssetToTimeline(assetID: asset.id)
                }
                .contextMenu {
                    Button("Relink Media") {
                        workspace.selectAsset(asset.id)
                        workspace.relinkSelectedAssetUsingDialog()
                    }
                    if showBins, let selectedBrowserBinID {
                        Button("Add to Selected Bin") {
                            workspace.addAsset(asset.id, toBin: selectedBrowserBinID)
                        }
                    }
                    ForEach(browserBins) { bin in
                        Button("Add to \(bin.name)") {
                            workspace.addAsset(asset.id, toBin: bin.id)
                        }
                    }
                }
                .draggable(asset.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard showBins,
                          let selectedBrowserBinID,
                          let rawID = items.first,
                          let draggedID = UUID(uuidString: rawID) else {
                        return false
                    }
                    workspace.moveAsset(draggedID, inBin: selectedBrowserBinID, before: asset.id)
                    return true
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard showBins,
                      let selectedBrowserBinID,
                      let rawID = items.first,
                      let draggedID = UUID(uuidString: rawID) else {
                    return false
                }
                workspace.moveAsset(draggedID, inBin: selectedBrowserBinID, before: nil)
                return true
            }
        }
    }

    private var browserBinsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Bins")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    workspace.createBin()
                    selectedBrowserBinID = browserBins.last?.id
                } label: {
                    Label("New Bin", systemImage: "folder.badge.plus")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            if browserBins.isEmpty {
                Text("Create bins to organize imported clips.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(browserBins) { bin in
                    HStack(spacing: 8) {
                        Image(systemName: selectedBrowserBinID == bin.id ? "folder.fill" : "folder")
                            .foregroundStyle(selectedBrowserBinID == bin.id ? .yellow : .white.opacity(0.85))

                        if editingBrowserBinID == bin.id {
                            TextField("Bin Name", text: $editingBrowserBinName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    commitEditingBin(bin.id)
                                }
                            Button("Save") {
                                commitEditingBin(bin.id)
                            }
                            .buttonStyle(.bordered)
                            Button("Cancel") {
                                cancelEditingBin()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(bin.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("\(bin.assetIDs.count) assets")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                startEditingBin(bin)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.8))

                            Button(role: .destructive) {
                                workspace.deleteBin(binID: bin.id)
                                ensureSelectedBrowserBin()
                                cancelEditingBin()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                selectedBrowserBinID == bin.id ?
                                Color.white.opacity(0.12) :
                                Color.white.opacity(0.04)
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedBrowserBinID = bin.id
                        if editingBrowserBinID != bin.id {
                            cancelEditingBin()
                        }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let rawID = items.first,
                              let assetID = UUID(uuidString: rawID) else {
                            return false
                        }
                        selectedBrowserBinID = bin.id
                        workspace.addAsset(assetID, toBin: bin.id)
                        return true
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var missingMediaBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.32))
            VStack(alignment: .leading, spacing: 2) {
                Text("Missing media detected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(workspace.missingAssets.count) asset(s) need relinking before preview/export is reliable.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Relink First Missing") {
                workspace.relinkFirstMissingAssetUsingDialog()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.70, green: 0.42, blue: 0.18))
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var timelineIndexPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    TextField(
                        "Search transcript",
                        text: Binding(
                            get: { workspace.transcriptQuery },
                            set: { workspace.updateTranscriptQuery($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Scan Silence") {
                        workspace.runSilenceSuggestions()
                    }
                    .buttonStyle(.bordered)
                }

                markerIndexView
                transcriptMatchesView
                silenceSuggestionsView
            }
            .padding(10)
        }
    }

    private var markerIndexView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Markers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            let markers = (activeSequence?.markers ?? []).sorted(by: { $0.time < $1.time })
            if markers.isEmpty {
                Text("No markers.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(markers) { marker in
                    Button {
                        workspace.updatePlayhead(to: marker.time)
                    } label: {
                        HStack {
                            Text(workspace.timecode(marker.time))
                                .font(.caption2.monospacedDigit())
                            Text(marker.label)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                        }
                        .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var transcriptMatchesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transcript")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if workspace.transcriptMatches.isEmpty {
                Text("No transcript matches.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workspace.transcriptMatches) { segment in
                    Button {
                        workspace.jumpToTranscriptSegment(segment.id)
                    } label: {
                        HStack {
                            Text(workspace.timecode(segment.start))
                                .font(.caption2.monospacedDigit())
                            Text(segment.text)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                        }
                        .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var silenceSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Silence Suggestions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !workspace.silenceSuggestions.isEmpty {
                    Button("Apply All") {
                        workspace.applyAllSilenceSuggestions()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if workspace.silenceSuggestions.isEmpty {
                Text("No silence cuts suggested.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workspace.silenceSuggestions) { suggestion in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(workspace.timecode(suggestion.start)) → \(workspace.timecode(suggestion.end))")
                                .font(.caption2.monospacedDigit())
                            Text(suggestion.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Apply") {
                            workspace.applySilenceSuggestion(suggestion.id)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func topToolbar(compact: Bool) -> some View {
        VStack(spacing: 8) {
            if compact {
                HStack {
                    Text(workspace.project.name)
                        .font(.headline)
                        .foregroundStyle(.white)

                    if let url = workspace.currentProjectBundleURL {
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Unsaved")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    transportButtons(usesSpacer: false)
                        .padding(.horizontal, 2)
                }
            } else {
                HStack {
                    Text(workspace.project.name)
                        .font(.headline)
                        .foregroundStyle(.white)

                    if let url = workspace.currentProjectBundleURL {
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Unsaved")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    transportButtons()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    toolbarButton("Home", systemImage: "house") {
                        pauseProgramPlayback(userInitiated: false)
                        workspaceStage = .home
                    }
                    toolbarButton("New", systemImage: "plus.square") { workspace.createNewProject() }
                    toolbarButton("Open", systemImage: "folder") { workspace.openProjectUsingDialog() }
                    toolbarButton("Save", systemImage: "square.and.arrow.down") { workspace.saveProject() }
                    toolbarButton("Undo", systemImage: "arrow.uturn.backward") { workspace.undo() }
                        .disabled(!workspace.canUndo)
                    toolbarButton("Redo", systemImage: "arrow.uturn.forward") { workspace.redo() }
                        .disabled(!workspace.canRedo)
                    Divider().frame(height: 18)
                    toolbarButton(
                        isBrowserPanelVisible ? "Browser On" : "Browser Off",
                        systemImage: isBrowserPanelVisible ? "sidebar.left" : "sidebar.left.hide"
                    ) {
                        toggleBrowserPanelVisibility()
                    }
                    toolbarButton(
                        isInspectorPanelVisible ? "Inspector On" : "Inspector Off",
                        systemImage: isInspectorPanelVisible ? "sidebar.right" : "sidebar.right.hide"
                    ) {
                        toggleInspectorPanelVisibility()
                    }
                    Menu {
                        Button("Editing") { applyWorkspacePreset(.editing) }
                        Button("Focused") { applyWorkspacePreset(.focused) }
                        Button("Captions") { applyWorkspacePreset(.captions) }
                        Divider()
                        Button("Viewer Auto") { viewerLayout = .auto }
                        Button("Viewer Side By Side") { viewerLayout = .sideBySide }
                        Button("Viewer Stacked") { viewerLayout = .stacked }
                        Divider()
                        Button("Inspector Left") { setInspectorPlacement(.left) }
                        Button("Inspector Right") { setInspectorPlacement(.right) }
                        Divider()
                        Button("Reset") { resetWorkspaceLayoutToDefaults() }
                    } label: {
                        Label("Layout: \(workspacePreset.title)", systemImage: "rectangle.3.group")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.40, green: 0.40, blue: 0.43))
                    Divider().frame(height: 18)
                    if !workspace.project.sequences.isEmpty {
                        sequencePicker
                    }
                    toolbarButton("New Seq", systemImage: "plus.rectangle.on.folder") { workspace.createSequence() }
                    toolbarButton("Duplicate", systemImage: "doc.on.doc") { workspace.duplicateActiveSequence() }
                    Picker(
                        "Edit Mode",
                        selection: Binding(
                            get: { workspace.timelineEditMode },
                            set: { workspace.setTimelineEditMode($0) }
                        )
                    ) {
                        Text("Insert").tag(TimelineEditMode.insert)
                        Text("Overwrite").tag(TimelineEditMode.overwrite)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                    Divider().frame(height: 18)
                    toolbarButton("Import", systemImage: "tray.and.arrow.down") { workspace.importMediaUsingDialog() }
                    toolbarButton("Append", systemImage: "plus.rectangle.on.rectangle") { workspace.appendSelectedAssetToTimeline() }
                    toolbarButton("Append End", systemImage: "plus.rectangle.fill.on.rectangle.fill") { workspace.appendSelectedAssetToTimelineEnd() }
                    toolbarButton("Split", systemImage: "scissors") { workspace.splitSelectedClipAtPlayhead() }
                    toolbarButton("Delete", systemImage: "delete.left") { workspace.rippleDeleteSelectedClip() }
                    toolbarButton("Add Marker", systemImage: "bookmark") { workspace.addMarkerAtPlayhead() }
                    toolbarButton("Next Marker", systemImage: "arrow.right.to.line") { workspace.jumpToNextMarker() }
                    toolbarButton("Prev Edit", systemImage: "arrow.left.to.line") { workspace.jumpToPreviousEditPoint() }
                    toolbarButton("Next Edit", systemImage: "arrow.right.to.line") { workspace.jumpToNextEditPoint() }
                    toolbarButton("Set In", systemImage: "inset.filled.left") { workspace.setInPointAtPlayhead() }
                    toolbarButton("Set Out", systemImage: "inset.filled.right") { workspace.setOutPointAtPlayhead() }
                    toolbarButton("Clear IO", systemImage: "xmark.circle") { workspace.clearInOutPoints() }
                    toolbarButton(workspace.isLoopPlaybackEnabled ? "Loop On" : "Loop Off", systemImage: "repeat") {
                        workspace.toggleLoopPlayback()
                    }
                    Divider().frame(height: 18)
                    toolbarButton("Nudge -", systemImage: "arrow.left") { workspace.nudgeSelectedClips(by: -0.5) }
                    toolbarButton("Nudge +", systemImage: "arrow.right") { workspace.nudgeSelectedClips(by: 0.5) }
                    toolbarButton("Trim In", systemImage: "arrow.right.to.line.compact") { workspace.trimSelectedClipLeading(by: 0.1) }
                    toolbarButton("Trim Out", systemImage: "arrow.left.to.line.compact") { workspace.trimSelectedClipTrailing(by: 0.1) }
                    toolbarButton("Slip -", systemImage: "arrow.left.and.line.vertical.and.arrow.right") { workspace.slipSelectedClip(by: -0.1) }
                        .disabled(!workspace.canSlipSelectedClip)
                        .help("Slip selected clip content backward by 0.1 seconds.")
                    toolbarButton("Slip +", systemImage: "arrow.right.and.line.vertical.and.arrow.left") { workspace.slipSelectedClip(by: 0.1) }
                        .disabled(!workspace.canSlipSelectedClip)
                        .help("Slip selected clip content forward by 0.1 seconds.")
                    toolbarButton("Delete Sel", systemImage: "trash") { workspace.rippleDeleteSelectedClip() }
                    Divider().frame(height: 18)
                    toolbarButton("Captions", systemImage: "captions.bubble") { workspace.runAutoCaptions() }
                    toolbarButton("Silence", systemImage: "waveform.and.mic") { workspace.runSilenceSuggestions() }
                    toolbarButton("Reframe 9:16", systemImage: "rectangle.portrait.and.arrow.right") { workspace.applySmartReframePreset("9:16") }
                    toolbarButton("Highlights", systemImage: "sparkles") { workspace.runHighlightSuggestions() }
                    Menu {
                        ForEach(workspace.exportPresets, id: \.id) { preset in
                            Button {
                                selectedExportPresetID = preset.id
                            } label: {
                                HStack {
                                    Text(preset.name)
                                    Spacer()
                                    if selectedExportPresetID == preset.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(
                            "Preset: \(selectedExportPreset?.name ?? "Export")",
                            systemImage: "gearshape.2"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.40, green: 0.40, blue: 0.43))
                    toolbarButton(
                        "Export \(selectedExportPreset?.container.uppercased() ?? "MP4")",
                        systemImage: "square.and.arrow.up"
                    ) {
                        if workspace.canExport {
                            workspace.enqueueExport(presetID: selectedExportPreset?.id ?? "youtube-1080p-h264")
                        } else {
                            workspace.statusMessage = workspace.exportSupportMessage
                            showsExportBlockedAlert = true
                        }
                    }
                    .help(workspace.exportSupportMessage)
                    toolbarButton("Create Proxy Manifest", systemImage: "externaldrive.badge.icloud") {
                        workspace.generateProxyManifest()
                    }
                    .help("Writes proxy manifest only; actual proxy media not generated in this prototype.")
                    Menu {
                        Button("Open Export Queue Panel") { showsExportQueue = true }
                        Divider()
                        if workspace.exportProgress > 0 && workspace.exportProgress < 1 {
                            Label("\(activeExportPresetName) • \(Int(workspace.exportProgress * 100))%", systemImage: "clock")
                            Button("Cancel Current Export") { workspace.cancelExport() }
                        } else {
                            Label("No active export", systemImage: "checkmark.circle")
                        }
                        Divider()
                        Button(workspace.exportSupportMessage) {}
                            .disabled(true)
                        switch workspace.exportSupportStatus {
                        case .missingMedia:
                            Button("Relink Missing Media") { workspace.relinkFirstMissingAssetUsingDialog() }
                        case .emptySequence:
                            Button("Append First Clip") { workspace.appendFirstAssetToTimeline() }
                        case .ready, .unsupported:
                            EmptyView()
                        }
                        if let latest = workspace.exportHistory.first {
                            Button("Open Last Export") { workspace.openExportOutput(latest) }
                            Button("Reveal Last Export") { workspace.revealExportOutput(latest) }
                            Button("Retry Last Export") { workspace.retryExport(using: latest) }
                        } else {
                            Label("No previous exports", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Label("Export Queue", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.40, green: 0.40, blue: 0.43))
                    Divider().frame(height: 18)
                    Button("Mode: \(workspace.activeSequence?.mode.rawValue.capitalized ?? "N/A")") {
                        workspace.switchTimelineMode()
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.43, green: 0.43, blue: 0.45))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .background(Color(red: 0.17, green: 0.17, blue: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func transportButtons(usesSpacer: Bool = true) -> some View {
        HStack(spacing: 6) {
            tinyRoundButton("backward.end.fill") { seekProgram(to: 0) }
            tinyRoundButton("backward.frame.fill") { stepProgramFrame(-1) }
            tinyRoundButton(workspace.isPlaying ? "pause.fill" : "play.fill") { toggleProgramPlayback() }
            tinyRoundButton("forward.frame.fill") { stepProgramFrame(1) }
            tinyRoundButton("forward.end.fill") { seekProgram(to: workspace.activeSequence?.duration ?? 0) }
            tinyRoundButton("inset.filled.left") { workspace.setInPointAtPlayhead() }
            tinyRoundButton("inset.filled.right") { workspace.setOutPointAtPlayhead() }
            tinyRoundButton(workspace.isLoopPlaybackEnabled ? "repeat.circle.fill" : "repeat.circle") {
                workspace.toggleLoopPlayback()
            }
            if usesSpacer {
                Spacer()
            }
            Text(workspace.timecode(workspace.playheadTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
            Button(String(format: "%.1fx", workspace.playbackRate)) {
                workspace.cyclePlaybackRate()
            }
            .buttonStyle(.bordered)
            .font(.caption2.monospacedDigit())
        }
    }

    private var sequencePicker: some View {
        Picker(
            "Sequence",
            selection: Binding(
                get: { workspace.activeSequenceID ?? workspace.project.sequences.first?.id ?? UUID() },
                set: { workspace.setActiveSequence($0) }
            )
        ) {
            ForEach(workspace.project.sequences) { sequence in
                Text(sequence.name).tag(sequence.id)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 180)
    }

    private func viewerWorkbench(stacked: Bool) -> some View {
        Group {
            if stacked {
                VStack(spacing: 8) {
                    viewerPanel(title: "Event Viewer", subtitle: "Source", kind: .source)
                    viewerPanel(title: "Project Viewer", subtitle: "Program", kind: .program)
                }
            } else {
                HStack(spacing: 8) {
                    viewerPanel(title: "Event Viewer", subtitle: "Source", kind: .source)
                    viewerPanel(title: "Project Viewer", subtitle: "Program", kind: .program)
                }
            }
        }
    }

    private func viewerPanel(title: String, subtitle: String, kind: ViewerKind) -> some View {
        let descriptor = (kind == .source) ? sourceViewerDescriptor : programViewerDescriptor

        return VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                tinyRoundButton("plus") { adjustViewerZoom(for: kind, delta: 0.1) }
                tinyRoundButton("minus") { adjustViewerZoom(for: kind, delta: -0.1) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(red: 0.18, green: 0.18, blue: 0.19))

            ZStack(alignment: .bottomLeading) {
                viewerSurface(descriptor: descriptor, kind: kind)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(viewerZoom(for: kind))
                    .animation(.easeOut(duration: 0.12), value: viewerZoom(for: kind))
                    .clipped()

                if kind == .program, let liveCaption = activeCaptionAtPlayhead {
                    Text(liveCaption.text)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(Color.black.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 44)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.headline)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(descriptor.detail)
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.60))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(8)
            }
            .frame(minHeight: 220)

            if kind == .source {
                sourceViewerControls
            } else {
                programViewerControls
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var sourceViewerControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tinyRoundButton("backward.frame.fill") {
                    workspace.updateSourcePlayhead(to: workspace.sourcePlayheadTime - (1.0 / max(1, workspace.project.fps)))
                }
                tinyRoundButton("forward.frame.fill") {
                    workspace.updateSourcePlayhead(to: workspace.sourcePlayheadTime + (1.0 / max(1, workspace.project.fps)))
                }
                tinyRoundButton("inset.filled.left") { workspace.setSourceInPointAtPlayhead() }
                tinyRoundButton("inset.filled.right") { workspace.setSourceOutPointAtPlayhead() }
                tinyRoundButton("xmark.circle") { workspace.clearSourceInOutPoints() }
                Button("Insert") {
                    workspace.appendSelectedSourceRangeToTimeline()
                }
                .buttonStyle(.borderedProminent)
                .disabled(sourceAsset == nil)
                Button("Append End") {
                    workspace.appendSelectedAssetToTimelineEnd()
                }
                .buttonStyle(.bordered)
                .disabled(sourceAsset == nil)
                Text(workspace.timecode(workspace.sourcePlayheadTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                Slider(
                    value: Binding(
                        get: { workspace.sourcePlayheadTime },
                        set: { workspace.updateSourcePlayhead(to: $0) }
                    ),
                    in: 0...sourceAssetDuration
                )
                .frame(width: 170)
                .disabled(sourceAsset == nil)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(red: 0.18, green: 0.18, blue: 0.19))
    }

    private var programViewerControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tinyRoundButton("gobackward.10") { seekProgramBy(-10) }
                tinyRoundButton(workspace.isPlaying ? "pause.fill" : "play.fill") { toggleProgramPlayback() }
                tinyRoundButton("goforward.10") { seekProgramBy(10) }
                tinyRoundButton(workspace.isPreviewMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    workspace.togglePreviewMute()
                }
                Slider(
                    value: Binding(
                        get: { workspace.previewVolume },
                        set: { workspace.updatePreviewVolume($0) }
                    ),
                    in: 0...1
                )
                .frame(width: 72)
                Slider(
                    value: Binding(
                        get: { workspace.playheadTime },
                        set: { newValue in
                            isScrubbingProgramPlayback = true
                            workspace.updatePlayhead(to: newValue)
                            seekProgram(to: newValue)
                            isScrubbingProgramPlayback = false
                        }
                    ),
                    in: 0...max(1.0, activeSequence?.duration ?? 1.0)
                )
                .frame(width: 170)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(red: 0.18, green: 0.18, blue: 0.19))
    }

    @ViewBuilder
    private func viewerSurface(descriptor: ViewerDescriptor, kind: ViewerKind) -> some View {
        #if canImport(AVKit) && canImport(AVFoundation)
        if kind == .program {
            programViewerSurface
        } else {
            MediaViewerSurface(
                asset: descriptor.asset,
                seekTime: descriptor.seekTime,
                shouldPlay: descriptor.shouldPlay,
                playbackRate: workspace.playbackRate,
                volume: workspace.previewVolume,
                isMuted: workspace.isPreviewMuted
            )
        }
        #else
        Rectangle()
            .fill(Color.black.opacity(0.92))
            .overlay {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.55))
            }
        #endif
    }

    #if canImport(AVKit) && canImport(AVFoundation)
    private var programViewerSurface: some View {
        ZStack {
            if programPlayer.hasContent {
                VideoPlayer(player: programPlayer.player)
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.92))
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "play.rectangle")
                                .font(.system(size: 34))
                                .foregroundStyle(.white.opacity(0.55))
                            Text("No Program Clip")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Append clips to timeline to preview sequence")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .onAppear {
            rebuildProgramPlayer()
            syncProgramAudioSettings()
        }
    }
    #endif

    private var timelinePanel: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Text("Timeline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(workspace.activeSequence?.mode == .magnetic ? "Magnetic" : "Track") Mode")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Markers \(activeSequence?.markers.count ?? 0)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Edit \(workspace.timelineEditMode.rawValue.capitalized)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(workspace.timelineEditMode == .overwrite ? .orange : .secondary)
                    if let range = workspace.playbackRange {
                        Text("Range \(workspace.timecode(range.start)) - \(workspace.timecode(range.end))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(workspace.isLoopPlaybackEnabled ? .yellow : .secondary)
                    } else {
                        Text("Range unset")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("Lane \(Int(trackLaneHeight))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(trackLaneHeight) },
                            set: { trackLaneHeight = CGFloat(clamped($0, in: trackLaneHeightBounds)) }
                        ),
                        in: trackLaneHeightBounds
                    )
                    .frame(width: 90)
                    Slider(value: $timelineZoom, in: timelineZoomBounds)
                        .frame(width: 120)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(Color(red: 0.19, green: 0.19, blue: 0.20))

            if workspace.exportProgress > 0 && workspace.exportProgress < 1 {
                HStack(spacing: 8) {
                    Text("Exporting")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ProgressView(value: workspace.exportProgress)
                    Text("\(Int(workspace.exportProgress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 0.17, green: 0.17, blue: 0.18))
            }

            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 10) {
                    timelineRuler

                    if videoClips.isEmpty && audioClips.isEmpty {
                        emptyTimelinePrompt
                    }

                    laneSectionHeader(title: "Video", kind: .video, count: videoTracks.count)
                    ForEach(Array(videoTracks.enumerated()), id: \.element.id) { offset, track in
                        trackLaneHeader(
                            track: track,
                            kind: .video,
                            index: offset,
                            totalCount: videoTracks.count
                        )
                        timelineTrack(track: track, tint: Color(red: 0.90, green: 0.52, blue: 0.28), kind: .video)
                    }

                    laneSectionHeader(title: "Audio", kind: .audio, count: audioTracks.count)
                    ForEach(Array(audioTracks.enumerated()), id: \.element.id) { offset, track in
                        trackLaneHeader(
                            track: track,
                            kind: .audio,
                            index: offset,
                            totalCount: audioTracks.count
                        )
                        timelineTrack(track: track, tint: Color(red: 0.24, green: 0.62, blue: 0.76), kind: .audio)
                    }

                    HStack {
                        Text("Captions")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Segments \(captionSegments.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    captionTimelineTrack
                }
                .padding(10)
            }
            .background(Color(red: 0.16, green: 0.16, blue: 0.17))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var timelineDuration: TimeInterval {
        max(12, activeSequence?.duration ?? 0)
    }

    private var timelinePixelsPerSecond: CGFloat {
        CGFloat(74 * timelineZoom)
    }

    private var timelineCanvasWidth: CGFloat {
        max(900, CGFloat(timelineDuration) * timelinePixelsPerSecond + 120)
    }

    private var normalizedTrackLaneHeight: CGFloat {
        CGFloat(clamped(Double(trackLaneHeight), in: trackLaneHeightBounds))
    }

    private var trackClipHeight: CGFloat {
        max(28, normalizedTrackLaneHeight - 10)
    }

    private var trackClipVerticalInset: CGFloat {
        max(3, (normalizedTrackLaneHeight - trackClipHeight) / 2)
    }

    private var captionLaneHeight: CGFloat {
        max(40, normalizedTrackLaneHeight - 8)
    }

    private var captionClipHeight: CGFloat {
        max(24, captionLaneHeight - 14)
    }

    private var captionClipVerticalInset: CGFloat {
        max(4, (captionLaneHeight - captionClipHeight) / 2)
    }

    private var timelineRuler: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.04))
                .frame(width: timelineCanvasWidth, height: 24)

            if let range = workspace.playbackRange {
                Rectangle()
                    .fill(Color.yellow.opacity(0.18))
                    .frame(
                        width: max(1, xPosition(for: range.end) - xPosition(for: range.start)),
                        height: 24
                    )
                    .offset(x: xPosition(for: range.start))
            }

            let tickCount = max(1, Int(ceil(timelineDuration)))
            ForEach(0...tickCount, id: \.self) { second in
                let tickX = xPosition(for: TimeInterval(second))
                Rectangle()
                    .fill(Color.white.opacity(second % 5 == 0 ? 0.38 : 0.20))
                    .frame(width: 1, height: second % 5 == 0 ? 16 : 8)
                    .offset(x: tickX, y: 5)

                if second % 5 == 0 {
                    Text(workspace.timecode(TimeInterval(second)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .offset(x: tickX + 4, y: 0)
                }
            }

            if let range = workspace.playbackRange {
                Rectangle()
                    .fill(Color.yellow.opacity(0.95))
                    .frame(width: 2, height: 24)
                    .offset(x: xPosition(for: range.start))

                Rectangle()
                    .fill(Color.orange.opacity(0.95))
                    .frame(width: 2, height: 24)
                    .offset(x: xPosition(for: range.end))
            }

            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 2, height: 24)
                .offset(x: xPosition(for: workspace.playheadTime))
        }
        .frame(width: timelineCanvasWidth, height: 24, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { gesture in
                    workspace.updatePlayhead(to: time(atX: gesture.location.x))
                }
        )
    }

    private var emptyTimelinePrompt: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start your storyline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Append your first clip to create a magnetic timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Append Clip") {
                workspace.appendSelectedAssetToTimeline()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(width: timelineCanvasWidth)
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func laneSectionHeader(title: String, kind: TrackKind, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count) tracks")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                workspace.addTrack(kind: kind)
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
    }

    private func trackLaneHeader(
        track: TimelineTrack,
        kind: TrackKind,
        index: Int,
        totalCount: Int
    ) -> some View {
        HStack(spacing: 8) {
            Text(track.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text("\(track.clips.count) clips")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if isTrackTargeted(trackID: track.id, kind: kind) {
                Text("Target")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            Spacer()
            trackStateButton("T", isOn: isTrackTargeted(trackID: track.id, kind: kind)) {
                workspace.setTargetedTrack(track.id, kind: kind)
            }
            trackStateButton("M", isOn: track.isMuted) {
                workspace.toggleTrackMute(trackID: track.id, kind: kind)
            }
            trackStateButton("S", isOn: track.isSolo) {
                workspace.toggleTrackSolo(trackID: track.id, kind: kind)
            }
            trackStateButton("L", isOn: workspace.isTrackLocked(track.id)) {
                workspace.toggleTrackLock(trackID: track.id)
            }
            trackIconButton("arrow.up", enabled: index > 0) {
                workspace.moveTrack(trackID: track.id, kind: kind, direction: -1)
            }
            trackIconButton("arrow.down", enabled: index < totalCount - 1) {
                workspace.moveTrack(trackID: track.id, kind: kind, direction: 1)
            }
            trackIconButton("trash", enabled: totalCount > 1) {
                workspace.removeTrack(trackID: track.id, kind: kind)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: timelineCanvasWidth, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func timelineTrack(track: TimelineTrack, tint: Color, kind: TrackKind) -> some View {
        let sortedClips = track.clips.sorted(by: { $0.timelineIn < $1.timelineIn })
        let isLocked = workspace.isTrackLocked(track.id)

        return AnyView(
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(isLocked ? 0.03 : 0.04))
                    .frame(width: timelineCanvasWidth, height: normalizedTrackLaneHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { gesture in
                                if let lastMarqueeSelectionAt,
                                   Date().timeIntervalSince(lastMarqueeSelectionAt) < 0.2 {
                                    return
                                }
                                workspace.clearClipSelection()
                                workspace.updatePlayhead(to: time(atX: gesture.location.x))
                            }
                    )
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { gesture in
                                isMarqueeSelecting = true
                                updateMarqueeSelection(
                                    for: sortedClips,
                                    trackID: track.id,
                                    kind: kind,
                                    startX: gesture.startLocation.x,
                                    currentX: gesture.location.x
                                )
                            }
                            .onEnded { _ in
                                endMarqueeSelection()
                            }
                    )

                ForEach(activeSequence?.markers ?? []) { marker in
                    Rectangle()
                        .fill(Color.yellow.opacity(0.50))
                        .frame(width: 1, height: normalizedTrackLaneHeight)
                        .offset(x: xPosition(for: marker.time))
                }

                if marqueeTrackID == track.id,
                   let rect = marqueeRect(trackHeight: normalizedTrackLaneHeight) {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.08))
                        )
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }

                ForEach(sortedClips) { clip in
                    let isSelected = workspace.selectedClipIDs.contains(clip.id)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(assetName(for: clip))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                        Text("\(workspace.timecode(clip.timelineIn))  +\(workspace.timecode(clip.duration))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: clipWidth(for: clip.duration), height: trackClipHeight, alignment: .leading)
                    .background(clipFillColor(for: clip, baseTint: tint))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                workspace.selectedClipIDs.contains(clip.id) ? Color.white : Color.clear,
                                lineWidth: 1.6
                            )
                    )
                    .overlay(alignment: .leading) {
                        if !isLocked {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.55))
                                .frame(width: 4, height: max(16, trackClipHeight - 10))
                                .padding(.leading, 2)
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onEnded { gesture in
                                            workspace.selectClip(clip.id)
                                            let delta = snappedTimelineDelta(for: gesture.translation.width)
                                            workspace.trimSelectedClipLeading(by: delta)
                                        }
                                )
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if !isLocked {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.55))
                                .frame(width: 4, height: max(16, trackClipHeight - 10))
                                .padding(.trailing, 2)
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onEnded { gesture in
                                            workspace.selectClip(clip.id)
                                            let delta = snappedTimelineDelta(for: gesture.translation.width)
                                            workspace.trimSelectedClipTrailing(by: delta)
                                        }
                                )
                        }
                    }
                    .offset(
                        x: xPosition(for: clip.timelineIn) + (
                            (isGroupDragging && isSelected) || draggingClipID == clip.id ? dragTranslationX : 0
                        ),
                        y: trackClipVerticalInset
                    )
                    .onTapGesture {
                        workspace.selectClip(clip.id)
                    }
                    .contextMenu {
                        Button("Split At Playhead") {
                            workspace.selectClip(clip.id)
                            workspace.splitSelectedClipAtPlayhead()
                        }
                        Divider()
                        Button("Nudge Left") {
                            workspace.selectClip(clip.id)
                            workspace.nudgeSelectedClip(by: -0.5)
                        }
                        Button("Nudge Right") {
                            workspace.selectClip(clip.id)
                            workspace.nudgeSelectedClip(by: 0.5)
                        }
                        Divider()
                        Button("Trim Start +0.1s") {
                            workspace.selectClip(clip.id)
                            workspace.trimSelectedClipLeading(by: 0.1)
                        }
                        Button("Trim End +0.1s") {
                            workspace.selectClip(clip.id)
                            workspace.trimSelectedClipTrailing(by: 0.1)
                        }
                        Divider()
                        Button("Ripple Delete", role: .destructive) {
                            workspace.selectClip(clip.id)
                            workspace.rippleDeleteSelectedClip()
                        }
                    }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { gesture in
                                guard !isLocked else { return }
                                if isSelected {
                                    workspace.selectClips(Array(workspace.selectedClipIDs), primary: clip.id)
                                } else {
                                    workspace.selectClip(clip.id)
                                }
                                draggingClipID = clip.id
                                dragTranslationX = gesture.translation.width
                                isGroupDragging = workspace.selectedClipIDs.count > 1
                            }
                            .onEnded { gesture in
                                guard !isLocked else {
                                    draggingClipID = nil
                                    dragTranslationX = 0
                                    isGroupDragging = false
                                    return
                                }
                                let seconds = snappedTimelineDelta(for: gesture.translation.width)
                                if isGroupDragging {
                                    workspace.nudgeSelectedClips(by: seconds)
                                } else {
                                    workspace.selectClip(clip.id)
                                    workspace.nudgeSelectedClip(by: seconds)
                                }
                                draggingClipID = nil
                                dragTranslationX = 0
                                isGroupDragging = false
                            }
                    )
                }

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(6)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .offset(x: 6, y: 6)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2, height: normalizedTrackLaneHeight)
                    .offset(x: xPosition(for: workspace.playheadTime))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isTrackTargeted(trackID: track.id, kind: kind) ? Color.yellow.opacity(0.75) : Color.clear,
                        lineWidth: 1.4
                    )
            )
            .frame(width: timelineCanvasWidth, height: normalizedTrackLaneHeight, alignment: .leading)
            .dropDestination(for: String.self) { items, location in
                guard let rawID = items.first,
                      let assetID = UUID(uuidString: rawID) else {
                    return false
                }
                workspace.selectAsset(assetID)
                workspace.setTargetedTrack(track.id, kind: kind)
                workspace.insertAssetToTimeline(assetID: assetID, at: time(atX: location.x))
                return true
            }
        )
    }

    private func isTrackTargeted(trackID: UUID, kind: TrackKind) -> Bool {
        switch kind {
        case .video:
            return workspace.targetedVideoTrackID == trackID
        case .audio:
            return workspace.targetedAudioTrackID == trackID
        }
    }

    private func trackStateButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .frame(width: 22, height: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? .black : .white.opacity(0.85))
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isOn ? Color.yellow.opacity(0.95) : Color.white.opacity(0.08))
        )
    }

    private func trackIconButton(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.bold())
                .frame(width: 20, height: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .white.opacity(0.85) : .white.opacity(0.35))
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(enabled ? 0.08 : 0.04))
        )
        .allowsHitTesting(enabled)
    }

    private var captionTimelineTrack: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.04))
                .frame(width: timelineCanvasWidth, height: captionLaneHeight)

            ForEach(captionSegments) { segment in
                Text(segment.text)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.90))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: max(48, clipWidth(for: segment.end - segment.start)), height: captionClipHeight, alignment: .leading)
                    .background(
                        workspace.selectedCaptionSegmentID == segment.id ?
                        Color(red: 0.95, green: 0.82, blue: 0.34).opacity(0.85) :
                        Color(red: 0.67, green: 0.58, blue: 0.23).opacity(0.65)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .offset(x: xPosition(for: segment.start), y: captionClipVerticalInset)
                    .onTapGesture {
                        workspace.jumpToTranscriptSegment(segment.id)
                    }
            }

            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 2, height: captionLaneHeight)
                .offset(x: xPosition(for: workspace.playheadTime))
        }
        .frame(width: timelineCanvasWidth, height: captionLaneHeight, alignment: .leading)
    }

    private func clipWidth(for duration: TimeInterval) -> CGFloat {
        max(56, CGFloat(duration) * timelinePixelsPerSecond)
    }

    private func xPosition(for time: TimeInterval) -> CGFloat {
        CGFloat(max(0, time)) * timelinePixelsPerSecond
    }

    private func time(atX xPosition: CGFloat) -> TimeInterval {
        guard timelinePixelsPerSecond > 0 else { return 0 }
        return TimeInterval(max(0, xPosition / timelinePixelsPerSecond))
    }

    private func marqueeRect(trackHeight: CGFloat) -> CGRect? {
        guard let startX = marqueeStartX, let currentX = marqueeCurrentX else {
            return nil
        }
        let clampedStart = min(max(0, startX), timelineCanvasWidth)
        let clampedCurrent = min(max(0, currentX), timelineCanvasWidth)
        let minX = min(clampedStart, clampedCurrent)
        let maxX = max(clampedStart, clampedCurrent)
        return CGRect(x: minX, y: 0, width: max(1, maxX - minX), height: trackHeight)
    }

    private func updateMarqueeSelection(
        for clips: [ClipRef],
        trackID: UUID,
        kind: TrackKind,
        startX: CGFloat,
        currentX: CGFloat
    ) {
        marqueeTrackID = trackID
        marqueeTrackKind = kind
        marqueeStartX = startX
        marqueeCurrentX = currentX

        let minX = min(startX, currentX)
        let maxX = max(startX, currentX)
        let startTime = time(atX: minX)
        let endTime = time(atX: maxX)

        let selected = clips
            .filter { $0.timelineIn < endTime && $0.outTime > startTime }
            .map(\.id)
        workspace.selectClips(selected, primary: selected.first)
    }

    private func endMarqueeSelection() {
        marqueeStartX = nil
        marqueeCurrentX = nil
        marqueeTrackID = nil
        marqueeTrackKind = nil
        isMarqueeSelecting = false
        lastMarqueeSelectionAt = Date()
    }

    private func snappedTimelineDelta(for translationX: CGFloat) -> TimeInterval {
        guard timelinePixelsPerSecond > 0 else { return 0 }
        let rawSeconds = TimeInterval(translationX / timelinePixelsPerSecond)
        let frameDuration = 1.0 / max(1, workspace.project.fps)
        return (rawSeconds / frameDuration).rounded() * frameDuration
    }

    private func assetName(for clip: ClipRef) -> String {
        workspace.project.assets.first(where: { $0.id == clip.assetID })?.name ?? "Clip"
    }

    private func captionText(for segmentID: UUID) -> String {
        captionSegments.first(where: { $0.id == segmentID })?.text ?? ""
    }

    private var inspectorPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Inspector")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                tinyRoundButton("arrow.counterclockwise") { workspace.resetSelectedClipAdjustments() }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            Picker("Inspector", selection: $inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if inspectorTab == .video {
                        videoInspectorControls
                    } else if inspectorTab == .audio {
                        audioInspectorControls
                    } else if inspectorTab == .captions {
                        captionsInspectorControls
                    } else {
                        inspectorGroup("Project", rows: [
                            ("FPS", String(format: "%.0f", workspace.project.fps)),
                            ("Color Space", workspace.project.colorSpace),
                            ("Schema", "v\(workspace.project.schemaVersion)")
                        ])
                        inspectorGroup("Sequence", rows: [
                            ("Video Clips", "\(videoClips.count)"),
                            ("Audio Clips", "\(audioClips.count)"),
                            ("Captions", "\(captionSegments.count)"),
                            ("Duration", workspace.timecode(activeSequence?.duration ?? 0)),
                            ("Markers", "\(activeSequence?.markers.count ?? 0)"),
                            ("Missing Media", "\(workspace.missingAssets.count)")
                        ])
                        if let selectedClip = workspace.selectedClip {
                            inspectorGroup("Selected Clip", rows: [
                                ("ID", String(selectedClip.id.uuidString.prefix(8)) + "..."),
                                ("Start", workspace.timecode(selectedClip.timelineIn)),
                                ("Duration", workspace.timecode(selectedClip.duration))
                            ])
                        }
                        inspectorGroup("Export Queue", rows: [
                            ("Preset", activeExportPresetName),
                            ("Status", workspace.exportStatusMessage),
                            ("Progress", "\(Int(workspace.exportProgress * 100))%"),
                            ("Completed", "\(workspace.exportHistory.count)")
                        ])
                        exportHistoryPanel
                    }

                    if let artifact = workspace.lastAIArtifact {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Latest AI")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(artifact.taskType.rawValue)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(10)
            }
        }
    }

    private var videoInspectorControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if workspace.selectedClipTrackKind == .video, let clip = workspace.selectedClip {
                sliderRow(
                    title: "Position X",
                    value: clip.transforms.positionX,
                    range: -200...200
                ) { workspace.updateSelectedClipPositionX($0) }

                sliderRow(
                    title: "Position Y",
                    value: clip.transforms.positionY,
                    range: -200...200
                ) { workspace.updateSelectedClipPositionY($0) }

                sliderRow(
                    title: "Scale",
                    value: clip.transforms.scaleX,
                    range: 0.1...2.5
                ) { workspace.updateSelectedClipScale($0) }

                sliderRow(
                    title: "Opacity",
                    value: clip.transforms.opacity,
                    range: 0...1
                ) { workspace.updateSelectedClipOpacity($0) }
            } else {
                inspectorHint("Select a video clip in timeline to edit transform and opacity.")
            }
        }
    }

    private var audioInspectorControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if workspace.selectedClip != nil {
                sliderRow(
                    title: "Clip Gain",
                    value: workspace.selectedClip?.gain ?? 1.0,
                    range: 0...2
                ) { workspace.updateSelectedClipGain($0) }
                inspectorGroup("Audio Enhancements", rows: [
                    ("Noise Removal", "Basic"),
                    ("Ducking", "Voice Over")
                ])
            } else {
                inspectorHint("Select any clip to edit gain.")
            }
        }
    }

    private var captionsInspectorControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button("Generate Captions") {
                    workspace.runAutoCaptions()
                }
                .buttonStyle(.borderedProminent)

                Button("Find Silence") {
                    workspace.runSilenceSuggestions()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 6) {
                Button("9:16") { workspace.applySmartReframePreset("9:16") }
                    .buttonStyle(.bordered)
                Button("1:1") { workspace.applySmartReframePreset("1:1") }
                    .buttonStyle(.bordered)
                Button("16:9") { workspace.applySmartReframePreset("16:9") }
                    .buttonStyle(.bordered)
            }

            TextField(
                "Search transcript",
                text: Binding(
                    get: { workspace.transcriptQuery },
                    set: { workspace.updateTranscriptQuery($0) }
                )
            )
            .textFieldStyle(.roundedBorder)

            if workspace.transcriptMatches.isEmpty {
                inspectorHint("No captions yet. Generate captions to edit transcript.")
            } else {
                ForEach(workspace.transcriptMatches) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(workspace.timecode(segment.start)) - \(workspace.timecode(segment.end))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Jump") {
                                workspace.jumpToTranscriptSegment(segment.id)
                            }
                            .buttonStyle(.bordered)
                        }

                        TextField(
                            "Caption",
                            text: Binding(
                                get: { captionText(for: segment.id) },
                                set: { workspace.updateCaptionSegmentText(segment.id, text: $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func sliderRow(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range
            )
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func inspectorHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func inspectorGroup(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text(row.1)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var exportHistoryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Export Queue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(workspace.exportHistory.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if workspace.exportProgress > 0 && workspace.exportProgress < 1 {
                HStack(spacing: 8) {
                    Text(activeExportPresetName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    ProgressView(value: workspace.exportProgress)
                    Text("\(Int(workspace.exportProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button("Cancel") {
                        workspace.cancelExport()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No active export")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(workspace.exportSupportMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    exportSupportActionRow
                }
            }

            Divider()

            if workspace.exportHistory.isEmpty {
                Text("Completed exports will appear here with retry and open actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(workspace.exportHistory.prefix(6))) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.sequenceName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("\(item.presetName) • \(item.resolution) • \(item.container.uppercased())")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(item.completedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: 6) {
                            Button("Retry") {
                                retryExportHistory(item)
                            }
                            .buttonStyle(.bordered)

                            Button("Open") {
                                workspace.openExportOutput(item)
                            }
                            .buttonStyle(.bordered)

                            Button("Reveal") {
                                workspace.revealExportOutput(item)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var exportQueueSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Export Queue")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { showsExportQueue = false }
                    .buttonStyle(.bordered)
            }

            if workspace.exportProgress > 0 && workspace.exportProgress < 1 {
                HStack(spacing: 10) {
                    Text(activeExportPresetName)
                        .font(.caption.weight(.semibold))
                    Text(workspace.exportStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: workspace.exportProgress)
                    Text("\(Int(workspace.exportProgress * 100))%")
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Button("Cancel Export") { workspace.cancelExport() }
                        .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No active export")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(workspace.exportSupportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    exportSupportActionRow
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if workspace.exportHistory.isEmpty {
                        Text("Completed exports will appear here with retry and open actions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(workspace.exportHistory) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.sequenceName)
                                            .font(.caption.weight(.semibold))
                                        Text("\(item.presetName) • \(item.resolution) • \(item.container.uppercased())")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(item.completedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }

                                HStack(spacing: 6) {
                                    Button("Retry") { retryExportHistory(item) }
                                        .buttonStyle(.bordered)
                                    Button("Open") { workspace.openExportOutput(item) }
                                        .buttonStyle(.bordered)
                                    Button("Reveal") { workspace.revealExportOutput(item) }
                                        .buttonStyle(.bordered)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 380)
    }

    @ViewBuilder
    private var exportSupportActionRow: some View {
        switch workspace.exportSupportStatus {
        case .missingMedia:
            Button("Relink Missing Media") {
                workspace.relinkFirstMissingAssetUsingDialog()
            }
            .buttonStyle(.bordered)
        case .emptySequence:
            Button("Append First Clip") {
                workspace.appendFirstAssetToTimeline()
            }
            .buttonStyle(.bordered)
        case .ready, .unsupported:
            EmptyView()
        }
    }

    private func retryExportHistory(_ item: EditorWorkspace.ExportHistoryItem) {
        if workspace.activeSequenceID != item.sequenceID {
            workspace.setActiveSequence(item.sequenceID)
        }
        selectedExportPresetID = item.presetID
        workspace.retryExport(using: item)
    }

    private func effectRow(name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func clipFillColor(for clip: ClipRef, baseTint: Color) -> Color {
        if workspace.selectedClipID == clip.id {
            return baseTint.opacity(1.0)
        }
        if workspace.selectedClipIDs.contains(clip.id) {
            return baseTint.opacity(0.88)
        }
        return baseTint.opacity(0.78)
    }

    private func tinyRoundButton(_ systemImage: String, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: systemImage)
                .font(.caption.bold())
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(action == nil ? 0.58 : 0.82))
        .allowsHitTesting(action != nil)
        .background(
            Circle()
                .fill(Color.white.opacity(action == nil ? 0.05 : 0.08))
                .frame(width: 20, height: 20)
        )
    }

    private func toolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(Color(red: 0.40, green: 0.40, blue: 0.43))
    }

    private func symbol(for type: MediaAsset.AssetType) -> String {
        switch type {
        case .video:
            return "video.fill"
        case .audio:
            return "waveform"
        case .image:
            return "photo.fill"
        case .unknown:
            return "questionmark.square.fill"
        }
    }

    private var bottomBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Text(workspace.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))

                if let autosaveURL = workspace.lastAutosaveURL {
                    Text("Autosave: \(autosaveURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let sequence = workspace.activeSequence {
                    Text("Sequence: \(sequence.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let selectedAssetID = workspace.selectedAssetID,
                   let asset = workspace.project.assets.first(where: { $0.id == selectedAssetID }) {
                    Text("Asset: \(asset.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let selectedClip = workspace.selectedClip {
                    Text("Clip @ \(workspace.timecode(selectedClip.timelineIn))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(workspace.isPlaying ? "Playback: Playing" : "Playback: Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Layout: \(workspacePreset.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Panels B:\(isBrowserPanelVisible ? "On" : "Off") I:\(isInspectorPanelVisible ? "On" : "Off")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Inspector Side: \(inspectorPlacement == .left ? "Left" : "Right")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Viewer H: \(Int(viewerPaneHeight))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Viewer Layout: \(viewerLayoutTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Track H: \(Int(trackLaneHeight))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Export Preset: \(selectedExportPreset?.name ?? "Default")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Speed: \(String(format: "%.1fx", workspace.playbackRate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Edit: \(workspace.timelineEditMode.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundStyle(workspace.timelineEditMode == .overwrite ? .orange : .secondary)

                if let videoTargetID = workspace.targetedVideoTrackID,
                   let videoName = activeSequence?.videoTracks.first(where: { $0.id == videoTargetID })?.name {
                    Text("V Target: \(videoName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let audioTargetID = workspace.targetedAudioTrackID,
                   let audioName = activeSequence?.audioTracks.first(where: { $0.id == audioTargetID })?.name {
                    Text("A Target: \(audioName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(workspace.isPreviewMuted ? "Muted" : "Vol \(Int(workspace.previewVolume * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let range = workspace.playbackRange {
                    Text("I/O: \(workspace.timecode(range.start))-\(workspace.timecode(range.end))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(workspace.isLoopPlaybackEnabled ? .yellow : .secondary)
                }

                Text("Export: \(workspace.exportStatusMessage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Shortcut Profile: Final Cut-like (simplified)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var shortcutsOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyboard Shortcuts")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Cmd+N  New Project")
            Text("Cmd+O  Open Project")
            Text("Cmd+S  Save Project")
            Text("Cmd+I  Import Media")
            Text("Cmd+E  Append Selected Asset")
            Text("Cmd+\\  Split Selected Clip")
            Text("Cmd+Shift+Delete  Ripple Delete Selected")
            Text("Space  Play/Pause")
            Text(", / .  Step Frame Back/Forward")
            Text("J / K / L  Shuttle Back / Stop / Play")
            Text("Cmd+Shift+W  Toggle Insert/Overwrite")
            Text("Cmd+Opt+Shift+V / A  Add Video/Audio Track")
            Text("Drag Browser clip onto Timeline to insert at drop point")
            Text("Drag clip edges in timeline lanes to trim In/Out")
            Text("Libraries tab: drag clips onto bins to organize media")
            Text("Missing media banner: use Relink First Missing to restore previews")
            Text("Use Event Viewer In/Out + Insert for subclip editing")
            Text("Toolbar Edit Mode: Insert / Overwrite")
            Text("Timeline lane buttons: Target / Mute / Solo / Lock")
            Text("Drag panel dividers to resize side panes and viewer/timeline split")
            Text("Alt+Left/Right  Prev/Next Edit")
            Text("Cmd+Left/Right  Start/End")
            Text("I / O  Set In / Out")
            Text("Cmd+Shift+X  Clear In/Out")
            Text("Cmd+Shift+L  Toggle Loop Playback")
            Text("Cmd+Shift+P  Cycle Playback Speed")
            Text("Cmd+Shift+U  Toggle Preview Mute")
            Text("Cmd+Shift+M  Toggle Timeline Mode")
            Text("Cmd+Opt+B  Toggle Browser Panel")
            Text("Cmd+Opt+I  Toggle Inspector Panel")
            Text("Cmd+Opt+[ / ]  Move Inspector Left / Right")
            Text("Cmd+Opt+1/2/3  Editing / Focused / Captions Layout")
            Text("Cmd+Opt+0  Reset Workspace Layout")
            Text("Cmd+/  Toggle This Help")
        }
        .font(.caption)
        .padding(10)
        .background(Color.black.opacity(0.88))
        .cornerRadius(8)
        .shadow(radius: 8)
        .foregroundStyle(.white.opacity(0.85))
    }
}

#if canImport(AVKit) && canImport(AVFoundation)
final class TimelineProgramPlayer: ObservableObject {
    @Published var player: AVPlayer
    @Published var hasContent: Bool = false

    var onTimeUpdate: (@Sendable (TimeInterval) -> Void)?
    var onPlaybackEnded: (@Sendable () -> Void)?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var lastSignature: String = ""

    init() {
        let player = AVPlayer()
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    @MainActor
    func rebuild(sequence: EditorSequence?, assets: [MediaAsset], fps: Double) {
        guard let sequence else {
            clear()
            return
        }

        let videoClips = (sequence.videoTracks.first?.clips ?? []).sorted(by: { $0.timelineIn < $1.timelineIn })
        guard !videoClips.isEmpty else {
            clear()
            return
        }

        let assetByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let signature = TimelineProgramPlayer.signature(sequenceID: sequence.id, clips: videoClips, assetByID: assetByID)
        if signature == lastSignature, player.currentItem != nil {
            return
        }

        let composition = AVMutableComposition()
        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var insertedAny = false

        for clip in videoClips {
            guard let asset = assetByID[clip.assetID] else { continue }
            let url = URL(fileURLWithPath: asset.path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path()) else { continue }

            let avAsset = AVAsset(url: url)
            guard let sourceVideoTrack = avAsset.tracks(withMediaType: .video).first else { continue }

            let clipStart = CMTime(seconds: max(0, clip.inTime), preferredTimescale: 600)
            let clipDuration = CMTime(seconds: max(0, clip.duration), preferredTimescale: 600)
            guard clipDuration > .zero else { continue }

            let sourceRange = CMTimeRange(start: clipStart, duration: clipDuration)
            let insertAt = CMTime(seconds: max(0, clip.timelineIn), preferredTimescale: 600)

            do {
                try compositionVideoTrack?.insertTimeRange(sourceRange, of: sourceVideoTrack, at: insertAt)
                insertedAny = true
            } catch {
                continue
            }

            if let sourceAudioTrack = avAsset.tracks(withMediaType: .audio).first {
                do {
                    try compositionAudioTrack?.insertTimeRange(sourceRange, of: sourceAudioTrack, at: insertAt)
                } catch {
                    // Audio is optional for preview.
                }
            }
        }

        guard insertedAny else {
            clear()
            return
        }

        let item = AVPlayerItem(asset: composition)
        item.audioTimePitchAlgorithm = .timeDomain

        player.replaceCurrentItem(with: item)
        attachObservers(fps: fps)
        lastSignature = signature
        hasContent = true
    }

    @MainActor
    func seek(to seconds: TimeInterval) {
        guard player.currentItem != nil else { return }
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    @MainActor
    func play(rate: Double) {
        guard player.currentItem != nil else { return }
        player.play()
        player.rate = Float(min(4.0, max(0.25, rate)))
    }

    @MainActor
    func pause() {
        player.pause()
    }

    private func clear() {
        player.replaceCurrentItem(with: nil)
        hasContent = false
        lastSignature = ""
    }

    @MainActor
    private func attachObservers(fps: Double) {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        let requested = fps.isFinite ? fps : 30
        let clampedFPS = Int(max(10, min(60, requested)))
        let interval = CMTime(seconds: 1.0 / Double(clampedFPS), preferredTimescale: 600)

        let timeHandler = onTimeUpdate
        let endHandler = onPlaybackEnded

        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            timeHandler?(seconds)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            endHandler?()
        }
    }

    private static func signature(
        sequenceID: UUID,
        clips: [ClipRef],
        assetByID: [UUID: MediaAsset]
    ) -> String {
        var parts: [String] = [sequenceID.uuidString]
        parts.reserveCapacity(1 + clips.count)
        for clip in clips {
            let path = assetByID[clip.assetID]?.path ?? "missing"
            parts.append("\(clip.id.uuidString)|\(clip.assetID.uuidString)|\(clip.timelineIn)|\(clip.inTime)|\(clip.outTime)|\(path)")
        }
        return parts.joined(separator: ";")
    }
}

private struct MediaViewerSurface: View {
    let asset: MediaAsset?
    let seekTime: TimeInterval?
    let shouldPlay: Bool
    let playbackRate: Double
    let volume: Double
    let isMuted: Bool

    @State private var player: AVPlayer?
    @State private var loadedAssetID: UUID?
    @State private var previewImage: NSImage?
    @State private var previewMessage: String?
    @State private var lastPreviewTime: TimeInterval?
    private let stagingRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("PremierCloneImports", isDirectory: true)

    var body: some View {
        ZStack {
            if let asset {
                switch asset.type {
                case .image:
                    imagePreview(path: asset.path)
                case .video:
                    if shouldPlay, let player {
                        VideoPlayer(player: player)
                    } else if let previewImage {
                        Image(nsImage: previewImage)
                            .resizable()
                            .scaledToFit()
                    } else if let player {
                        VideoPlayer(player: player)
                    } else {
                        placeholder(symbol: "play.rectangle", message: previewMessage ?? "Video preview unavailable")
                    }
                case .audio:
                    audioPreview(name: asset.name)
                case .unknown:
                    placeholder(symbol: "questionmark.square", message: "Unsupported media type")
                }
            } else {
                placeholder(symbol: "film", message: "No media loaded")
            }
        }
        .background(Color.black.opacity(0.92))
        .onAppear {
            configurePlayerIfNeeded(force: true)
            syncSeek(force: true)
            refreshPreviewImage()
            syncAudioSettings()
            syncPlayback()
        }
        .onChange(of: asset?.id) { _ in
            configurePlayerIfNeeded(force: true)
            syncSeek(force: true)
            refreshPreviewImage()
            syncAudioSettings()
            syncPlayback()
        }
        .onChange(of: seekTime) { _ in
            syncSeek(force: false)
            if !shouldPlay {
                refreshPreviewImage()
            }
        }
        .onChange(of: shouldPlay) { _ in
            syncPlayback()
        }
        .onChange(of: playbackRate) { _ in
            syncPlayback()
        }
        .onChange(of: volume) { _ in
            syncAudioSettings()
        }
        .onChange(of: isMuted) { _ in
            syncAudioSettings()
        }
        .onDisappear {
            player?.pause()
        }
    }

    @ViewBuilder
    private func imagePreview(path: String) -> some View {
        #if canImport(AppKit)
        if let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            placeholder(symbol: "photo", message: "Image preview unavailable")
        }
        #else
        placeholder(symbol: "photo", message: "Image preview unavailable")
        #endif
    }

    private func audioPreview(name: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.72))
            Text(name)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Text("Audio-only clip")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func configurePlayerIfNeeded(force: Bool) {
        guard let asset else {
            player?.pause()
            player = nil
            loadedAssetID = nil
            previewImage = nil
            previewMessage = nil
            return
        }

        if asset.type == .image || asset.type == .unknown {
            player?.pause()
            player = nil
            loadedAssetID = nil
            previewImage = nil
            return
        }

        if !force, loadedAssetID == asset.id, player != nil {
            return
        }

        guard let mediaURL = resolvedPreviewURL(for: asset) else {
            player?.pause()
            player = nil
            loadedAssetID = nil
            previewImage = nil
            previewMessage = "Missing file: \(URL(fileURLWithPath: asset.path).lastPathComponent)"
            return
        }

        let item = AVPlayerItem(url: mediaURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .pause
        newPlayer.automaticallyWaitsToMinimizeStalling = false

        player?.pause()
        player = newPlayer
        loadedAssetID = asset.id
        previewMessage = nil
        syncAudioSettings()
    }

    private func syncSeek(force: Bool) {
        guard let player, let seekTime else { return }
        if shouldPlay && !force {
            return
        }

        let time = CMTime(seconds: max(0, seekTime), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func syncPlayback() {
        guard let player else { return }
        if shouldPlay {
            player.play()
            player.rate = Float(min(4.0, max(0.25, playbackRate)))
        } else {
            player.pause()
        }
    }

    private func syncAudioSettings() {
        guard let player else { return }
        player.isMuted = isMuted
        player.volume = Float(min(1.0, max(0, volume)))
    }

    private func refreshPreviewImage() {
        if shouldPlay {
            return
        }

        guard let asset, asset.type == .video else {
            previewImage = nil
            return
        }

        let targetTime = max(0, seekTime ?? 0)
        if let lastPreviewTime, abs(lastPreviewTime - targetTime) < 0.03 {
            return
        }
        lastPreviewTime = targetTime

        guard let url = resolvedPreviewURL(for: asset) else {
            previewImage = nil
            previewMessage = "Missing file: \(URL(fileURLWithPath: asset.path).lastPathComponent)"
            return
        }

        let assetResource = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: assetResource)
        generator.appliesPreferredTrackTransform = true

        let desiredTime = CMTime(seconds: targetTime, preferredTimescale: 600)

        if let generated = try? generator.copyCGImage(at: desiredTime, actualTime: nil) {
            previewImage = NSImage(cgImage: generated, size: .zero)
            previewMessage = nil
            return
        }

        if let generatedStart = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            previewImage = NSImage(cgImage: generatedStart, size: .zero)
            previewMessage = nil
            return
        }

        previewImage = nil
        previewMessage = "Unable to decode preview frame"
    }

    private func resolvedPreviewURL(for asset: MediaAsset) -> URL? {
        let sourceURL = URL(fileURLWithPath: asset.path)
        let manager = FileManager.default
        guard manager.fileExists(atPath: sourceURL.path) else { return nil }

        do {
            if !manager.fileExists(atPath: stagingRootURL.path) {
                try manager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)
            }

            let stagedURL = stagingDestination(for: sourceURL, in: stagingRootURL)
            if !manager.fileExists(atPath: stagedURL.path) {
                try manager.copyItem(at: sourceURL, to: stagedURL)
            }
            return stagedURL
        } catch {
            // Fall back to original if staging fails.
            return sourceURL
        }
    }

    private func stagingDestination(for sourceURL: URL, in root: URL) -> URL {
        let safeBase = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
        let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension.lowercased()
        let attributes = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)) ?? [:]
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let signature = "\(size)-\(Int(modified))"
        return root.appendingPathComponent("\(safeBase)-\(signature).\(ext)", isDirectory: false)
    }

    private func placeholder(symbol: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.6))
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }
}
#endif
    public enum ExportSupportStatus: Equatable {
        case ready
        case unsupported(String)
        case missingMedia(String)
        case emptySequence
    }
