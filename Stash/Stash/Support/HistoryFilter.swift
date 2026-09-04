// ABOUTME: Pure search filter over clipboard items, shared by the popover and the history window.
// ABOUTME: No storage or view dependencies, so it is testable in isolation.

import Foundation

enum HistoryFilter {
    static func apply(_ items: [ClipboardItem], query: String) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { matches($0, query: trimmed) }
    }

    /// Whether a query narrows the list. Callers use it to tell "nothing stored" from
    /// "nothing matched", so it has to agree with `apply` on what counts as blank.
    static func isSearching(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func matches(_ item: ClipboardItem, query: String) -> Bool {
        contains(item.plainText, query)
            || contains(item.urlString, query)
            || contains(item.sourceAppName, query)
            || item.filePaths?.contains { contains($0, query) } == true
    }

    /// Folds case and diacritics so "creme" finds "Crème" — clipboard text is arbitrary
    /// prose, and an exact-match search over it is close to useless.
    private static func contains(_ haystack: String?, _ needle: String) -> Bool {
        guard let haystack else { return false }
        return haystack.range(
            of: needle,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }
}

/// Identifies a search result: the query plus the store generation it ran against.
/// Either changing means the previous result no longer describes the history.
struct SearchKey: Equatable {
    let query: String
    let generation: Int
}
