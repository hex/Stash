// ABOUTME: Menu bar popover content showing recent clipboard entries and controls.
// ABOUTME: Live-updating SwiftUI view for .window style MenuBarExtra.

import SwiftUI
import SwiftData

struct MenuBarView: View {
    let storage: StorageManager
    let preferences: Preferences
    let onPaste: (ClipboardEntry) -> Void
    let onOpenPanel: () -> Void
    let onPauseChanged: (Bool) -> Void

    @State private var copiedEntryID: PersistentIdentifier?
    @State private var hoveredEntryID: PersistentIdentifier?

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
                            let isCopied = copiedEntryID == entry.persistentModelID
                            let isHovered = hoveredEntryID == entry.persistentModelID

                            EntryRowView(entry: entry, isSelected: false)
                                .opacity(isCopied ? 0 : 1)
                                .overlay {
                                    if isCopied {
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                            Text("Copied")
                                                .foregroundStyle(.green)
                                        }
                                        .font(.body)
                                    }
                                }
                            .background(
                                isCopied ? Color.green.opacity(0.1) :
                                isHovered ? Color.primary.opacity(0.06) :
                                Color.clear
                            )
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                            .onTapGesture { copyEntry(entry) }
                            .onHover { hovering in
                                hoveredEntryID = hovering ? entry.persistentModelID : nil
                            }
                            .help(tooltipText(for: entry))
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

    private func copyEntry(_ entry: ClipboardEntry) {
        onPaste(entry)
        withAnimation(.easeIn(duration: 0.15)) {
            copiedEntryID = entry.persistentModelID
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) {
                copiedEntryID = nil
            }
        }
    }

    private func tooltipText(for entry: ClipboardEntry) -> String {
        switch entry.contentType {
        case .image: return "Image (\(entry.sourceAppName ?? "Unknown"))"
        case .fileURL:
            return entry.filePaths?.joined(separator: "\n") ?? "[File]"
        default:
            return String((entry.plainText ?? "").prefix(500))
        }
    }
}
