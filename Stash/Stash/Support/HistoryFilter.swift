// ABOUTME: Pure search filter over clipboard items, shared by the popover and the history window.
// ABOUTME: No storage or view dependencies, so it is testable in isolation.

import Foundation

enum HistoryFilter {
    static func apply(_ items: [ClipboardItem], query: String) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { matches($0, query: trimmed) }
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
