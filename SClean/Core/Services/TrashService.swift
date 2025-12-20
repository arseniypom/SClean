//
//  TrashService.swift
//  SClean
//
//  Manages in-app trash state (soft delete before permanent deletion)
//

import SwiftUI
import Combine

/// Manages the in-app Trash - items marked for deletion but not yet permanently removed
@MainActor
final class TrashService: ObservableObject {
    
    /// Shared instance
    static let shared = TrashService()
    
    /// Set of trashed asset IDs
    @Published private(set) var trashedIDs: Set<String> = []
    
    /// Last trashed item (for undo)
    @Published private(set) var lastTrashedID: String?
    
    /// Total count of trashed items
    var trashCount: Int { trashedIDs.count }
    
    private let userDefaultsKey = "SClean.trashedAssetIDs"
    
    private init() {
        loadFromStorage()
    }
    
    // MARK: - Public Methods
    
    /// Move an asset to trash
    func trash(_ assetID: String) {
        trashedIDs.insert(assetID)
        lastTrashedID = assetID
        saveToStorage()
    }
    
    /// Restore an asset from trash
    func restore(_ assetID: String) {
        trashedIDs.remove(assetID)
        if lastTrashedID == assetID {
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
        trashedIDs.contains(assetID)
    }
    
    /// Clear all items from trash (used after permanent deletion)
    func clearAll() {
        trashedIDs.removeAll()
        lastTrashedID = nil
        saveToStorage()
    }
    
    /// Remove specific IDs from trash (e.g., after permanent deletion)
    func remove(_ assetIDs: Set<String>) {
        trashedIDs.subtract(assetIDs)
        if let lastID = lastTrashedID, assetIDs.contains(lastID) {
            lastTrashedID = nil
        }
        saveToStorage()
    }
    
    /// Filter assets to only include non-trashed items
    func filterVisible(_ assets: [YearAsset]) -> [YearAsset] {
        assets.filter { !isTrashed($0.id) }
    }
    
    // MARK: - Persistence
    
    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            trashedIDs = ids
        }
    }
    
    private func saveToStorage() {
        if let data = try? JSONEncoder().encode(trashedIDs) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}

