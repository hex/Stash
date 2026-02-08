// ABOUTME: Menu bar popover content showing recent clipboard entries and controls.
// ABOUTME: Live-updating SwiftUI view for .window style MenuBarExtra.

import SwiftUI
import SwiftData

struct MenuBarView: View {
    let storage: StorageManager
    let preferences: Preferences
    let onPaste: (ClipboardEntry) -> Void
    let onPauseChanged: (Bool) -> Void
    let onOpenSettings: () -> Void

    @State private var copiedEntryID: PersistentIdentifier?
    @State private var hoveredEntryID: PersistentIdentifier?
    @State private var isConfirmingQuit = false

    var body: some View {
        let _ = storage.changeCount
        let entries = (try? storage.fetchAll()) ?? []

        VStack(spacing: 0) {
            if entries.isEmpty {
                emptyState
            } else {
                entryList(entries)
            }

            Divider()

            controlBar
        }
        .frame(width: 340, height: 400)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No clipboard history")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("Copy something to get started")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - Entry List

    private func entryList(_ entries: [ClipboardEntry]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let displayed = Array(entries.prefix(10))
                ForEach(Array(displayed.enumerated()), id: \.element.persistentModelID) { index, entry in
                    let isCopied = copiedEntryID == entry.persistentModelID
                    let isHovered = hoveredEntryID == entry.persistentModelID

                    EntryRowView(entry: entry)
                        .opacity(isCopied ? 0 : 1)
                        .overlay {
                            if isCopied {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Copied")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    isCopied ? Color.green.opacity(0.12) :
                                    isHovered ? Color.accentColor.opacity(0.15) :
                                    Color.clear
                                )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { copyEntry(entry) }
                        .onHover { hovering in
                            hoveredEntryID = hovering ? entry.persistentModelID : nil
                        }
                        .contextMenu {
                            Button("Copy") { copyEntry(entry) }

                            Button(entry.isPinned ? "Unpin" : "Pin") {
                                try? storage.togglePin(entryWithID: entry.persistentModelID)
                            }

                            if entry.contentType == .image, entry.imageData != nil {
                                Button("Preview") { previewImage(entry) }
                            }

                            Divider()

                            Button("Delete", role: .destructive) {
                                try? storage.delete(entryWithID: entry.persistentModelID)
                            }
                        }
                        .help(tooltipText(for: entry))

                    if index < displayed.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.automatic)
        .contentMargins(.vertical, 6, for: .scrollIndicators)
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gear")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")

            Spacer()

            Toggle("Pause", isOn: Binding(
                get: { preferences.isPaused },
                set: { onPauseChanged($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()

            Button {
                isConfirmingQuit = true
            } label: {
                Image(systemName: "power")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Quit Stash")
            .confirmationDialog("Quit Stash?", isPresented: $isConfirmingQuit) {
                Button("Quit", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

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

    private func previewImage(_ entry: ClipboardEntry) {
        guard let data = entry.imageData else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stash-preview.png")
        try? data.write(to: url)
        NSWorkspace.shared.open(url)
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
