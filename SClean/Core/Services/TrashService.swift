//
//  TrashService.swift
//  SClean
//
//  Manages in-app trash state (soft delete before permanent deletion)
//

import SwiftUI
import Combine

// MARK: - Trashed Item

/// Represents an item in the trash with timestamp for ordering
struct TrashedItem: Codable, Equatable, Identifiable {
    let assetID: String
    let trashedAt: Date
    
    var id: String { assetID }
    
    init(assetID: String, trashedAt: Date = Date()) {
        self.assetID = assetID
        self.trashedAt = trashedAt
    }
}

// MARK: - Trash Service

/// Manages the in-app Trash - items marked for deletion but not yet permanently removed
@MainActor
final class TrashService: ObservableObject {

    /// Shared instance
    static let shared = TrashService()

    /// All trashed items (ordered by trashedAt, oldest first)
    @Published private(set) var trashedItems: [TrashedItem] = [] {
        didSet { trashedIDSet = Set(trashedItems.map(\.assetID)) }
    }

    /// Last trashed item (for undo)
    @Published private(set) var lastTrashedID: String?

    /// Total count of trashed items
    var trashCount: Int { trashedItems.count }

    /// Mirror of trashedItems IDs, kept in sync via didSet so isTrashed stays O(1)
    /// even when called per-page inside render loops.
    private var trashedIDSet: Set<String> = []

    /// Set of trashed IDs for fast lookup
    var trashedIDs: Set<String> {
        trashedIDSet
    }

    /// Ordered list of trashed asset IDs (oldest first)
    var orderedTrashedIDs: [String] {
        trashedItems.map(\.assetID)
    }

    /// IDs permanently deleted this session (not persisted, resets on app launch)
    private(set) var permanentlyDeletedIDs: Set<String> = []

    /// All IDs to exclude from display (trashed + permanently deleted)
    var excludedIDs: Set<String> {
        trashedIDs.union(permanentlyDeletedIDs)
    }

    private let userDefaultsKey = "SlideClean.trashedItems"

    // Legacy key for migration
    private let legacyUserDefaultsKey = "SClean.trashedAssetIDs"

    // Dependencies for testability
    private let storage: KeyValueStoring
    private let dateProvider: DateProviding

    private init() {
        self.storage = UserDefaults.standard
        self.dateProvider = SystemDateProvider()
        loadFromStorage()
    }

    /// Internal initializer for testing
    init(storage: KeyValueStoring, dateProvider: DateProviding) {
        self.storage = storage
        self.dateProvider = dateProvider
        loadFromStorage()
    }
    
    // MARK: - Public Methods
    
    /// Move an asset to trash
    func trash(_ assetID: String) {
        // Don't add duplicates
        guard !isTrashed(assetID) else { return }

        let item = TrashedItem(assetID: assetID, trashedAt: dateProvider.now)
        // Append at end (oldest first ordering overall)
        trashedItems.append(item)
        lastTrashedID = assetID
        saveToStorage()
    }
    
    /// Restore an asset from trash
    func restore(_ assetID: String) {
        trashedItems.removeAll { $0.assetID == assetID }
        if lastTrashedID == assetID {
            lastTrashedID = nil
        }
        saveToStorage()
    }
    
    /// Restore multiple assets from trash
    func restoreMultiple(_ assetIDs: Set<String>) {
        trashedItems.removeAll { assetIDs.contains($0.assetID) }
        if let lastID = lastTrashedID, assetIDs.contains(lastID) {
            lastTrashedID = nil
        }
        saveToStorage()
    }
    
    /// Restore the last trashed item (for undo)
    func undoLastTrash() {
        guard let lastID = lastTrashedID else { return }
        restore(lastID)
    }
    
    /// Check if an asset is in trash
    func isTrashed(_ assetID: String) -> Bool {
        trashedIDSet.contains(assetID)
    }
    
    /// Get trashed item by ID
    func trashedItem(for assetID: String) -> TrashedItem? {
        trashedItems.first { $0.assetID == assetID }
    }
    
    /// Clear all items from trash (used after permanent deletion)
    func clearAll() {
        trashedItems.removeAll()
        lastTrashedID = nil
        saveToStorage()
    }
    
    /// Remove specific IDs from trash (e.g., after permanent deletion or cleanup)
    func remove(_ assetIDs: Set<String>) {
        trashedItems.removeAll { assetIDs.contains($0.assetID) }
        if let lastID = lastTrashedID, assetIDs.contains(lastID) {
            lastTrashedID = nil
        }
        saveToStorage()
    }
    
    /// Mark assets as permanently deleted (removes from trash)
    /// Call this after successful deletion from photo library
    func markDeleted(_ assetIDs: [String]) {
        permanentlyDeletedIDs.formUnion(assetIDs)
        remove(Set(assetIDs))
    }
    
    /// Filter assets to only include non-trashed items
    func filterVisible(_ assets: [YearAsset]) -> [YearAsset] {
        let trashedSet = trashedIDs
        return assets.filter { !trashedSet.contains($0.id) }
    }
    
    // MARK: - Persistence

    private func loadFromStorage() {
        // Try loading new format first
        if let data = storage.data(forKey: userDefaultsKey),
           let items = try? JSONDecoder().decode([TrashedItem].self, from: data) {
            // Ensure oldest-first ordering by trashedAt
            trashedItems = items.sorted { $0.trashedAt < $1.trashedAt }
            return
        }

        // Migrate from legacy format (Set<String>)
        if let data = storage.data(forKey: legacyUserDefaultsKey),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            // Convert to new format with current timestamp
            let now = dateProvider.now
            trashedItems = ids.map { TrashedItem(assetID: $0, trashedAt: now) }
                .sorted { $0.trashedAt < $1.trashedAt }
            // Save in new format
            saveToStorage()
            // Remove legacy data
            storage.removeObject(forKey: legacyUserDefaultsKey)
        }
    }

    private func saveToStorage() {
        if let data = try? JSONEncoder().encode(trashedItems) {
            storage.set(data, forKey: userDefaultsKey)
        }
    }
}
