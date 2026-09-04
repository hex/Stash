// ABOUTME: Menu bar popover — Native + Quiet design, system fonts, system accent, no themed colors.
// ABOUTME: Inherits the user's macOS preferences (light/dark, accent, contrast) without override.

import SwiftUI
import SwiftData

struct MenuBarView: View {
    let storage: StorageManager
    let preferences: Preferences
    let onPaste: (ClipboardItem) -> Bool
    let onPauseChanged: (Bool) -> Void
    let onOpenSettings: () -> Void
    let onOpenHistory: () -> Void

    @State private var copiedEntryID: PersistentIdentifier?
    @State private var metrics = ScrollMetrics()
    @State private var entries: [ClipboardItem] = []
    @State private var query = ""

    /// An empty query shows a short quick-access list; a search reaches the whole
    /// history, since the point of searching is to find what scrolling would not.
    private var visibleEntries: [ClipboardItem] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Array(entries.prefix(preferences.popoverEntryCount))
            : HistoryFilter.apply(entries, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !entries.isEmpty {
                searchField
                Divider()
            }

            let visible = visibleEntries
            if visible.isEmpty {
                emptyState
            } else {
                entryList(visible)
            }

            Divider()

            bottomToolbar
        }
        .frame(width: 380, height: 400)
        .background(
            Color(NSColor(name: nil, dynamicProvider: { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(red: 0.106, green: 0.115, blue: 0.149, alpha: 1) // #1B1D26
                    : NSColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1) // #F6F7F9
            }))
        )
        .preferredColorScheme(preferences.appearance == .auto ? nil
                              : (preferences.appearance == .dark ? .dark : .light))
        .task(id: storage.changeCount) {
            entries = (try? storage.fetchAll()) ?? []
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .tooltip("Settings", anchor: .leading)

            Button {
                onOpenHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .tooltip("Show full history", anchor: .leading)

            Spacer()

            Toggle(preferences.isPaused ? "Paused" : "Recording", isOn: Binding(
                get: { !preferences.isPaused },
                set: { onPauseChanged(!$0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.caption)
            .foregroundStyle(.secondary)
            .tint(.blue)
            .tooltip(preferences.isPaused ? "Paused — toggle to resume" : "Recording — toggle to pause")

            Button {
                confirmAndQuit()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.34, blue: 0.34))
            }
            .buttonStyle(.plain)
            .tooltip("Quit Stash", anchor: .trailing)
            .contextMenu {
                Button("Clear All History", role: .destructive) {
                    confirmAndClear()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 8) {
            Spacer()
            Image(systemName: searching ? "magnifyingglass" : "tray")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(searching ? "No matches" : "No clipboard history")
                .font(.body)
                .foregroundStyle(.secondary)
            Text(searching ? "Try a different search" : "Copy something to get started")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .tooltip("Clear search", edge: .bottom, anchor: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Entry list

    private func entryList(_ entries: [ClipboardItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let firstID = entries.first?.id
                let lastID = entries.last?.id
                ForEach(entries) { entry in
                    let action = actionFor(entry)
                    EntryRowView(
                        entry: entry,
                        isTopmost: entry.id == firstID,
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
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geo in
            metrics.offset = geo.contentOffset.y
            metrics.contentHeight = geo.contentSize.height
            metrics.viewportHeight = geo.bounds.height
        }
        .onScrollPhaseChange { _, newPhase in
            metrics.isScrolling = newPhase != .idle
        }
        .overlay(alignment: .topTrailing) {
            ScrollIndicator(metrics: metrics)
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

    // MARK: - Modal confirmations (NSAlert bypasses SwiftUI dialog wedging in popovers)

    private func confirmAndQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit Stash?"
        alert.addButton(withTitle: "Quit").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            if preferences.clearOnQuit {
                try? storage.deleteAll()
            }
            NSApp.terminate(nil)
        }
    }

    private func confirmAndClear() {
        let alert = NSAlert()
        alert.messageText = "Clear All History?"
        alert.informativeText = "This will permanently delete every entry, including pinned items."
        alert.addButton(withTitle: "Clear All").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            try? storage.deleteAll()
        }
    }
}

/// Scroll geometry lives here rather than in `MenuBarView`'s own state. `@Observable`
/// invalidates only the views that *read* a property, so the per-frame geometry writes
/// reach `ScrollIndicator` alone and never rebuild the entry list behind it.
@Observable
private final class ScrollMetrics {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var isScrolling = false
}

private struct ScrollIndicator: View {
    let metrics: ScrollMetrics

    var body: some View {
        let contentHeight = metrics.contentHeight
        let viewportHeight = metrics.viewportHeight
        let needsScroll = contentHeight > viewportHeight + 1
        let viewportRatio = min(max(viewportHeight / max(contentHeight, 1), 0.1), 1.0)
        let indicatorHeight = max(viewportHeight * viewportRatio, 24)
        let trackRange = max(viewportHeight - indicatorHeight, 0)
        let scrollableRange = max(contentHeight - viewportHeight, 1)
        let progress = min(max(metrics.offset / scrollableRange, 0), 1)

        Capsule()
            .fill(.primary.opacity(0.30))
            .frame(width: 3, height: indicatorHeight)
            .padding(.trailing, 3)
            .offset(y: progress * trackRange)
            .opacity(needsScroll && metrics.isScrolling ? 1 : 0)
            .animation(.easeOut(duration: 0.4), value: metrics.isScrolling)
            .allowsHitTesting(false)
    }
}
