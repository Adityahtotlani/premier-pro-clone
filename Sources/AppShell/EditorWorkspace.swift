import Foundation
import SwiftUI
import ProjectCore
import TimelineCore
import PlaybackCore
import RenderCore
import AICore
import IOAdapters

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
    public static let appendFirstAsset = Notification.Name("EditorCommand.appendFirstAsset")
    public static let splitFirstClip = Notification.Name("EditorCommand.splitFirstClip")
    public static let rippleDeleteFirstClip = Notification.Name("EditorCommand.rippleDeleteFirstClip")
    public static let newSequence = Notification.Name("EditorCommand.newSequence")
    public static let duplicateSequence = Notification.Name("EditorCommand.duplicateSequence")
    public static let addMarker = Notification.Name("EditorCommand.addMarker")
    public static let nextMarker = Notification.Name("EditorCommand.nextMarker")
    public static let toggleTimelineMode = Notification.Name("EditorCommand.toggleTimelineMode")
    public static let toggleShortcutHelp = Notification.Name("EditorCommand.toggleShortcutHelp")

    public static func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

@MainActor
public final class EditorWorkspace: ObservableObject {
    @Published public var project: Project
    @Published public var statusMessage: String
    @Published public var lastAIArtifact: AIArtifact?
    @Published public var activeSequenceID: UUID?
    @Published public var selectedAssetID: UUID?
    @Published public var selectedClipID: UUID?
    @Published public var currentProjectBundleURL: URL?
    @Published public var lastAutosaveURL: URL?
    @Published public var playheadTime: TimeInterval
    @Published public var showsShortcutHelp: Bool
    @Published public var exportProgress: Double
    @Published public var exportStatusMessage: String
    @Published public var completedExports: [RenderJob]

    public let timelineEngine: TimelineEngine
    public let playbackEngine: PlaybackEngine
    public let renderEngine: RenderEngine
    public let aiService: AIAssistService

    private let projectStore: ProjectStore
    private let mediaImporter: MediaImporter
    private let proxyManager: ProxyManager
    private var autosaveTimer: Timer?
    private var exportProgressTask: Task<Void, Never>?

    public init(
        project: Project = ProjectFactory.starterProject(name: "Untitled Project"),
        timelineEngine: TimelineEngine = TimelineEngine(),
        playbackEngine: PlaybackEngine = PlaybackEngine(),
        renderEngine: RenderEngine = RenderEngine(),
        aiService: AIAssistService = AIAssistService(),
        projectStore: ProjectStore = ProjectStore(),
        mediaImporter: MediaImporter = MediaImporter(),
        proxyManager: ProxyManager = ProxyManager()
    ) {
        self.project = project
        self.timelineEngine = timelineEngine
        self.playbackEngine = playbackEngine
        self.renderEngine = renderEngine
        self.aiService = aiService
        self.projectStore = projectStore
        self.mediaImporter = mediaImporter
        self.proxyManager = proxyManager

        statusMessage = "Ready"
        playheadTime = 0
        showsShortcutHelp = false
        activeSequenceID = project.sequences.first?.id
        exportProgress = 0
        exportStatusMessage = "Idle"
        completedExports = []
    }

    public var activeSequence: EditorSequence? {
        if let activeSequenceID,
           let matched = project.sequences.first(where: { $0.id == activeSequenceID }) {
            return matched
        }
        return project.sequences.first
    }

    public var selectedClip: ClipRef? {
        clipSelection?.clip
    }

    public var selectedClipTrackKind: TrackKind? {
        clipSelection?.kind
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
        project = ProjectFactory.starterProject(name: name)
        currentProjectBundleURL = nil
        lastAutosaveURL = nil
        lastAIArtifact = nil
        selectedAssetID = nil
        selectedClipID = nil
        activeSequenceID = project.sequences.first?.id
        playheadTime = 0
        exportProgress = 0
        exportStatusMessage = "Idle"
        completedExports = []
        statusMessage = "Created new project"
        restartAutosaveTimer()
    }

    public func openProject(at bundleURL: URL) {
        do {
            exportProgressTask?.cancel()
            exportProgressTask = nil
            let loaded = try projectStore.load(from: bundleURL)
            project = loaded
            currentProjectBundleURL = bundleURL
            selectedAssetID = loaded.assets.first?.id
            selectedClipID = nil
            activeSequenceID = loaded.sequences.first?.id
            playheadTime = 0
            exportProgress = 0
            exportStatusMessage = "Idle"
            statusMessage = "Opened \(bundleURL.lastPathComponent)"
            restartAutosaveTimer()
        } catch {
            do {
                if let recovered = try projectStore.recoverLatestAutosave(from: bundleURL) {
                    project = recovered
                    currentProjectBundleURL = bundleURL
                    selectedAssetID = recovered.assets.first?.id
                    activeSequenceID = recovered.sequences.first?.id
                    exportProgress = 0
                    exportStatusMessage = "Idle"
                    statusMessage = "Recovered latest autosave from \(bundleURL.lastPathComponent)"
                    restartAutosaveTimer()
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
            statusMessage = "Saved as \(bundleURL.lastPathComponent)"
            restartAutosaveTimer()
        } catch {
            statusMessage = "Save as failed: \(error.localizedDescription)"
        }
    }

    public func switchTimelineMode() {
        guard let sequence = activeSequence else { return }

        let nextMode: TimelineMode = sequence.mode == .track ? .magnetic : .track

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

        selectedAssetID = firstAsset.id
        appendAssetToTimeline(assetID: firstAsset.id)
    }

    public func appendAssetToTimeline(assetID: UUID) {
        guard let asset = project.assets.first(where: { $0.id == assetID }) else {
            statusMessage = "Asset not found"
            return
        }
        selectedAssetID = assetID

        guard let sequence = activeSequence,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequence.id }) else {
            statusMessage = "No active sequence"
            return
        }

        var workingProject = project
        let tracks = ensurePrimaryTracks(in: &workingProject, sequenceIndex: sequenceIndex)

        let clipDuration = max(1.0, asset.duration > 0 ? asset.duration : 4.0)
        let clip = ClipRef(
            assetID: asset.id,
            inTime: 0,
            outTime: clipDuration,
            timelineIn: playheadTime
        )

        do {
            let insertedVideo = try timelineEngine.apply(
                operation: .insertClip(
                    sequenceID: sequence.id,
                    trackID: tracks.videoTrackID,
                    trackKind: .video,
                    clip: clip
                ),
                to: workingProject
            )
            workingProject = insertedVideo.0

            if asset.type == .video || asset.type == .audio {
                let linkedAudio = ClipRef(
                    assetID: asset.id,
                    inTime: 0,
                    outTime: clipDuration,
                    timelineIn: playheadTime,
                    linkedAudioIDs: [clip.id]
                )

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
            }

            project = workingProject
            selectedClipID = clip.id
            playheadTime += clipDuration
            statusMessage = "Inserted \(asset.name) at \(timecode(playheadTime - clipDuration))"
        } catch {
            statusMessage = "Insert failed: \(error.localizedDescription)"
        }
    }

    public func splitFirstClipAtPlayhead() {
        guard let sequence = activeSequence,
              let firstTrack = sequence.videoTracks.first,
              let firstClip = firstTrack.clips.first else {
            statusMessage = "No clip available to split"
            return
        }

        let splitTime = min(max(firstClip.timelineIn + 0.1, playheadTime), firstClip.timelineIn + firstClip.duration - 0.1)

        do {
            let result = try timelineEngine.apply(
                operation: .splitClip(
                    sequenceID: sequence.id,
                    trackID: firstTrack.id,
                    trackKind: .video,
                    clipID: firstClip.id,
                    splitTime: splitTime
                ),
                to: project
            )
            project = result.0
            sanitizeSelectedClip()
            statusMessage = "Split first clip at \(timecode(splitTime))"
        } catch {
            statusMessage = "Split failed: \(error.localizedDescription)"
        }
    }

    public func rippleDeleteFirstClip() {
        guard let sequence = activeSequence,
              let firstTrack = sequence.videoTracks.first,
              let firstClip = firstTrack.clips.first else {
            statusMessage = "No clip available to ripple delete"
            return
        }

        do {
            let result = try timelineEngine.apply(
                operation: .rippleDelete(
                    sequenceID: sequence.id,
                    trackID: firstTrack.id,
                    trackKind: .video,
                    clipID: firstClip.id
                ),
                to: project
            )
            project = result.0
            sanitizeSelectedClip()
            playheadTime = min(playheadTime, result.1.resultingDuration)
            statusMessage = "Ripple deleted first clip"
        } catch {
            statusMessage = "Ripple delete failed: \(error.localizedDescription)"
        }
    }

    public func runAutoCaptions() {
        guard let sequence = activeSequence else { return }

        do {
            lastAIArtifact = try aiService.run(taskType: .autoCaptions, sequenceID: sequence.id, options: [:], in: project)
            statusMessage = "Generated caption draft"
        } catch {
            statusMessage = "Caption generation failed"
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

    public func enqueueExport(presetID: String = "youtube-1080p-h264") {
        guard let sequence = activeSequence else { return }

        do {
            _ = try renderEngine.enqueue(projectID: project.id, sequenceID: sequence.id, presetID: presetID)
            exportProgress = 0
            exportStatusMessage = "Rendering \(presetID)"
            startExportProgressSimulation()
            statusMessage = "Export job started (\(presetID))"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    public func cancelExport() {
        exportProgressTask?.cancel()
        exportProgressTask = nil
        exportProgress = 0
        exportStatusMessage = "Cancelled"
        _ = try? renderEngine.failCurrentJob()
        statusMessage = "Export cancelled"
    }

    public func importMedia(urls: [URL]) {
        let result = mediaImporter.import(urls: urls)
        guard !result.importedAssets.isEmpty else {
            statusMessage = result.warnings.isEmpty ? "No files imported" : result.warnings.joined(separator: " | ")
            return
        }

        var updatedAssets = project.assets
        var insertedCount = 0

        for asset in result.importedAssets {
            if !updatedAssets.contains(where: { $0.path == asset.path }) {
                updatedAssets.append(asset)
                insertedCount += 1
            }
        }

        var updatedProject = project
        updatedProject.assets = updatedAssets

        if updatedProject.bins.isEmpty {
            updatedProject.bins = [MediaBin(name: "Imported")]
        }

        for index in updatedProject.bins.indices {
            var ids = Set(updatedProject.bins[index].assetIDs)
            for asset in result.importedAssets {
                ids.insert(asset.id)
            }
            updatedProject.bins[index].assetIDs = Array(ids)
        }

        project = updatedProject
        if selectedAssetID == nil {
            selectedAssetID = result.importedAssets.first?.id
        }
        sanitizeSelectedClip()
        statusMessage = "Imported \(insertedCount) assets"
    }

    public func selectClip(_ clipID: UUID?) {
        selectedClipID = clipID
    }

    public func selectAsset(_ assetID: UUID?) {
        selectedAssetID = assetID
    }

    public func appendSelectedAssetToTimeline() {
        guard let selectedAssetID else {
            statusMessage = "Select an asset in the browser first"
            return
        }
        appendAssetToTimeline(assetID: selectedAssetID)
    }

    public func setActiveSequence(_ sequenceID: UUID) {
        guard project.sequences.contains(where: { $0.id == sequenceID }) else { return }
        activeSequenceID = sequenceID
        selectedClipID = nil
        playheadTime = 0
        statusMessage = "Switched sequence"
    }

    public func createSequence(named name: String? = nil) {
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
        selectedClipID = nil
        playheadTime = 0
        statusMessage = "Created \(sequenceName)"
    }

    public func duplicateActiveSequence() {
        guard let sequence = activeSequence else { return }
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
        selectedClipID = nil
        playheadTime = 0
        statusMessage = "Duplicated sequence"
    }

    public func addMarkerAtPlayhead(label: String = "Marker") {
        guard let activeSequenceID,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == activeSequenceID }) else { return }
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
        playheadTime = marker.time
        statusMessage = "Jumped to marker: \(marker.label)"
    }

    public func nudgeSelectedClip(by seconds: TimeInterval) {
        guard let sequence = activeSequence, let selection = clipSelection else {
            statusMessage = "Select a clip first"
            return
        }

        let targetTime = max(0, selection.clip.timelineIn + seconds)

        do {
            let result = try timelineEngine.apply(
                operation: .moveClip(
                    sequenceID: sequence.id,
                    trackID: selection.trackID,
                    trackKind: selection.kind,
                    clipID: selection.clip.id,
                    newTimelineIn: targetTime
                ),
                to: project
            )
            project = result.0
            statusMessage = "Moved clip to \(timecode(targetTime))"
        } catch {
            statusMessage = "Move failed: \(error.localizedDescription)"
        }
    }

    public func trimSelectedClipLeading(by delta: TimeInterval) {
        guard let sequence = activeSequence, let selection = clipSelection else {
            statusMessage = "Select a clip first"
            return
        }

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
        guard let sequence = activeSequence, let selection = clipSelection else {
            statusMessage = "Select a clip first"
            return
        }

        do {
            let result = try timelineEngine.apply(
                operation: .rippleDelete(
                    sequenceID: sequence.id,
                    trackID: selection.trackID,
                    trackKind: selection.kind,
                    clipID: selection.clip.id
                ),
                to: project
            )
            project = result.0
            sanitizeSelectedClip()
            playheadTime = min(playheadTime, result.1.resultingDuration)
            statusMessage = "Ripple deleted selected clip"
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
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

    public func toggleShortcutHelp() {
        showsShortcutHelp.toggle()
    }

    public func updatePlayhead(to newTime: TimeInterval) {
        playheadTime = max(0, newTime)
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

        return (
            project.sequences[sequenceIndex].videoTracks[0].id,
            project.sequences[sequenceIndex].audioTracks[0].id
        )
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

    private func startExportProgressSimulation() {
        exportProgressTask?.cancel()
        exportProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }

                await MainActor.run {
                    self.exportProgress = min(1.0, self.exportProgress + 0.03)

                    if self.exportProgress >= 1.0 {
                        self.exportProgressTask?.cancel()
                        self.exportProgressTask = nil
                        if let completed = try? self.renderEngine.completeCurrentJob() {
                            self.completedExports.insert(completed, at: 0)
                        }
                        self.exportStatusMessage = "Completed"
                        self.statusMessage = "Export completed"
                    }
                }
            }
        }
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
        guard let selectedClipID else { return }
        guard let sequenceID = activeSequenceID ?? project.sequences.first?.id,
              let sequenceIndex = project.sequences.firstIndex(where: { $0.id == sequenceID }) else { return }

        var project = self.project
        var updated = false

        for trackIndex in project.sequences[sequenceIndex].videoTracks.indices {
            if let clipIndex = project.sequences[sequenceIndex].videoTracks[trackIndex].clips.firstIndex(where: { $0.id == selectedClipID }) {
                mutation(&project.sequences[sequenceIndex].videoTracks[trackIndex].clips[clipIndex])
                updated = true
                break
            }
        }

        if !updated {
            for trackIndex in project.sequences[sequenceIndex].audioTracks.indices {
                if let clipIndex = project.sequences[sequenceIndex].audioTracks[trackIndex].clips.firstIndex(where: { $0.id == selectedClipID }) {
                    mutation(&project.sequences[sequenceIndex].audioTracks[trackIndex].clips[clipIndex])
                    updated = true
                    break
                }
            }
        }

        guard updated else { return }
        self.project = project
    }

    private func sanitizeSelectedClip() {
        guard let selectedClipID else { return }
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
}

public struct EditorRootView: View {
    @StateObject private var workspace = EditorWorkspace()
    @State private var browserTab: BrowserTab = .libraries
    @State private var inspectorTab: InspectorTab = .video
    @State private var timelineZoom: Double = 1.0
    @State private var draggingClipID: UUID?
    @State private var dragTranslationX: CGFloat = 0

    public init() {}

    private enum BrowserTab: String, CaseIterable, Identifiable {
        case libraries = "Libraries"
        case media = "Media"
        case effects = "Effects"

        var id: String { rawValue }
    }

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case video = "Video"
        case audio = "Audio"
        case info = "Info"

        var id: String { rawValue }
    }

    private var activeSequence: EditorSequence? {
        workspace.activeSequence
    }

    private var videoClips: [ClipRef] {
        activeSequence?.videoTracks
            .flatMap(\.clips)
            .sorted(by: { $0.timelineIn < $1.timelineIn }) ?? []
    }

    private var audioClips: [ClipRef] {
        activeSequence?.audioTracks
            .flatMap(\.clips)
            .sorted(by: { $0.timelineIn < $1.timelineIn }) ?? []
    }

    private var clipCount: Int {
        videoClips.count
    }

    public var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.12)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HSplitView {
                    browserPanel
                        .frame(minWidth: 250, idealWidth: 290, maxWidth: 360)

                    VSplitView {
                        VStack(spacing: 8) {
                            topToolbar
                            viewerWorkbench
                        }
                        .padding(8)
                        .background(Color(red: 0.13, green: 0.13, blue: 0.14))
                        .frame(minHeight: 360)

                        timelinePanel
                            .frame(minHeight: 280)
                            .background(Color(red: 0.15, green: 0.15, blue: 0.16))
                    }

                    inspectorPanel
                        .frame(minWidth: 250, idealWidth: 285, maxWidth: 340)
                        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
                }
                .background(Color(red: 0.12, green: 0.12, blue: 0.13))

                bottomBar
                    .background(Color(red: 0.10, green: 0.10, blue: 0.11))
            }
            .overlay(alignment: .topTrailing) {
                if workspace.showsShortcutHelp {
                    shortcutsOverlay
                        .padding(14)
                }
            }
        }
        .frame(minWidth: 1400, minHeight: 860)
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.newProject)) { _ in
            workspace.createNewProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.openProject)) { _ in
            workspace.openProjectUsingDialog()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.saveProject)) { _ in
            workspace.saveProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.importMedia)) { _ in
            workspace.importMediaUsingDialog()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.appendFirstAsset)) { _ in
            workspace.appendFirstAssetToTimeline()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.splitFirstClip)) { _ in
            workspace.splitFirstClipAtPlayhead()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.rippleDeleteFirstClip)) { _ in
            workspace.rippleDeleteFirstClip()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.newSequence)) { _ in
            workspace.createSequence()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.duplicateSequence)) { _ in
            workspace.duplicateActiveSequence()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.addMarker)) { _ in
            workspace.addMarkerAtPlayhead()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.nextMarker)) { _ in
            workspace.jumpToNextMarker()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.toggleTimelineMode)) { _ in
            workspace.switchTimelineMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.toggleShortcutHelp)) { _ in
            workspace.toggleShortcutHelp()
        }
    }

    private var browserPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Browser")
                    .font(.headline)
                Spacer()
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
                    HStack {
                        Button("Append Selected") {
                            workspace.appendSelectedAssetToTimeline()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(workspace.selectedAssetID == nil)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 2)

                    List(workspace.project.assets) { asset in
                        HStack(spacing: 8) {
                            Image(systemName: symbol(for: asset.type))
                                .foregroundStyle(.white.opacity(0.9))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(asset.name)
                                    .foregroundStyle(.white)
                                Text("\(asset.type.rawValue.capitalized) • \(workspace.timecode(asset.duration))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
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
                    }
                }
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

    private var topToolbar: some View {
        VStack(spacing: 8) {
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

                transportButtons
            }

            HStack(spacing: 8) {
                toolbarButton("New", systemImage: "plus.square") { workspace.createNewProject() }
                toolbarButton("Open", systemImage: "folder") { workspace.openProjectUsingDialog() }
                toolbarButton("Save", systemImage: "square.and.arrow.down") { workspace.saveProject() }
                Divider().frame(height: 18)
                if !workspace.project.sequences.isEmpty {
                    sequencePicker
                }
                toolbarButton("New Seq", systemImage: "plus.rectangle.on.folder") { workspace.createSequence() }
                toolbarButton("Duplicate", systemImage: "doc.on.doc") { workspace.duplicateActiveSequence() }
                Divider().frame(height: 18)
                toolbarButton("Import", systemImage: "tray.and.arrow.down") { workspace.importMediaUsingDialog() }
                toolbarButton("Append", systemImage: "plus.rectangle.on.rectangle") { workspace.appendSelectedAssetToTimeline() }
                toolbarButton("Split", systemImage: "scissors") { workspace.splitFirstClipAtPlayhead() }
                toolbarButton("Delete", systemImage: "delete.left") { workspace.rippleDeleteFirstClip() }
                toolbarButton("Add Marker", systemImage: "bookmark") { workspace.addMarkerAtPlayhead() }
                toolbarButton("Next Marker", systemImage: "arrow.right.to.line") { workspace.jumpToNextMarker() }
                Divider().frame(height: 18)
                toolbarButton("Nudge -", systemImage: "arrow.left") { workspace.nudgeSelectedClip(by: -0.5) }
                toolbarButton("Nudge +", systemImage: "arrow.right") { workspace.nudgeSelectedClip(by: 0.5) }
                toolbarButton("Trim In", systemImage: "arrow.right.to.line.compact") { workspace.trimSelectedClipLeading(by: 0.1) }
                toolbarButton("Trim Out", systemImage: "arrow.left.to.line.compact") { workspace.trimSelectedClipTrailing(by: 0.1) }
                toolbarButton("Delete Sel", systemImage: "trash") { workspace.rippleDeleteSelectedClip() }
                Divider().frame(height: 18)
                toolbarButton("Captions", systemImage: "captions.bubble") { workspace.runAutoCaptions() }
                toolbarButton("Highlights", systemImage: "sparkles") { workspace.runHighlightSuggestions() }
                toolbarButton("Export", systemImage: "square.and.arrow.up") { workspace.enqueueExport() }
                if workspace.exportProgress > 0 && workspace.exportProgress < 1 {
                    toolbarButton("Cancel Export", systemImage: "xmark.circle") { workspace.cancelExport() }
                }
                Spacer()
                Button("Mode: \(workspace.activeSequence?.mode.rawValue.capitalized ?? "N/A")") {
                    workspace.switchTimelineMode()
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.43, green: 0.43, blue: 0.45))
            }
            .foregroundStyle(.white)
        }
        .padding(10)
        .background(Color(red: 0.17, green: 0.17, blue: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var transportButtons: some View {
        HStack(spacing: 6) {
            tinyRoundButton("backward.end.fill")
            tinyRoundButton("backward.fill")
            tinyRoundButton("play.fill")
            tinyRoundButton("forward.fill")
            tinyRoundButton("forward.end.fill")
            Spacer()
            Text(workspace.timecode(workspace.playheadTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
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

    private var viewerWorkbench: some View {
        HStack(spacing: 8) {
            viewerPanel(title: "Event Viewer", subtitle: "Source")
            viewerPanel(title: "Project Viewer", subtitle: "Program")
        }
    }

    private func viewerPanel(title: String, subtitle: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                tinyRoundButton("plus")
                tinyRoundButton("minus")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(red: 0.18, green: 0.18, blue: 0.19))

            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.92))
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.65))
                    Text("Playhead \(workspace.timecode(workspace.playheadTime))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(minHeight: 220)

            HStack {
                tinyRoundButton("gobackward.10")
                tinyRoundButton("playpause.fill")
                tinyRoundButton("goforward.10")
                Spacer()
                tinyRoundButton("speaker.wave.2.fill")
                Slider(
                    value: Binding(
                        get: { workspace.playheadTime },
                        set: { workspace.updatePlayhead(to: $0) }
                    ),
                    in: 0...max(1.0, activeSequence?.duration ?? 1.0)
                )
                .frame(maxWidth: 180)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(red: 0.18, green: 0.18, blue: 0.19))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var timelinePanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Timeline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("Magnetic Mode")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Markers \(activeSequence?.markers.count ?? 0)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $timelineZoom, in: 0.6...2.2)
                    .frame(width: 120)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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
                    HStack {
                        Text("Primary Storyline")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Clips \(videoClips.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if videoClips.isEmpty {
                        emptyTimelinePrompt
                    } else {
                        timelineTrack(clips: videoClips, tint: Color(red: 0.90, green: 0.52, blue: 0.28))
                    }

                    HStack {
                        Text("Connected Audio")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Clips \(audioClips.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    timelineTrack(clips: audioClips, tint: Color(red: 0.24, green: 0.62, blue: 0.76))
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
                workspace.appendFirstAssetToTimeline()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func timelineTrack(clips: [ClipRef], tint: Color) -> some View {
        if clips.isEmpty {
            return AnyView(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 36)
            )
        }

        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(clips) { clip in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.timecode(clip.timelineIn))
                                .font(.caption2.monospacedDigit())
                            Text("+\(workspace.timecode(clip.duration))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(width: clipWidth(for: clip.duration), height: 36, alignment: .leading)
                        .background(clipFillColor(for: clip, baseTint: tint))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    workspace.selectedClipID == clip.id ? Color.white : Color.clear,
                                    lineWidth: 1.6
                                )
                        )
                        .offset(x: draggingClipID == clip.id ? dragTranslationX : 0)
                        .onTapGesture {
                            workspace.selectClip(clip.id)
                        }
                        .contextMenu {
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
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { gesture in
                                    workspace.selectClip(clip.id)
                                    draggingClipID = clip.id
                                    dragTranslationX = gesture.translation.width
                                }
                                .onEnded { gesture in
                                    let seconds = Double(gesture.translation.width / max(30, (48 * timelineZoom)))
                                    workspace.selectClip(clip.id)
                                    workspace.nudgeSelectedClip(by: seconds)
                                    draggingClipID = nil
                                    dragTranslationX = 0
                                }
                        )
                    }
                }
            }
        )
    }

    private func clipWidth(for duration: TimeInterval) -> CGFloat {
        let width = 70 + (duration * 10 * timelineZoom)
        return min(240, max(70, width))
    }

    private var inspectorPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Inspector")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                tinyRoundButton("slider.horizontal.3")
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
                    } else {
                        inspectorGroup("Project", rows: [
                            ("FPS", String(format: "%.0f", workspace.project.fps)),
                            ("Color Space", workspace.project.colorSpace),
                            ("Schema", "v\(workspace.project.schemaVersion)")
                        ])
                        inspectorGroup("Sequence", rows: [
                            ("Video Clips", "\(videoClips.count)"),
                            ("Audio Clips", "\(audioClips.count)"),
                            ("Duration", workspace.timecode(activeSequence?.duration ?? 0)),
                            ("Markers", "\(activeSequence?.markers.count ?? 0)")
                        ])
                        if let selectedClip = workspace.selectedClip {
                            inspectorGroup("Selected Clip", rows: [
                                ("ID", String(selectedClip.id.uuidString.prefix(8)) + "..."),
                                ("Start", workspace.timecode(selectedClip.timelineIn)),
                                ("Duration", workspace.timecode(selectedClip.duration))
                            ])
                        }
                        inspectorGroup("Export Queue", rows: [
                            ("Status", workspace.exportStatusMessage),
                            ("Progress", "\(Int(workspace.exportProgress * 100))%"),
                            ("Completed", "\(workspace.completedExports.count)")
                        ])
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

            ForEach(rows, id: \.0) { row in
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
        return baseTint.opacity(0.78)
    }

    private func tinyRoundButton(_ systemImage: String) -> some View {
        Button {
            // Decorative transport/utility controls for the prototype shell.
        } label: {
            Image(systemName: systemImage)
                .font(.caption.bold())
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.8))
        .background(
            Circle()
                .fill(Color.white.opacity(0.08))
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
        HStack {
            Text(workspace.statusMessage)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()

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

    private var shortcutsOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyboard Shortcuts")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Cmd+N  New Project")
            Text("Cmd+O  Open Project")
            Text("Cmd+S  Save Project")
            Text("Cmd+I  Import Media")
            Text("Cmd+E  Append First Asset")
            Text("Cmd+\\  Split First Clip")
            Text("Cmd+Shift+Delete  Ripple Delete First")
            Text("Cmd+Shift+M  Toggle Timeline Mode")
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
