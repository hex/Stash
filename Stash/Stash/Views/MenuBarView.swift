// ABOUTME: Menu bar popover content showing recent clipboard entries and controls.
// ABOUTME: Live-updating SwiftUI view for .window style MenuBarExtra.

import SwiftUI

struct MenuBarView: View {
    let storage: StorageManager
    let preferences: Preferences
    let onPaste: (ClipboardEntry) -> Void
    let onOpenPanel: () -> Void
    let onPauseChanged: (Bool) -> Void

    var body: some View {
        let _ = storage.changeCount
        let entries = (try? storage.fetchAll()) ?? []

        VStack(spacing: 0) {
            if entries.isEmpty {
                Spacer()
                Text("No clipboard history")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(entries.prefix(10)), id: \.persistentModelID) { entry in
                            Button {
                                onPaste(entry)
                            } label: {
                                EntryRowView(entry: entry, isSelected: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            HStack {
                Button("Open Stash...") {
                    onOpenPanel()
                }

                Spacer()

                Toggle("Pause", isOn: Binding(
                    get: { preferences.isPaused },
                    set: { onPauseChanged($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack {
                Spacer()
                Button("Quit Stash") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 320, height: 360)
    }
}
