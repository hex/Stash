// ABOUTME: Manages SwiftData persistence for clipboard entries.
// ABOUTME: Handles CRUD, consecutive dedup, history limit enforcement, and search.

import Foundation
import SwiftData

@MainActor
@Observable
final class StorageManager {
    let container: ModelContainer
    let context: ModelContext
    var historyLimit: Int = 500
    /// Incremented on every mutation so SwiftUI views re-evaluate when data changes.
    private(set) var changeCount: Int = 0

    init(inMemory: Bool = false) {
        let schema = Schema([ClipboardEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        self.container = try! ModelContainer(for: schema, configurations: [config])
        self.context = ModelContext(container)
    }

    /// Saves a new clipboard entry, skipping if it's a consecutive duplicate.
    /// Returns the saved entry, or nil if skipped as duplicate.
    @discardableResult
    func save(
        contentType: ContentType,
        plainText: String? = nil,
        urlString: String? = nil,
        filePaths: [String]? = nil,
        imageData: Data? = nil,
        richTextData: Data? = nil,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) throws -> ClipboardEntry? {
        let hash = ClipboardEntry.computeHash(
            contentType: contentType,
            plainText: plainText,
            imageData: imageData,
            richTextData: richTextData
        )

        // Consecutive dedup: skip if the most recent entry has the same hash
        if let mostRecent = try fetchMostRecent(), mostRecent.contentHash == hash {
            return nil
        }

        let entry = ClipboardEntry(
            contentType: contentType,
            plainText: plainText,
            urlString: urlString,
            filePaths: filePaths,
            imageData: imageData,
            richTextData: richTextData,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )
        context.insert(entry)
        try context.save()
        try enforceHistoryLimit()
        changeCount += 1
        return entry
    }

    func fetchAll() throws -> [ClipboardEntry] {
        var descriptor = FetchDescriptor<ClipboardEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = historyLimit
        return try context.fetch(descriptor)
    }

    func search(_ query: String) throws -> [ClipboardEntry] {
        let lowered = query.lowercased()
        let predicate = #Predicate<ClipboardEntry> { entry in
            entry.plainText?.localizedStandardContains(lowered) == true
        }
        var descriptor = FetchDescriptor<ClipboardEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = historyLimit
        return try context.fetch(descriptor)
    }

    func delete(_ entry: ClipboardEntry) throws {
        context.delete(entry)
        try context.save()
        changeCount += 1
    }

    func deleteAll() throws {
        let entries = try context.fetch(FetchDescriptor<ClipboardEntry>())
        for entry in entries {
            context.delete(entry)
        }
        try context.save()
        changeCount += 1
    }

    // MARK: - Private

    private func fetchMostRecent() throws -> ClipboardEntry? {
        var descriptor = FetchDescriptor<ClipboardEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func enforceHistoryLimit() throws {
        let allEntries = try context.fetch(
            FetchDescriptor<ClipboardEntry>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        )

        let unpinned = allEntries.filter { !$0.isPinned }
        let pinned = allEntries.filter { $0.isPinned }

        // Only prune unpinned entries; pinned count doesn't matter
        let maxUnpinned = max(0, historyLimit - pinned.count)
        if unpinned.count > maxUnpinned {
            let toDelete = unpinned.suffix(from: maxUnpinned)
            for entry in toDelete {
                context.delete(entry)
            }
            try context.save()
        }
    }
}
