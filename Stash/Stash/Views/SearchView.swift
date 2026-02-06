// ABOUTME: Root view for the floating panel: search field, content filter, and entry list.
// ABOUTME: Keyboard-driven: arrows navigate, Enter selects, Esc dismisses, Cmd+1-9 quick select.

import SwiftUI
import SwiftData

struct SearchView: View {
    let storage: StorageManager
    let openCount: OpenCount
    let onSelect: (ClipboardEntry) -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var entries: [ClipboardEntry] = []
    @State private var filterType: ContentType?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            filterBar
            Divider()
            entryList

            if entries.isEmpty {
                Spacer()
                Text(searchText.isEmpty ? "No clipboard history yet" : "No matching entries")
                    .foregroundStyle(.secondary)
                    .font(.body)
                Spacer()
            }
        }
        .frame(width: 640, height: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            resetState()
        }
        .onChange(of: openCount.value) { _, _ in
            resetState()
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.title3.bold())
                .focused($isSearchFocused)
                .onChange(of: searchText) { _, _ in
                    selectedIndex = 0
                    refreshEntries()
                }
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.return) {
                    selectCurrent()
                    return .handled
                }
                .onKeyPress(.escape) {
                    NSApp.keyWindow?.orderOut(nil)
                    return .handled
                }
                .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                    handleQuickSelect(press)
                }
        }
        .padding(12)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterChip("All", type: nil)
            filterChip("Text", type: .plainText)
            filterChip("Rich", type: .richText)
            filterChip("Images", type: .image)
            filterChip("Files", type: .fileURL)
            filterChip("URLs", type: .url)
            Spacer()
            Text("\(entries.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func filterChip(_ label: String, type: ContentType?) -> some View {
        Button(label) {
            filterType = type
            selectedIndex = 0
            refreshEntries()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(filterType == type ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .font(.caption)
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(entries.enumerated()), id: \.element.persistentModelID) { index, entry in
                        HStack(spacing: 4) {
                            if index < 9 {
                                Text("\(index + 1)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 16)
                            } else {
                                Spacer().frame(width: 16)
                            }

                            EntryRowView(entry: entry, isSelected: index == selectedIndex)
                        }
                        .id(index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(entry)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
    }

    private func resetState() {
        searchText = ""
        selectedIndex = 0
        refreshEntries()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isSearchFocused = true
        }
    }

    private func refreshEntries() {
        do {
            var result = try storage.fetchAll()
            if !searchText.isEmpty {
                let lowered = searchText.lowercased()
                result = result.filter { $0.plainText?.localizedCaseInsensitiveContains(lowered) == true }
            }
            if let type = filterType {
                result = result.filter { $0.contentType == type }
            }
            entries = result
        } catch {
            entries = []
        }
    }

    private func moveSelection(by delta: Int) {
        let newIndex = selectedIndex + delta
        if newIndex >= 0 && newIndex < entries.count {
            selectedIndex = newIndex
        }
    }

    private func selectCurrent() {
        guard selectedIndex >= 0 && selectedIndex < entries.count else { return }
        onSelect(entries[selectedIndex])
    }

    /// Cmd+1 through Cmd+9 for quick entry selection
    private func handleQuickSelect(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command) else { return .ignored }
        guard let digit = press.characters.first?.wholeNumberValue,
              digit >= 1 && digit <= 9 else { return .ignored }

        let index = digit - 1
        guard index < entries.count else { return .ignored }
        onSelect(entries[index])
        return .handled
    }
}
