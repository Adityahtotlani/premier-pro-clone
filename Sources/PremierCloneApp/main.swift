import SwiftUI
import AppShell

@main
struct PremierCloneApplication: App {
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
