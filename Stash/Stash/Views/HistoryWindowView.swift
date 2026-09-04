// ABOUTME: Full-history browser — a resizable window listing every stored entry with search.
// ABOUTME: Shares EntryRowView and HistoryFilter with the popover rather than duplicating them.

import SwiftUI
import SwiftData

struct HistoryWindowView: View {
    let storage: StorageManager
    let preferences: Preferences
    let onPaste: (ClipboardItem) -> Bool

    @State private var entries: [ClipboardItem] = []
    @State private var query = ""
    @State private var copiedEntryID: PersistentIdentifier?

    private var visibleEntries: [ClipboardItem] {
        HistoryFilter.apply(entries, query: query)
    }

    var body: some View {
        let visible = visibleEntries

        VStack(spacing: 0) {
            header(matchCount: visible.count)
            Divider()

            if visible.isEmpty {
                emptyState
            } else {
                list(visible)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .preferredColorScheme(preferences.appearance == .auto ? nil
                              : (preferences.appearance == .dark ? .dark : .light))
        .task(id: storage.changeCount) {
            entries = (try? storage.fetchAll()) ?? []
        }
    }

    // MARK: - Header

    private func header(matchCount: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            TextField("Search history", text: $query)
                .textFieldStyle(.plain)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }

            Text(countLabel(matchCount))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func countLabel(_ matchCount: Int) -> String {
        let noun = matchCount == 1 ? "entry" : "entries"
        return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(matchCount) \(noun)"
            : "\(matchCount) of \(entries.count)"
    }

    // MARK: - List

    private func list(_ visible: [ClipboardItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let lastID = visible.last?.id
                ForEach(visible) { entry in
                    let action = actionFor(entry)
                    EntryRowView(
                        entry: entry,
                        isTopmost: false,
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
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
    }

    private var emptyState: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 8) {
            Spacer()
            Image(systemName: searching ? "magnifyingglass" : "tray")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(searching ? "No matches" : "No clipboard history")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func copyEntry(_ entry: ClipboardItem) {
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
