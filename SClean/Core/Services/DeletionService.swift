//
//  DeletionService.swift
//  SClean
//
//  Handles bulk deletion of photos via PHPhotoLibrary
//

import Photos
import SwiftUI
import Combine

// MARK: - Deletion Result

/// Result of a bulk deletion operation
struct DeletionResult: Equatable {
    let deletedCount: Int
    let failedIDs: [String]
    let error: DeletionError?
    
    var isFullSuccess: Bool { failedIDs.isEmpty && error == nil && deletedCount > 0 }
    var isPartialSuccess: Bool { deletedCount > 0 && !failedIDs.isEmpty }
    var isFailure: Bool { deletedCount == 0 && (error != nil || !failedIDs.isEmpty) }
    var totalAttempted: Int { deletedCount + failedIDs.count }
    
    static let empty = DeletionResult(deletedCount: 0, failedIDs: [], error: nil)
}

// MARK: - Deletion Error

/// Errors that can occur during deletion
enum DeletionError: Error, Equatable {
    case permissionDenied
    case permissionRevoked
    case noAssetsFound
    case userCancelled
    case unknown(String)
    
    var localizedDescription: String {
        switch self {
        case .permissionDenied:
            return "Photo library access is required to delete items."
        case .permissionRevoked:
            return "Photo library access was revoked during deletion."
        case .noAssetsFound:
            return "No items were found to delete."
        case .userCancelled:
            return "Deletion was cancelled."
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Deletion Progress

/// Progress update during deletion
struct DeletionProgress {
    let current: Int
    let total: Int
    
    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

// MARK: - Deletion Service

/// Service for permanently deleting photos from the photo library
@MainActor
final class DeletionService: ObservableObject {
    
    /// Shared instance
    static let shared = DeletionService()
    
    /// Current deletion progress
    @Published private(set) var progress: DeletionProgress?
    
    /// Whether a deletion is in progress
    @Published private(set) var isDeleting = false
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Delete assets from the photo library
    /// - Parameter assetIDs: Array of PHAsset local identifiers to delete
    /// - Returns: DeletionResult with counts and any failed IDs
    func deleteAssets(_ assetIDs: [String]) async -> DeletionResult {
        guard !assetIDs.isEmpty else {
            return DeletionResult(deletedCount: 0, failedIDs: [], error: .noAssetsFound)
        }
        
        isDeleting = true
        progress = DeletionProgress(current: 0, total: assetIDs.count)
        
        defer {
            isDeleting = false
            progress = nil
        }
        
        // Fetch the PHAssets
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: assetIDs,
            options: nil
        )
        
        guard fetchResult.count > 0 else {
            return DeletionResult(deletedCount: 0, failedIDs: assetIDs, error: .noAssetsFound)
        }
        
        // Collect found assets
        var assetsToDelete: [PHAsset] = []
        var foundIDs: Set<String> = []
        
        fetchResult.enumerateObjects { asset, _, _ in
            assetsToDelete.append(asset)
            foundIDs.insert(asset.localIdentifier)
        }
        
        // Perform deletion
        do {
            try await performDeletion(assets: assetsToDelete)
            
            // Update progress to complete
            progress = DeletionProgress(current: assetIDs.count, total: assetIDs.count)
            
            // Success - all found assets were deleted
            // notFoundIDs are considered "already gone" - not failures
            return DeletionResult(
                deletedCount: assetsToDelete.count,
                failedIDs: [],
                error: nil
            )
            
        } catch let error as NSError {
            // Handle specific errors
            if error.domain == "PHPhotosErrorDomain" {
                switch error.code {
                case 3300: // PHPhotosError.accessUserDenied
                    return DeletionResult(
                        deletedCount: 0,
                        failedIDs: assetIDs,
                        error: .userCancelled
                    )
                case 3301: // PHPhotosError.accessRestricted
                    return DeletionResult(
                        deletedCount: 0,
                        failedIDs: assetIDs,
                        error: .permissionDenied
                    )
                default:
                    break
                }
            }
            
            return DeletionResult(
                deletedCount: 0,
                failedIDs: assetIDs,
                error: .unknown(error.localizedDescription)
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func performDeletion(assets: [PHAsset]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: DeletionError.unknown("Unknown error occurred"))
                }
            }
        }
    }
}

