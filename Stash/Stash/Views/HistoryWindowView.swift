// ABOUTME: Full-history browser — a resizable window listing every stored entry with search.
// ABOUTME: Shares its rows, actions, and filter with the popover via EntryListView.

import SwiftUI
import SwiftData

struct HistoryWindowView: View {
    let storage: StorageManager
    let preferences: Preferences
    let onPaste: (ClipboardItem) -> Bool

    @State private var entries: [ClipboardItem] = []
    @State private var query = ""

    @State private var matches: [ClipboardItem] = []

    private var visibleEntries: [ClipboardItem] {
        HistoryFilter.isSearching(query) ? matches : entries
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
        return HistoryFilter.isSearching(query)
            ? "\(matchCount) of \(entries.count)"
            : "\(matchCount) \(noun)"
    }

    // MARK: - List

    private func list(_ visible: [ClipboardItem]) -> some View {
        ScrollView {
            EntryListView(entries: visible, storage: storage, onPaste: onPaste)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
        }
    }

    private var emptyState: some View {
        let searching = HistoryFilter.isSearching(query)
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
}
