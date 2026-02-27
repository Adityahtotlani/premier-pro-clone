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
    @Published public var currentProjectBundleURL: URL?
    @Published public var lastAutosaveURL: URL?
    @Published public var playheadTime: TimeInterval
    @Published public var showsShortcutHelp: Bool

    public let timelineEngine: TimelineEngine
    public let playbackEngine: PlaybackEngine
    public let renderEngine: RenderEngine
    public let aiService: AIAssistService

    private let projectStore: ProjectStore
    private let mediaImporter: MediaImporter
    private let proxyManager: ProxyManager
    private var autosaveTimer: Timer?

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
    }

    public var activeSequence: EditorSequence? {
        project.sequences.first
    }

    public func createNewProject(named name: String = "Untitled Project") {
        project = ProjectFactory.starterProject(name: name)
        currentProjectBundleURL = nil
        lastAutosaveURL = nil
        lastAIArtifact = nil
        playheadTime = 0
        statusMessage = "Created new project"
        restartAutosaveTimer()
    }

    public func openProject(at bundleURL: URL) {
        do {
            let loaded = try projectStore.load(from: bundleURL)
            project = loaded
            currentProjectBundleURL = bundleURL
            playheadTime = 0
            statusMessage = "Opened \(bundleURL.lastPathComponent)"
            restartAutosaveTimer()
        } catch {
            do {
                if let recovered = try projectStore.recoverLatestAutosave(from: bundleURL) {
                    project = recovered
                    currentProjectBundleURL = bundleURL
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

        appendAssetToTimeline(assetID: firstAsset.id)
    }

    public func appendAssetToTimeline(assetID: UUID) {
        guard let asset = project.assets.first(where: { $0.id == assetID }) else {
            statusMessage = "Asset not found"
            return
        }

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
            statusMessage = "Export job started (\(presetID))"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
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
        statusMessage = "Imported \(insertedCount) assets"
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
}

public struct EditorRootView: View {
    @StateObject private var workspace = EditorWorkspace()

    public init() {}

    private var activeSequence: EditorSequence? {
        workspace.activeSequence
    }

    private var clipCount: Int {
        activeSequence?.videoTracks.flatMap(\.clips).count ?? 0
    }

    private var hasImportedMedia: Bool {
        !workspace.project.assets.isEmpty
    }

    private var quickStartProgress: Int {
        [hasImportedMedia, clipCount > 0, workspace.lastAIArtifact != nil].filter { $0 }.count
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 0.96),
                    Color(red: 0.94, green: 0.97, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                welcomeHeader
                Divider()

                HSplitView {
                    leftRail
                        .frame(minWidth: 300, idealWidth: 340)

                    VStack(spacing: 10) {
                        actionDock
                        viewersPanel
                        timelinePanel
                    }
                    .padding(10)
                }

                Divider()
                statusBar
            }
            .frame(minWidth: 1280, minHeight: 780)
            .padding(8)
            .overlay(alignment: .topTrailing) {
                if workspace.showsShortcutHelp {
                    shortcutsOverlay
                        .padding(14)
                }
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.toggleTimelineMode)) { _ in
            workspace.switchTimelineMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorCommand.toggleShortcutHelp)) { _ in
            workspace.toggleShortcutHelp()
        }
    }

    private var welcomeHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Start Editing in 3 Simple Steps")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text("Import clips, place your first shot, then export a creator preset.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Text("Progress \(quickStartProgress)/3")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.8))
                    .clipShape(Capsule())
                Button("Shortcuts") { workspace.toggleShortcutHelp() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.25, green: 0.59, blue: 0.48),
                    Color(red: 0.20, green: 0.47, blue: 0.66)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var leftRail: some View {
        VStack(spacing: 10) {
            quickStartCard
            mediaBinCard
        }
        .padding(10)
    }

    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Start")
                .font(.system(.title3, design: .rounded).weight(.semibold))

            checklistRow(
                title: "1. Import media",
                hint: "Bring in clips you want to edit",
                complete: hasImportedMedia,
                actionTitle: "Import"
            ) {
                workspace.importMediaUsingDialog()
            }

            checklistRow(
                title: "2. Add first clip",
                hint: "Drop your first shot on timeline",
                complete: clipCount > 0,
                actionTitle: "Append"
            ) {
                workspace.appendFirstAssetToTimeline()
            }

            checklistRow(
                title: "3. Try smart assist",
                hint: "Generate captions or highlights",
                complete: workspace.lastAIArtifact != nil,
                actionTitle: "Auto Captions"
            ) {
                workspace.runAutoCaptions()
            }

            Button("Export Preview") {
                workspace.enqueueExport()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.90, green: 0.46, blue: 0.24))
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func checklistRow(
        title: String,
        hint: String,
        complete: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(complete ? Color.green : Color.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(actionTitle) {
                action()
            }
            .buttonStyle(.bordered)
            .disabled(complete)
        }
    }

    private var mediaBinCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Media Bin")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
                Button("Import") {
                    workspace.importMediaUsingDialog()
                }
            }

            if workspace.project.assets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No media yet")
                        .font(.subheadline.weight(.medium))
                    Text("Click Import to add videos, audio, or images.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                List {
                    ForEach(workspace.project.assets) { asset in
                        HStack {
                            Image(systemName: symbol(for: asset.type))
                                .foregroundStyle(Color(red: 0.19, green: 0.49, blue: 0.61))
                            VStack(alignment: .leading) {
                                Text(asset.name)
                                Text("\(asset.type.rawValue.capitalized) • \(workspace.timecode(asset.duration))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionDock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    actionTile("New", subtitle: "Fresh project", icon: "plus.square.fill", tint: Color(red: 0.27, green: 0.50, blue: 0.85)) {
                        workspace.createNewProject()
                    }
                    actionTile("Open", subtitle: "Load bundle", icon: "folder.fill", tint: Color(red: 0.35, green: 0.56, blue: 0.39)) {
                        workspace.openProjectUsingDialog()
                    }
                    actionTile("Save", subtitle: "Keep progress", icon: "square.and.arrow.down.fill", tint: Color(red: 0.49, green: 0.49, blue: 0.70)) {
                        workspace.saveProject()
                    }
                    actionTile("Append Clip", subtitle: "Add first asset", icon: "film.stack.fill", tint: Color(red: 0.81, green: 0.49, blue: 0.27)) {
                        workspace.appendFirstAssetToTimeline()
                    }
                    actionTile("Split", subtitle: "Cut at playhead", icon: "scissors", tint: Color(red: 0.66, green: 0.43, blue: 0.29)) {
                        workspace.splitFirstClipAtPlayhead()
                    }
                    actionTile("Captions", subtitle: "Auto draft text", icon: "captions.bubble.fill", tint: Color(red: 0.26, green: 0.60, blue: 0.62)) {
                        workspace.runAutoCaptions()
                    }
                    actionTile("Export", subtitle: "Share result", icon: "square.and.arrow.up.fill", tint: Color(red: 0.89, green: 0.40, blue: 0.26)) {
                        workspace.enqueueExport()
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var viewersPanel: some View {
        HStack(spacing: 12) {
            viewerCard(title: "Source Viewer")
            viewerCard(title: "Program Viewer")
        }
    }

    @ViewBuilder
    private func actionTile(
        _ title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 118, alignment: .leading)
            .padding(10)
            .background(Color.white.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
    }

    private func viewerCard(title: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.85), Color.black.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    VStack(spacing: 6) {
                        Text("Playback Surface")
                            .foregroundStyle(.white.opacity(0.85))
                            .font(.caption)
                        Text("Playhead: \(workspace.timecode(workspace.playheadTime))")
                            .foregroundStyle(.white.opacity(0.75))
                            .font(.caption2)
                    }
                )
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timeline")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
                Text("Mode: \(workspace.activeSequence?.mode.rawValue.capitalized ?? "N/A")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Switch Mode") {
                    workspace.switchTimelineMode()
                }
                .buttonStyle(.bordered)
            }

            if let sequence = activeSequence {
                VStack(spacing: 6) {
                    HStack {
                        Text("Playhead")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(workspace.timecode(workspace.playheadTime))
                            .font(.caption.monospacedDigit())
                    }

                    Slider(
                        value: Binding(
                            get: { workspace.playheadTime },
                            set: { workspace.updatePlayhead(to: $0) }
                        ),
                        in: 0...max(1.0, sequence.duration)
                    )
                }

                if clipCount == 0 {
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack")
                            .foregroundStyle(Color(red: 0.23, green: 0.50, blue: 0.66))
                        VStack(alignment: .leading) {
                            Text("Timeline is empty")
                                .font(.subheadline.weight(.semibold))
                            Text("Use “Append Clip” above to place your first shot.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Append Now") {
                            workspace.appendFirstAssetToTimeline()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    List {
                        Section("Video Tracks") {
                            ForEach(sequence.videoTracks) { track in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(trackSummary(track))
                                    Text(clipSummary(track.clips))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Section("Audio Tracks") {
                            ForEach(sequence.audioTracks) { track in
                                Text(trackSummary(track))
                            }
                        }
                    }
                }
            } else {
                Text("No active sequence")
                    .foregroundStyle(.secondary)
            }

            if let artifact = workspace.lastAIArtifact {
                Text("Last AI: \(artifact.taskType.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func trackSummary(_ track: TimelineTrack) -> String {
        "\(track.name) • clips: \(track.clips.count)"
    }

    private func clipSummary(_ clips: [ClipRef]) -> String {
        if clips.isEmpty {
            return "No clips"
        }

        return clips
            .prefix(4)
            .map { clip in
                "\(workspace.timecode(clip.timelineIn)) (+\(workspace.timecode(clip.duration)))"
            }
            .joined(separator: "   ")
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

    private var statusBar: some View {
        HStack {
            Text(workspace.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            if let autosaveURL = workspace.lastAutosaveURL {
                Text("Autosave: \(autosaveURL.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
        .background(.thinMaterial)
        .cornerRadius(8)
        .shadow(radius: 8)
    }
}
