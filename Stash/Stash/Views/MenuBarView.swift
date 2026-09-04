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

    @State private var metrics = ScrollMetrics()
    @State private var entries: [ClipboardItem] = []
    @State private var query = ""


    @State private var matches: [ClipboardItem] = []

    /// An empty query shows a short quick-access list; a search reaches the whole
    /// history, since the point of searching is to find what scrolling would not.
    private var visibleEntries: [ClipboardItem] {
        HistoryFilter.isSearching(query)
            ? matches
            : Array(entries.prefix(preferences.popoverEntryCount))
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
        .background(PopoverBackground(appearance: preferences.appearance))
        .preferredColorScheme(preferences.appearance.colorScheme)
        .task(id: storage.changeCount) {
            entries = (try? storage.fetchAll()) ?? []
        }
        // Entries are never truncated, so a query runs over megabytes of text with
        // diacritic folding. Debouncing keeps that off the keystroke path.
        // Keyed on the entries too, or a copy made mid-search would leave stale matches.
        .task(id: SearchKey(query: query, generation: storage.changeCount)) {
            guard HistoryFilter.isSearching(query) else { return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            matches = HistoryFilter.apply(entries, query: query)
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
        let searching = HistoryFilter.isSearching(query)
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
            EntryListView(entries: entries, storage: storage, onPaste: onPaste)
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
