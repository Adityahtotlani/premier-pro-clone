#if canImport(XCTest)
import XCTest
@testable import AppShell
import ProjectCore

@MainActor
final class AppShellTests: XCTestCase {
    func testCreateSequenceAndSwitch() {
        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "Test"))
        let initialCount = workspace.project.sequences.count

        workspace.createSequence(named: "Alt")

        XCTAssertEqual(workspace.project.sequences.count, initialCount + 1)
        XCTAssertEqual(workspace.activeSequence?.name, "Alt")
    }

    func testAddMarkerAtPlayhead() {
        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "Test"))
        workspace.updatePlayhead(to: 12.0)
        workspace.addMarkerAtPlayhead(label: "Beat")

        XCTAssertEqual(workspace.activeSequence?.markers.count, 1)
        XCTAssertEqual(workspace.activeSequence?.markers.first?.label, "Beat")
    }

    func testSelectedClipMutationUpdatesTransform() {
        var project = ProjectFactory.starterProject(name: "Test")
        let asset = MediaAsset(name: "Clip", path: "/tmp/clip.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()

        guard let selectedClip = workspace.selectedClip else {
            XCTFail("Expected selected clip")
            return
        }

        workspace.updateSelectedClipPositionX(42)

        let updated = workspace.activeSequence?.videoTracks
            .flatMap(\.clips)
            .first(where: { $0.id == selectedClip.id })

        XCTAssertEqual(updated?.transforms.positionX, 42)
    }

    func testUndoRedoAfterMarkerChange() {
        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "Test"))
        workspace.updatePlayhead(to: 5.0)
        workspace.addMarkerAtPlayhead(label: "A")
        XCTAssertEqual(workspace.activeSequence?.markers.count, 1)

        workspace.undo()
        XCTAssertEqual(workspace.activeSequence?.markers.count, 0)

        workspace.redo()
        XCTAssertEqual(workspace.activeSequence?.markers.count, 1)
    }

    func testSplitUsesSelectedClip() {
        var project = ProjectFactory.starterProject(name: "Split")
        project.assets = [MediaAsset(name: "Clip", path: "/tmp/c.mp4", type: .video, duration: 6)]

        let workspace = EditorWorkspace(project: project)
        workspace.selectAsset(project.assets.first?.id)
        workspace.appendSelectedAssetToTimeline()
        workspace.updatePlayhead(to: 2.0)
        workspace.splitFirstClipAtPlayhead()

        let clips = workspace.activeSequence?.videoTracks.first?.clips ?? []
        XCTAssertEqual(clips.count, 2)
    }

    func testNudgeMovesLinkedAudioWithVideo() {
        var project = ProjectFactory.starterProject(name: "Move")
        project.assets = [MediaAsset(name: "Clip", path: "/tmp/clip.mp4", type: .video, duration: 5)]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()

        guard let selectedVideo = workspace.selectedClip else {
            XCTFail("Expected selected video clip")
            return
        }

        let audioBefore = workspace.activeSequence?.audioTracks
            .flatMap(\.clips)
            .first(where: { $0.linkedAudioIDs.contains(selectedVideo.id) || selectedVideo.linkedAudioIDs.contains($0.id) })
        XCTAssertNotNil(audioBefore)

        workspace.nudgeSelectedClip(by: 1.0)

        let movedVideo = workspace.activeSequence?.videoTracks
            .flatMap(\.clips)
            .first(where: { $0.id == selectedVideo.id })
        let movedAudio = workspace.activeSequence?.audioTracks
            .flatMap(\.clips)
            .first(where: { $0.id == audioBefore?.id })

        XCTAssertEqual(movedVideo?.timelineIn, 1.0, accuracy: 0.0001)
        XCTAssertEqual(movedAudio?.timelineIn, 1.0, accuracy: 0.0001)
    }

    func testSplitSelectedVideoSplitsLinkedAudio() {
        var project = ProjectFactory.starterProject(name: "LinkedSplit")
        project.assets = [MediaAsset(name: "Clip", path: "/tmp/linked.mp4", type: .video, duration: 6)]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()
        workspace.updatePlayhead(to: 2.0)
        workspace.splitSelectedClipAtPlayhead()

        let videoClips = workspace.activeSequence?.videoTracks.first?.clips ?? []
        let audioClips = workspace.activeSequence?.audioTracks.first?.clips ?? []
        XCTAssertEqual(videoClips.count, 2)
        XCTAssertEqual(audioClips.count, 2)
    }

    func testMagneticInsertShiftsExistingTimeline() {
        var project = ProjectFactory.starterProject(name: "MagneticInsert")
        project.assets = [MediaAsset(name: "Clip", path: "/tmp/mag.mp4", type: .video, duration: 4)]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()
        workspace.switchTimelineMode()
        workspace.updatePlayhead(to: 0)
        workspace.appendFirstAssetToTimeline()

        let starts = (workspace.activeSequence?.videoTracks.first?.clips ?? [])
            .map(\.timelineIn)
            .sorted()

        XCTAssertEqual(starts.count, 2)
        XCTAssertEqual(starts[0], 0, accuracy: 0.0001)
        XCTAssertEqual(starts[1], 4, accuracy: 0.0001)
    }

    func testAutoCaptionsPopulateSequenceTrack() {
        var project = ProjectFactory.starterProject(name: "Captions")
        project.assets = [MediaAsset(name: "Clip", path: "/tmp/caption.mp4", type: .video, duration: 8)]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()
        workspace.runAutoCaptions()

        let segments = workspace.activeSequence?.captionTracks.first?.segments ?? []
        XCTAssertFalse(segments.isEmpty)
        XCTAssertEqual(workspace.transcriptMatches.count, segments.count)
    }

    func testTranscriptQueryFiltersMatches() {
        var project = ProjectFactory.starterProject(name: "Transcript")
        var sequence = project.sequences[0]
        sequence.captionTracks = [
            CaptionTrack(language: "en", segments: [
                CaptionSegment(start: 0, end: 1, text: "hello world", confidence: 0.9),
                CaptionSegment(start: 1, end: 2, text: "cutaway", confidence: 0.9)
            ])
        ]
        project.sequences[0] = sequence

        let workspace = EditorWorkspace(project: project)
        workspace.updateTranscriptQuery("hello")

        XCTAssertEqual(workspace.transcriptMatches.count, 1)
        XCTAssertEqual(workspace.transcriptMatches.first?.text, "hello world")
    }

    func testSmartReframePresetUpdatesSelectedVideoTransform() {
        var project = ProjectFactory.starterProject(name: "Reframe")
        project.assets = [MediaAsset(name: "Clip", path: "/tmp/reframe.mp4", type: .video, duration: 4)]
        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()

        workspace.applySmartReframePreset("9:16")

        XCTAssertEqual(workspace.selectedClip?.transforms.scaleX, 1.34, accuracy: 0.0001)
        XCTAssertEqual(workspace.selectedClip?.transforms.scaleY, 1.34, accuracy: 0.0001)
    }

    func testApplySilenceSuggestionClosesGap() {
        var project = ProjectFactory.starterProject(name: "SilenceGap")
        let audioAsset = MediaAsset(name: "VO", path: "/tmp/voice.wav", type: .audio, duration: 3)
        project.assets = [audioAsset]

        var sequence = project.sequences[0]
        sequence.audioTracks = [
            TimelineTrack(
                name: "A1",
                kind: .audio,
                clips: [
                    ClipRef(assetID: audioAsset.id, inTime: 0, outTime: 1, timelineIn: 0),
                    ClipRef(assetID: audioAsset.id, inTime: 1, outTime: 2, timelineIn: 2)
                ]
            )
        ]
        sequence.duration = 3
        project.sequences[0] = sequence

        let workspace = EditorWorkspace(project: project)
        workspace.runSilenceSuggestions()

        guard let firstSuggestion = workspace.silenceSuggestions.first else {
            XCTFail("Expected at least one silence suggestion")
            return
        }

        workspace.applySilenceSuggestion(firstSuggestion.id)

        let starts = workspace.activeSequence?.audioTracks.first?.clips
            .map(\.timelineIn)
            .sorted() ?? []
        XCTAssertEqual(starts, [0, 1], "Expected second clip to ripple left after gap removal")
    }

    func testResetSelectedClipAdjustments() {
        var project = ProjectFactory.starterProject(name: "ResetAdjustments")
        project.assets = [MediaAsset(name: "Clip", path: "/tmp/reset.mp4", type: .video, duration: 4)]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()
        workspace.updateSelectedClipScale(1.8)
        workspace.updateSelectedClipGain(0.4)

        workspace.resetSelectedClipAdjustments()

        XCTAssertEqual(workspace.selectedClip?.transforms.scaleX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(workspace.selectedClip?.transforms.scaleY, 1.0, accuracy: 0.0001)
        XCTAssertEqual(workspace.selectedClip?.gain, 1.0, accuracy: 0.0001)
    }

    func testCyclePlaybackRateRotatesPresetValues() {
        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "Rate"))
        XCTAssertEqual(workspace.playbackRate, 1.0, accuracy: 0.0001)

        workspace.cyclePlaybackRate()
        XCTAssertEqual(workspace.playbackRate, 1.5, accuracy: 0.0001)
        workspace.cyclePlaybackRate()
        XCTAssertEqual(workspace.playbackRate, 2.0, accuracy: 0.0001)
        workspace.cyclePlaybackRate()
        XCTAssertEqual(workspace.playbackRate, 0.5, accuracy: 0.0001)
    }

    func testJumpToNextAndPreviousEditPoint() {
        var project = ProjectFactory.starterProject(name: "EditPoints")
        project.assets = [MediaAsset(name: "Clip", path: "/tmp/edit.mp4", type: .video, duration: 4)]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline() // 0...4
        workspace.appendFirstAssetToTimeline() // 4...8

        workspace.updatePlayhead(to: 1.0)
        workspace.jumpToNextEditPoint()
        XCTAssertEqual(workspace.playheadTime, 4.0, accuracy: 0.0001)

        workspace.jumpToPreviousEditPoint()
        XCTAssertEqual(workspace.playheadTime, 0.0, accuracy: 0.0001)
    }

    func testSourceRangeInsertUsesMarkedInOut() {
        var project = ProjectFactory.starterProject(name: "SourceRange")
        let asset = MediaAsset(name: "Clip", path: "/tmp/source.mp4", type: .video, duration: 10)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.selectAsset(asset.id)
        workspace.updateSourcePlayhead(to: 2.0)
        workspace.setSourceInPointAtPlayhead()
        workspace.updateSourcePlayhead(to: 5.0)
        workspace.setSourceOutPointAtPlayhead()
        workspace.updatePlayhead(to: 0)

        workspace.appendSelectedSourceRangeToTimeline()

        let insertedVideo = workspace.activeSequence?.videoTracks.first?.clips.first
        let insertedAudio = workspace.activeSequence?.audioTracks.first?.clips.first
        XCTAssertEqual(insertedVideo?.inTime, 2.0, accuracy: 0.0001)
        XCTAssertEqual(insertedVideo?.outTime, 5.0, accuracy: 0.0001)
        XCTAssertEqual(insertedAudio?.inTime, 2.0, accuracy: 0.0001)
        XCTAssertEqual(insertedAudio?.outTime, 5.0, accuracy: 0.0001)
        XCTAssertEqual(workspace.playheadTime, 3.0, accuracy: 0.0001)
    }

    func testAppendSelectedAssetToTimelineEndIgnoresCurrentPlayhead() {
        var project = ProjectFactory.starterProject(name: "AppendEnd")
        let asset = MediaAsset(name: "Clip", path: "/tmp/append-end.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.selectAsset(asset.id)
        workspace.appendSelectedAssetToTimeline()
        workspace.updatePlayhead(to: 0.5)

        workspace.appendSelectedAssetToTimelineEnd()

        let starts = (workspace.activeSequence?.videoTracks.first?.clips ?? [])
            .map(\.timelineIn)
            .sorted()
        XCTAssertEqual(starts.count, 2)
        XCTAssertEqual(starts[0], 0.0, accuracy: 0.0001)
        XCTAssertEqual(starts[1], 4.0, accuracy: 0.0001)
    }

    func testInsertAssetToTimelineAtSpecificTime() {
        var project = ProjectFactory.starterProject(name: "DropInsert")
        let asset = MediaAsset(name: "Clip", path: "/tmp/drop.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.insertAssetToTimeline(assetID: asset.id, at: 2.0)

        let inserted = workspace.activeSequence?.videoTracks.first?.clips.first
        XCTAssertEqual(inserted?.timelineIn, 2.0, accuracy: 0.0001)
    }

    func testSelectingAnotherAssetClearsSourceRange() {
        var project = ProjectFactory.starterProject(name: "SourceSwitch")
        let first = MediaAsset(name: "A", path: "/tmp/a.mp4", type: .video, duration: 10)
        let second = MediaAsset(name: "B", path: "/tmp/b.mp4", type: .video, duration: 6)
        project.assets = [first, second]

        let workspace = EditorWorkspace(project: project)
        workspace.selectAsset(first.id)
        workspace.updateSourcePlayhead(to: 1.0)
        workspace.setSourceInPointAtPlayhead()
        workspace.updateSourcePlayhead(to: 3.0)
        workspace.setSourceOutPointAtPlayhead()
        XCTAssertNotNil(workspace.sourceRange)

        workspace.selectAsset(second.id)
        XCTAssertNil(workspace.sourceRange)
        XCTAssertEqual(workspace.sourcePlayheadTime, 0.0, accuracy: 0.0001)
    }

    func testOverwriteModeReplacesOverlappedRegion() {
        var project = ProjectFactory.starterProject(name: "Overwrite")
        let asset = MediaAsset(name: "Clip", path: "/tmp/overwrite.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.selectAsset(asset.id)
        workspace.appendSelectedAssetToTimeline() // 0...4
        workspace.updatePlayhead(to: 2.0)
        workspace.setTimelineEditMode(.overwrite)
        workspace.appendSelectedAssetToTimeline() // 2...6

        let clips = workspace.activeSequence?.videoTracks.first?.clips.sorted(by: { $0.timelineIn < $1.timelineIn }) ?? []
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[0].timelineIn, 0.0, accuracy: 0.0001)
        XCTAssertEqual(clips[0].duration, 2.0, accuracy: 0.0001)
        XCTAssertEqual(clips[1].timelineIn, 2.0, accuracy: 0.0001)
        XCTAssertEqual(clips[1].duration, 4.0, accuracy: 0.0001)
    }

    func testTargetedVideoTrackReceivesInsert() {
        var project = ProjectFactory.starterProject(name: "TargetTrack")
        let asset = MediaAsset(name: "Clip", path: "/tmp/target.mp4", type: .video, duration: 4)
        project.assets = [asset]
        project.sequences[0].videoTracks.append(TimelineTrack(name: "V2", kind: .video))

        let workspace = EditorWorkspace(project: project)
        guard let targetTrackID = workspace.activeSequence?.videoTracks.last?.id else {
            XCTFail("Expected second video track")
            return
        }
        workspace.setTargetedTrack(targetTrackID, kind: .video)
        workspace.appendFirstAssetToTimeline()

        let firstTrackCount = workspace.activeSequence?.videoTracks.first?.clips.count ?? 0
        let secondTrackCount = workspace.activeSequence?.videoTracks.last?.clips.count ?? 0
        XCTAssertEqual(firstTrackCount, 0)
        XCTAssertEqual(secondTrackCount, 1)
    }

    func testLockedTrackBlocksNudge() {
        var project = ProjectFactory.starterProject(name: "LockedTrack")
        let asset = MediaAsset(name: "Clip", path: "/tmp/lock.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()
        guard let trackID = workspace.activeSequence?.videoTracks.first?.id else {
            XCTFail("Expected video track")
            return
        }
        workspace.toggleTrackLock(trackID: trackID)
        let before = workspace.selectedClip?.timelineIn
        workspace.nudgeSelectedClip(by: 1.0)
        let after = workspace.selectedClip?.timelineIn
        XCTAssertEqual(before, after, accuracy: 0.0001)
    }

    func testShuttleControlsPlayAndStop() {
        var project = ProjectFactory.starterProject(name: "Shuttle")
        let asset = MediaAsset(name: "Clip", path: "/tmp/shuttle.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()
        workspace.jumpToStart()
        workspace.shuttleForward()
        XCTAssertTrue(workspace.isPlaying)

        workspace.shuttleStop()
        XCTAssertFalse(workspace.isPlaying)
    }

    func testTrackAddMoveAndRemoveFlow() {
        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "Tracks"))
        let initialTrackID = workspace.activeSequence?.videoTracks.first?.id

        workspace.addTrack(kind: .video)
        let videoTracksAfterAdd = workspace.activeSequence?.videoTracks ?? []
        XCTAssertEqual(videoTracksAfterAdd.count, 2)
        guard let addedTrackID = videoTracksAfterAdd.last?.id else {
            XCTFail("Expected added track")
            return
        }

        workspace.moveTrack(trackID: addedTrackID, kind: .video, direction: -1)
        XCTAssertEqual(workspace.activeSequence?.videoTracks.first?.id, addedTrackID)

        if let initialTrackID {
            workspace.removeTrack(trackID: initialTrackID, kind: .video)
        }
        XCTAssertEqual(workspace.activeSequence?.videoTracks.count, 1)

        if let lastTrackID = workspace.activeSequence?.videoTracks.first?.id {
            workspace.removeTrack(trackID: lastTrackID, kind: .video)
        }
        XCTAssertEqual(workspace.activeSequence?.videoTracks.count, 1)
    }

    func testToggleTimelineEditModeSwitchesState() {
        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "Mode"))
        XCTAssertEqual(workspace.timelineEditMode, .insert)
        workspace.toggleTimelineEditMode()
        XCTAssertEqual(workspace.timelineEditMode, .overwrite)
        workspace.toggleTimelineEditMode()
        XCTAssertEqual(workspace.timelineEditMode, .insert)
    }

    func testProgramClipRespectsTrackMuteAndSolo() {
        var project = ProjectFactory.starterProject(name: "ProgramClip")
        let lower = MediaAsset(name: "Lower", path: "/tmp/lower.mp4", type: .video, duration: 4)
        let upper = MediaAsset(name: "Upper", path: "/tmp/upper.mp4", type: .video, duration: 4)
        project.assets = [lower, upper]

        var sequence = project.sequences[0]
        let v1 = TimelineTrack(
            name: "V1",
            kind: .video,
            clips: [ClipRef(assetID: lower.id, inTime: 0, outTime: 4, timelineIn: 0)]
        )
        let v2 = TimelineTrack(
            name: "V2",
            kind: .video,
            clips: [ClipRef(assetID: upper.id, inTime: 0, outTime: 4, timelineIn: 0)]
        )
        sequence.videoTracks = [v1, v2]
        sequence.duration = 4
        project.sequences[0] = sequence

        let workspace = EditorWorkspace(project: project)
        let initialProgramClip = workspace.programClip(at: 1.0)
        XCTAssertEqual(initialProgramClip?.assetID, upper.id)

        if let upperTrackID = workspace.activeSequence?.videoTracks.last?.id {
            workspace.toggleTrackMute(trackID: upperTrackID, kind: .video)
        }
        let mutedProgramClip = workspace.programClip(at: 1.0)
        XCTAssertEqual(mutedProgramClip?.assetID, lower.id)

        if let lowerTrackID = workspace.activeSequence?.videoTracks.first?.id {
            workspace.toggleTrackSolo(trackID: lowerTrackID, kind: .video)
        }
        let soloProgramClip = workspace.programClip(at: 1.0)
        XCTAssertEqual(soloProgramClip?.assetID, lower.id)
    }

    func testBinManagementFlow() {
        var project = ProjectFactory.starterProject(name: "Bins")
        let asset = MediaAsset(name: "Clip", path: "/tmp/bin-clip.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        let initialBinCount = workspace.project.bins.count

        workspace.createBin(named: "Interviews")
        guard let createdBin = workspace.project.bins.first(where: { $0.name == "Interviews" }) else {
            XCTFail("Expected newly created bin")
            return
        }

        workspace.addAsset(asset.id, toBin: createdBin.id)
        XCTAssertTrue(
            workspace.project.bins
                .first(where: { $0.id == createdBin.id })?
                .assetIDs
                .contains(asset.id) ?? false
        )

        workspace.renameBin(binID: createdBin.id, to: "Interview Selects")
        XCTAssertEqual(
            workspace.project.bins.first(where: { $0.id == createdBin.id })?.name,
            "Interview Selects"
        )

        workspace.removeAsset(asset.id, fromBin: createdBin.id)
        XCTAssertFalse(
            workspace.project.bins
                .first(where: { $0.id == createdBin.id })?
                .assetIDs
                .contains(asset.id) ?? true
        )

        workspace.deleteBin(binID: createdBin.id)
        XCTAssertEqual(workspace.project.bins.count, initialBinCount)
    }

    func testReorderAssetsWithinBin() {
        var project = ProjectFactory.starterProject(name: "BinReorder")
        let assetA = MediaAsset(name: "A", path: "/tmp/bin-a.mp4", type: .video, duration: 4)
        let assetB = MediaAsset(name: "B", path: "/tmp/bin-b.mp4", type: .video, duration: 4)
        let assetC = MediaAsset(name: "C", path: "/tmp/bin-c.mp4", type: .video, duration: 4)
        project.assets = [assetA, assetB, assetC]
        project.bins = [MediaBin(name: "Imported", assetIDs: [assetA.id, assetB.id, assetC.id])]

        let workspace = EditorWorkspace(project: project)

        workspace.moveAsset(assetC.id, inBin: project.bins[0].id, before: assetA.id)

        let ordered = workspace.project.bins[0].assetIDs
        XCTAssertEqual(ordered, [assetC.id, assetA.id, assetB.id])
    }

    func testImportSkipsDuplicateMediaAndAvoidsPhantomBinIDs() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceImportDuplicate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let mediaURL = tempDirectory.appendingPathComponent("clip.mp4")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: mediaURL)

        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "ImportDuplicate"))
        workspace.importMedia(urls: [mediaURL])

        XCTAssertEqual(workspace.project.assets.count, 1)
        let firstAssetID = workspace.project.assets[0].id

        workspace.importMedia(urls: [mediaURL])

        XCTAssertEqual(workspace.project.assets.count, 1)
        XCTAssertEqual(workspace.project.assets[0].id, firstAssetID)

        guard let importedBin = workspace.project.bins.first else {
            XCTFail("Expected at least one bin")
            return
        }
        XCTAssertEqual(importedBin.assetIDs.count, 1)
        XCTAssertEqual(importedBin.assetIDs.first, firstAssetID)
    }

    func testImportAddsAssetsOnlyToImportedBin() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceImportBins-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let mediaURL = tempDirectory.appendingPathComponent("clip.mov")
        try Data([0xAA, 0xBB, 0xCC]).write(to: mediaURL)

        var project = ProjectFactory.starterProject(name: "ImportBins")
        project.bins = [
            MediaBin(name: "Imported"),
            MediaBin(name: "Favorites")
        ]

        let workspace = EditorWorkspace(project: project)
        workspace.importMedia(urls: [mediaURL])

        guard let importedBin = workspace.project.bins.first(where: { $0.name == "Imported" }),
              let favoritesBin = workspace.project.bins.first(where: { $0.name == "Favorites" }),
              let importedAssetID = workspace.project.assets.first?.id else {
            XCTFail("Expected imported data")
            return
        }

        XCTAssertTrue(importedBin.assetIDs.contains(importedAssetID))
        XCTAssertFalse(favoritesBin.assetIDs.contains(importedAssetID))
    }

    func testMissingAssetsDetectsOfflineMedia() {
        var project = ProjectFactory.starterProject(name: "MissingMedia")
        let missing = MediaAsset(name: "Missing", path: "/tmp/does-not-exist-\(UUID().uuidString).mp4", type: .video, duration: 4)
        project.assets = [missing]

        let workspace = EditorWorkspace(project: project)

        XCTAssertEqual(workspace.missingAssets.count, 1)
        XCTAssertEqual(workspace.missingAssets.first?.id, missing.id)
    }

    func testRelinkAssetUpdatesPathAndClearsMissingState() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceRelink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let replacementURL = tempDirectory.appendingPathComponent("replacement.mov")
        try Data([0x01, 0x02, 0x03]).write(to: replacementURL)

        var project = ProjectFactory.starterProject(name: "Relink")
        let asset = MediaAsset(
            name: "OfflineClip",
            path: "/tmp/missing-\(UUID().uuidString).mov",
            type: .video,
            duration: 5
        )
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        XCTAssertEqual(workspace.missingAssets.count, 1)

        workspace.relinkAsset(asset.id, to: replacementURL)

        XCTAssertEqual(workspace.project.assets.first?.path, replacementURL.standardizedFileURL.path())
        XCTAssertTrue(workspace.missingAssets.isEmpty)
    }

    func testExportPresetLookupIncludesCreatorPresets() {
        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "Presets"))

        XCTAssertNotNil(workspace.exportPreset(id: "youtube-1080p-h264"))
        XCTAssertNotNil(workspace.exportPreset(id: "tiktok-1080x1920-h265"))
        XCTAssertNotNil(workspace.exportPreset(id: "reels-1080x1920-h264"))
    }

    func testEnqueueExportUsesRequestedPresetID() {
        var project = ProjectFactory.starterProject(name: "ExportPreset")
        let asset = MediaAsset(name: "Clip", path: "/tmp/export-preset.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()
        workspace.enqueueExport(presetID: "tiktok-1080x1920-h265")

        XCTAssertEqual(workspace.exportStatusMessage, "Rendering tiktok-1080x1920-h265")
        XCTAssertTrue(workspace.statusMessage.contains("tiktok-1080x1920-h265"))
    }

    func testCompletedExportCreatesHistoryItem() async throws {
        var project = ProjectFactory.starterProject(name: "ExportHistory")
        let asset = MediaAsset(name: "Clip", path: "/tmp/export-history.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.appendFirstAssetToTimeline()
        workspace.enqueueExport(presetID: "youtube-1080p-h264")
        workspace.exportProgress = 0.97

        try await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(workspace.exportStatusMessage, "Completed")
        XCTAssertEqual(workspace.exportHistory.count, 1)
        XCTAssertEqual(workspace.exportHistory.first?.presetID, "youtube-1080p-h264")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.exportHistory.first?.outputURL.path ?? ""))
    }

    func testOpenProjectRestoresExportHistoryFromDisk() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistedExportHistory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let bundleURL = tempDirectory.appendingPathComponent("Project.pcloneproj", isDirectory: true)

        var project = ProjectFactory.starterProject(name: "PersistedHistory")
        let asset = MediaAsset(name: "Clip", path: "/tmp/export-persisted.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.saveProjectAs(to: bundleURL)
        workspace.appendFirstAssetToTimeline()
        workspace.enqueueExport(presetID: "reels-1080x1920-h264")
        workspace.exportProgress = 0.97

        try await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(workspace.exportHistory.count, 1)

        let reopened = EditorWorkspace(project: ProjectFactory.starterProject(name: "Reload"))
        reopened.openProject(at: bundleURL)

        XCTAssertEqual(reopened.exportHistory.count, 1)
        XCTAssertEqual(reopened.exportHistory.first?.presetID, "reels-1080x1920-h264")
    }

    func testRecentProjectsUpdatesOnSaveAndOpen() throws {
        let suiteName = "RecentProjectsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentProjects-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let bundleURL = tempDirectory.appendingPathComponent("Project.pcloneproj", isDirectory: true)
        let project = ProjectFactory.starterProject(name: "RecentProject")

        let workspace = EditorWorkspace(project: project, userDefaults: defaults)
        workspace.saveProjectAs(to: bundleURL)

        XCTAssertEqual(workspace.recentProjects.count, 1)
        XCTAssertEqual(workspace.recentProjects.first?.path, bundleURL.standardizedFileURL.path)

        let reopened = EditorWorkspace(project: ProjectFactory.starterProject(name: "Reload"), userDefaults: defaults)
        reopened.openProject(at: bundleURL)

        XCTAssertEqual(reopened.recentProjects.count, 1)
        XCTAssertEqual(reopened.recentProjects.first?.path, bundleURL.standardizedFileURL.path)
    }

    func testRestoreLatestAutosaveRestoresProjectState() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreAutosave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let bundleURL = tempDirectory.appendingPathComponent("Project.pcloneproj", isDirectory: true)

        var project = ProjectFactory.starterProject(name: "AutosaveRestore")
        let asset = MediaAsset(name: "Clip", path: "/tmp/autosave-restore.mp4", type: .video, duration: 4)
        project.assets = [asset]

        let workspace = EditorWorkspace(project: project)
        workspace.saveProjectAs(to: bundleURL)
        workspace.appendFirstAssetToTimeline()

        let autosaveURL = try ProjectStore().autosave(project: workspace.project, to: bundleURL)
        XCTAssertEqual(workspace.latestAvailableAutosaveURL?.lastPathComponent, autosaveURL.lastPathComponent)

        workspace.createSequence(named: "Scratch")
        XCTAssertEqual(workspace.project.sequences.count, 2)

        workspace.restoreLatestAutosave()

        XCTAssertEqual(workspace.project.sequences.count, 1)
        XCTAssertEqual(workspace.activeSequence?.videoTracks.first?.clips.count, 1)
        XCTAssertEqual(workspace.lastAutosaveURL?.lastPathComponent, autosaveURL.lastPathComponent)
        XCTAssertTrue(workspace.statusMessage.contains("Restored latest autosave"))
    }

    func testRestoreLatestAutosaveRequiresSavedProject() {
        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "UnsavedAutosave"))

        workspace.restoreLatestAutosave()

        XCTAssertEqual(workspace.statusMessage, "Save or open a project before restoring autosave")
    }

    func testPreviewMuteAndVolumeInteraction() {
        let workspace = EditorWorkspace(project: ProjectFactory.starterProject(name: "PreviewAudio"))
        XCTAssertFalse(workspace.isPreviewMuted)
        XCTAssertEqual(workspace.previewVolume, 1.0, accuracy: 0.0001)

        workspace.togglePreviewMute()
        XCTAssertTrue(workspace.isPreviewMuted)

        workspace.updatePreviewVolume(0.6)
        XCTAssertFalse(workspace.isPreviewMuted)
        XCTAssertEqual(workspace.previewVolume, 0.6, accuracy: 0.0001)
    }
}
#endif
