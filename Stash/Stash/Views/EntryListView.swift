// ABOUTME: The clipboard entry list shared by the popover and the history window.
// ABOUTME: Owns row actions, the context menu, and the copied-flash state.

import SwiftUI
import SwiftData

/// Both surfaces render the same rows with the same actions; only the scroll container
/// around them differs, so the hosts keep the ScrollView and share everything inside it.
struct EntryListView: View {
    let entries: [ClipboardItem]
    let storage: StorageManager
    let onPaste: (ClipboardItem) -> Bool

    @State private var copiedEntryID: PersistentIdentifier?

    /// The entry currently on the pasteboard. Pinned rows sort first, so position no
    /// longer identifies it — only the timestamp does.
    private var mostRecentID: PersistentIdentifier? {
        entries.max(by: { $0.timestamp < $1.timestamp })?.id
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            let newestID = mostRecentID
            let lastID = entries.last?.id
            ForEach(entries) { entry in
                let action = actionFor(entry)
                EntryRowView(
                    entry: entry,
                    isMostRecent: entry.id == newestID,
                    isCopied: copiedEntryID == entry.id,
                    action: action,
                    loadImageData: { try? storage.imageData(for: entry.id) }
                )
                .contentShape(Rectangle())
                .onTapGesture { copyEntry(entry) }
                .contextMenu {
                    Button("Copy") { copyEntry(entry) }
                    Button(entry.isPinned ? "Unpin" : "Pin") {
                        try? storage.togglePin(entryWithID: entry.id)
                    }
                    if let action {
                        Button(action.label) { action.perform() }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        try? storage.delete(entryWithID: entry.id)
                    }
                }

                if entry.id != lastID {
                    Divider()
                }
            }
        }
    }

    // MARK: - Actions

    private func copyEntry(_ entry: ClipboardItem) {
        // A row pruned since the last refresh has no payload left to load, and the
        // affirmation must not claim a copy that did not happen.
        guard onPaste(entry) else { return }
        withAnimation(.easeIn(duration: 0.15)) {
            copiedEntryID = entry.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) {
                copiedEntryID = nil
            }
        }
    }

    private func actionFor(_ entry: ClipboardItem) -> EntryRowView.Action? {
        switch entry.contentType {
        case .image:
            return EntryRowView.Action(label: "Preview", systemImage: "eye") {
                guard let data = try? storage.imageData(for: entry.id) else { return }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("stash-preview")
                    .appendingPathExtension(ImageFormat.fileExtension(of: data))
                try? data.write(to: url)
                NSWorkspace.shared.open(url)
            }
        case .fileURL:
            guard let path = entry.filePaths?.first,
                  FileManager.default.fileExists(atPath: path) else { return nil }
            return EntryRowView.Action(label: "Preview", systemImage: "eye") {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        case .url:
            guard let urlString = entry.urlString,
                  let url = URL(string: urlString) else { return nil }
            return EntryRowView.Action(label: "Open", systemImage: "arrow.up.right.square") {
                NSWorkspace.shared.open(url)
            }
        default:
            return nil
        }
    }
}
