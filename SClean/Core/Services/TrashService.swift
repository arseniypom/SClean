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
    
    /// All trashed items (ordered by trashedAt, newest first)
    @Published private(set) var trashedItems: [TrashedItem] = []
    
    /// Last trashed item (for undo)
    @Published private(set) var lastTrashedID: String?
    
    /// Total count of trashed items
    var trashCount: Int { trashedItems.count }
    
    /// Set of trashed IDs for fast lookup
    var trashedIDs: Set<String> {
        Set(trashedItems.map(\.assetID))
    }
    
    /// Ordered list of trashed asset IDs (newest first)
    var orderedTrashedIDs: [String] {
        trashedItems.map(\.assetID)
    }
    
    private let userDefaultsKey = "SClean.trashedItems"
    
    // Legacy key for migration
    private let legacyUserDefaultsKey = "SClean.trashedAssetIDs"
    
    private init() {
        loadFromStorage()
    }
    
    // MARK: - Public Methods
    
    /// Move an asset to trash
    func trash(_ assetID: String) {
        // Don't add duplicates
        guard !isTrashed(assetID) else { return }
        
        let item = TrashedItem(assetID: assetID)
        // Insert at beginning (newest first)
        trashedItems.insert(item, at: 0)
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
        trashedItems.contains { $0.assetID == assetID }
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
    
    /// Filter assets to only include non-trashed items
    func filterVisible(_ assets: [YearAsset]) -> [YearAsset] {
        let trashedSet = trashedIDs
        return assets.filter { !trashedSet.contains($0.id) }
    }
    
    // MARK: - Persistence
    
    private func loadFromStorage() {
        // Try loading new format first
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let items = try? JSONDecoder().decode([TrashedItem].self, from: data) {
            trashedItems = items
            return
        }
        
        // Migrate from legacy format (Set<String>)
        if let data = UserDefaults.standard.data(forKey: legacyUserDefaultsKey),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            // Convert to new format with current timestamp
            let now = Date()
            trashedItems = ids.map { TrashedItem(assetID: $0, trashedAt: now) }
            // Save in new format
            saveToStorage()
            // Remove legacy data
            UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
        }
    }
    
    private func saveToStorage() {
        if let data = try? JSONEncoder().encode(trashedItems) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
