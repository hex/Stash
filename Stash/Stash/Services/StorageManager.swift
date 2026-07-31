// ABOUTME: Manages SwiftData persistence for clipboard entries with field-level encryption.
// ABOUTME: Handles CRUD, consecutive dedup, history limit enforcement, and encrypted storage.

import Foundation
import SwiftData

@MainActor
@Observable
final class StorageManager {
    let container: ModelContainer
    let context: ModelContext
    let crypto: CryptoService
    var historyLimit: Int = 500
    /// Incremented on every mutation so SwiftUI views re-evaluate when data changes.
    private(set) var changeCount: Int = 0

    init(inMemory: Bool = false, crypto: CryptoService = CryptoService()) {
        let schema = Schema([ClipboardEntry.self])
        let config = ModelConfiguration("Stash", schema: schema, isStoredInMemoryOnly: inMemory)
        self.container = try! ModelContainer(for: schema, configurations: [config])
        self.context = ModelContext(container)
        self.crypto = crypto

        if !inMemory {
            excludeStoreFromTimeMachine()
        }
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

        // Encrypt content fields before persisting (hash was computed from plaintext above)
        entry.plainText = plainText.flatMap { try? crypto.encrypt($0) }
        entry.urlString = urlString.flatMap { try? crypto.encrypt($0) }
        if let json = entry.filePathsJSON {
            entry.filePathsJSON = try? crypto.encrypt(json)
        }
        entry.imageData = imageData.flatMap { try? crypto.encrypt(data: $0) }
        entry.richTextData = richTextData.flatMap { try? crypto.encrypt(data: $0) }

        context.insert(entry)
        try context.save()
        try enforceHistoryLimit()
        changeCount += 1
        return entry
    }

    func fetchAll() throws -> [ClipboardItem] {
        // Decrypt in a throwaway read context, then return value-type snapshots.
        // The managed objects and their context deallocate when this returns, so
        // views hold no reference back into SwiftData's object graph.
        let readContext = ModelContext(container)
        var descriptor = FetchDescriptor<ClipboardEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = historyLimit
        let entries = try readContext.fetch(descriptor)

        return entries.map { entry in
            entry.plainText = decryptString(entry.plainText)
            entry.urlString = decryptString(entry.urlString)
            entry.filePathsJSON = decryptString(entry.filePathsJSON)
            entry.imageData = decryptData(entry.imageData)
            entry.richTextData = decryptData(entry.richTextData)
            return ClipboardItem(entry)
        }
    }

    func delete(entryWithID id: PersistentIdentifier) throws {
        guard let entry = try fetchEntry(for: id, in: context) else { return }
        context.delete(entry)
        try context.save()
        changeCount += 1
    }

    func togglePin(entryWithID id: PersistentIdentifier) throws {
        guard let entry = try fetchEntry(for: id, in: context) else { return }
        entry.isPinned.toggle()
        try context.save()
        changeCount += 1
    }

    func deleteAll() throws {
        try context.delete(model: ClipboardEntry.self)
        try context.save()
        changeCount += 1
    }

    /// Deletes unpinned entries older than the given number of days.
    /// Returns the number of entries deleted. 0 days means "forever" (no-op).
    @discardableResult
    func deleteExpired(olderThanDays days: Int) throws -> Int {
        guard days > 0 else { return 0 }

        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let expired = #Predicate<ClipboardEntry> { !$0.isPinned && $0.timestamp < cutoff }
        // delete(model:where:) reports no count, and callers need one.
        let count = try context.fetchCount(FetchDescriptor(predicate: expired))
        if count > 0 {
            try context.delete(model: ClipboardEntry.self, where: expired)
            try context.save()
            changeCount += 1
        }
        return count
    }

    // MARK: - Private

    /// Fetches one entry by id, or nil if its row no longer exists.
    ///
    /// `model(for:)` never returns nil: for a deleted row it hands back a shell whose first
    /// attribute access traps with "This model instance was invalidated because its backing
    /// data could no longer be found the store". The shell is indistinguishable from a live
    /// model without touching an attribute, and `isDeleted` is context state, so it reads
    /// false for both. Existence is therefore established first via `fetchIdentifiers`,
    /// which materialises no models and reads no blob columns. Callers and every mutation
    /// are `@MainActor` and synchronous, so the check cannot interleave with a delete.
    private func fetchEntry(for id: PersistentIdentifier, in context: ModelContext) throws -> ClipboardEntry? {
        let ids = try context.fetchIdentifiers(FetchDescriptor<ClipboardEntry>())
        guard ids.contains(id) else { return nil }
        return context.model(for: id) as? ClipboardEntry
    }

    /// Decrypts a string, falling back to the original value for pre-encryption data.
    private func decryptString(_ value: String?) -> String? {
        guard let value else { return nil }
        return (try? crypto.decrypt(value)) ?? value
    }

    /// Decrypts data, falling back to the original value for pre-encryption data.
    private func decryptData(_ value: Data?) -> Data? {
        guard let value else { return nil }
        return (try? crypto.decrypt(data: value)) ?? value
    }

    private func excludeStoreFromTimeMachine() {
        guard let storeURL = container.configurations.first?.url else { return }
        let dir = storeURL.deletingLastPathComponent()
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(resourceValues)
    }

    private func fetchMostRecent() throws -> ClipboardEntry? {
        var descriptor = FetchDescriptor<ClipboardEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Runs on every save, so it counts rather than materialising the whole history.
    private func enforceHistoryLimit() throws {
        let pinnedCount = try context.fetchCount(
            FetchDescriptor<ClipboardEntry>(predicate: #Predicate { $0.isPinned })
        )

        // Only prune unpinned entries; pinned count doesn't matter
        var overflow = FetchDescriptor<ClipboardEntry>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        overflow.fetchOffset = max(0, historyLimit - pinnedCount)

        let toDelete = try context.fetch(overflow)
        guard !toDelete.isEmpty else { return }
        for entry in toDelete {
            context.delete(entry)
        }
        try context.save()
    }
}
