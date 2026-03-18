import SwiftUI
import AppShell
#if canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)
final class PremierCloneAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
#endif

@main
struct PremierCloneApplication: App {
    #if canImport(AppKit)
    @NSApplicationDelegateAdaptor(PremierCloneAppDelegate.self)
    private var appDelegate
    #endif
    @StateObject private var workspace = EditorWorkspace()

    var body: some Scene {
        WindowGroup("Premier Clone") {
            EditorRootView()
                .environmentObject(workspace)
        }
        .commands {
            CommandMenu("File") {
                Button("New Project") {
                    EditorCommand.post(EditorCommand.newProject)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Project") {
                    EditorCommand.post(EditorCommand.openProject)
                }
                .keyboardShortcut("o", modifiers: .command)

                if !workspace.recentProjects.isEmpty {
                    Menu("Open Recent") {
                        ForEach(Array(workspace.recentProjects.prefix(5).enumerated()), id: \.element.id) { index, recent in
                            let shortcut = KeyEquivalent(Character("\(index + 1)"))
                            Button(recent.name) {
                                workspace.openRecentProject(recent)
                            }
                            .keyboardShortcut(shortcut, modifiers: [.command, .option])
                            Button("Reveal \(recent.name)") {
                                workspace.revealRecentProject(recent)
                            }
                            Button("Remove \(recent.name)") {
                                workspace.removeRecentProject(recent)
                            }
                        }
                        Divider()
                        Button("Clear Recent Projects") {
                            workspace.clearRecentProjects()
                        }
                    }
                }

                Button("Save Project") {
                    EditorCommand.post(EditorCommand.saveProject)
                }
                .keyboardShortcut("s", modifiers: .command)

                Divider()

                Button("Import Media") {
                    EditorCommand.post(EditorCommand.importMedia)
                }
                .keyboardShortcut("i", modifiers: .command)

                Divider()

                Button("Create Proxy Manifest") {
                    EditorCommand.post(EditorCommand.generateProxyManifest)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Button("Restore Latest Autosave") {
                    EditorCommand.post(EditorCommand.restoreLatestAutosave)
                }

                Button("Relink First Missing Media") {
                    EditorCommand.post(EditorCommand.relinkFirstMissingAsset)
                }

                Button("Retry Last Export") {
                    EditorCommand.post(EditorCommand.retryLatestExport)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Open Last Export") {
                    EditorCommand.post(EditorCommand.openLatestExport)
                }

                Button("Reveal Last Export") {
                    EditorCommand.post(EditorCommand.revealLatestExport)
                }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
            }

            CommandMenu("Edit") {
                Button("Undo") {
                    EditorCommand.post(EditorCommand.undo)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    EditorCommand.post(EditorCommand.redo)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Divider()

                Button("Append Selected Asset") {
                    EditorCommand.post(EditorCommand.appendFirstAsset)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Split Selected Clip") {
                    EditorCommand.post(EditorCommand.splitFirstClip)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Ripple Delete Selected Clip") {
                    EditorCommand.post(EditorCommand.rippleDeleteFirstClip)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }

            CommandMenu("Timeline") {
                Button("New Sequence") {
                    EditorCommand.post(EditorCommand.newSequence)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Button("Duplicate Sequence") {
                    EditorCommand.post(EditorCommand.duplicateSequence)
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Divider()

                Button("Add Video Track") {
                    EditorCommand.post(EditorCommand.addVideoTrack)
                }
                .keyboardShortcut("v", modifiers: [.command, .option, .shift])

                Button("Add Audio Track") {
                    EditorCommand.post(EditorCommand.addAudioTrack)
                }
                .keyboardShortcut("a", modifiers: [.command, .option, .shift])

                Button("Toggle Insert/Overwrite") {
                    EditorCommand.post(EditorCommand.toggleTimelineEditMode)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Divider()

                Button("Add Marker") {
                    EditorCommand.post(EditorCommand.addMarker)
                }
                .keyboardShortcut("m", modifiers: .command)

                Button("Jump To Next Marker") {
                    EditorCommand.post(EditorCommand.nextMarker)
                }
                .keyboardShortcut("'", modifiers: .command)

                Divider()

                Button("Toggle Track/Magnetic Mode") {
                    EditorCommand.post(EditorCommand.toggleTimelineMode)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }

            CommandMenu("Playback") {
                Button("Play/Pause") {
                    EditorCommand.post(EditorCommand.playPause)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Step Backward Frame") {
                    EditorCommand.post(EditorCommand.stepBackwardFrame)
                }
                .keyboardShortcut(",", modifiers: [])

                Button("Step Forward Frame") {
                    EditorCommand.post(EditorCommand.stepForwardFrame)
                }
                .keyboardShortcut(".", modifiers: [])

                Divider()

                Button("Shuttle Backward") {
                    EditorCommand.post(EditorCommand.shuttleBackward)
                }
                .keyboardShortcut("j", modifiers: [])

                Button("Shuttle Stop") {
                    EditorCommand.post(EditorCommand.shuttleStop)
                }
                .keyboardShortcut("k", modifiers: [])

                Button("Shuttle Forward") {
                    EditorCommand.post(EditorCommand.shuttleForward)
                }
                .keyboardShortcut("l", modifiers: [])

                Divider()

                Button("Previous Edit Point") {
                    EditorCommand.post(EditorCommand.previousEditPoint)
                }
                .keyboardShortcut(.leftArrow, modifiers: .option)

                Button("Next Edit Point") {
                    EditorCommand.post(EditorCommand.nextEditPoint)
                }
                .keyboardShortcut(.rightArrow, modifiers: .option)

                Divider()

                Button("Set In Point") {
                    EditorCommand.post(EditorCommand.setInPoint)
                }
                .keyboardShortcut("i", modifiers: [])

                Button("Set Out Point") {
                    EditorCommand.post(EditorCommand.setOutPoint)
                }
                .keyboardShortcut("o", modifiers: [])

                Button("Clear In/Out Points") {
                    EditorCommand.post(EditorCommand.clearInOutPoints)
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])

                Button("Toggle Loop Playback") {
                    EditorCommand.post(EditorCommand.toggleLoopPlayback)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("Go To Start") {
                    EditorCommand.post(EditorCommand.jumpToStart)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Go To End") {
                    EditorCommand.post(EditorCommand.jumpToEnd)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Divider()

                Button("Cycle Playback Speed") {
                    EditorCommand.post(EditorCommand.cyclePlaybackRate)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Toggle Preview Mute") {
                    EditorCommand.post(EditorCommand.togglePreviewMute)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }

            CommandMenu("View") {
                Button("Toggle Browser Panel") {
                    EditorCommand.post(EditorCommand.toggleBrowserPanel)
                }
                .keyboardShortcut("b", modifiers: [.command, .option])

                Button("Toggle Inspector Panel") {
                    EditorCommand.post(EditorCommand.toggleInspectorPanel)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Divider()

                Button("Move Inspector Left") {
                    EditorCommand.post(EditorCommand.moveInspectorLeft)
                }
                .keyboardShortcut("[", modifiers: [.command, .option])

                Button("Move Inspector Right") {
                    EditorCommand.post(EditorCommand.moveInspectorRight)
                }
                .keyboardShortcut("]", modifiers: [.command, .option])

                Divider()

                Button("Editing Workspace") {
                    EditorCommand.post(EditorCommand.applyEditingWorkspacePreset)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Focused Workspace") {
                    EditorCommand.post(EditorCommand.applyFocusedWorkspacePreset)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button("Captions Workspace") {
                    EditorCommand.post(EditorCommand.applyCaptionsWorkspacePreset)
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

                Divider()

                Button("Reset Workspace Layout") {
                    EditorCommand.post(EditorCommand.resetWorkspaceLayout)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])

                Divider()

                Button("Toggle Shortcut Help") {
                    EditorCommand.post(EditorCommand.toggleShortcutHelp)
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
    }
}
