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

    var body: some Scene {
        WindowGroup("Premier Clone") {
            EditorRootView()
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

                Button("Save Project") {
                    EditorCommand.post(EditorCommand.saveProject)
                }
                .keyboardShortcut("s", modifiers: .command)

                Divider()

                Button("Import Media") {
                    EditorCommand.post(EditorCommand.importMedia)
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            CommandMenu("Edit") {
                Button("Append First Asset") {
                    EditorCommand.post(EditorCommand.appendFirstAsset)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Split First Clip") {
                    EditorCommand.post(EditorCommand.splitFirstClip)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Ripple Delete First Clip") {
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

            CommandMenu("View") {
                Button("Toggle Shortcut Help") {
                    EditorCommand.post(EditorCommand.toggleShortcutHelp)
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
    }
}
