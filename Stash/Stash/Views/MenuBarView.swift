// ABOUTME: Menu bar dropdown content showing recent clipboard entries and controls.
// ABOUTME: Provides quick access to pause, settings, and quit actions.

import SwiftUI

struct MenuBarView: View {
    let storage: StorageManager
    let preferences: Preferences
    let onPaste: (ClipboardEntry) -> Void
    let onOpenPanel: () -> Void

    @State private var recentEntries: [ClipboardEntry] = []

    var body: some View {
        ForEach(recentEntries.prefix(5), id: \.persistentModelID) { entry in
            Button {
                onPaste(entry)
            } label: {
                Text(menuLabel(for: entry))
                    .lineLimit(1)
            }
        }

        if recentEntries.isEmpty {
            Text("No clipboard history")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Open Stash...") {
            onOpenPanel()
        }
        .keyboardShortcut("o")

        Divider()

        Toggle("Pause Monitoring", isOn: Binding(
            get: { preferences.isPaused },
            set: { preferences.isPaused = $0 }
        ))

        Divider()

        Button("Quit Stash") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func menuLabel(for entry: ClipboardEntry) -> String {
        switch entry.contentType {
        case .image:
            return "[Image]"
        case .fileURL:
            if let paths = entry.filePaths {
                return paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            }
            return entry.plainText ?? "[File]"
        default:
            let text = entry.plainText ?? ""
            return String(text.prefix(60))
        }
    }
}
