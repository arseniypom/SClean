//
//  LibraryIndexer.swift
//  SClean
//
//  Builds and updates the cached photo library index.
//

import Foundation
import Photos

// MARK: - Library Indexer

struct LibraryIndexer: Sendable {
    typealias ProgressHandler = @Sendable (_ processed: Int, _ total: Int) -> Void
    
    func buildIndex(
        existingSnapshot: LibraryIndexSnapshot?,
        onProgress: ProgressHandler? = nil
    ) async -> LibraryIndexSnapshot {
        await Task.detached(priority: .userInitiated) {
            Self.indexLibrary(existingSnapshot: existingSnapshot, onProgress: onProgress)
        }.value
    }
    
    // MARK: - Private
    
    private nonisolated static func indexLibrary(
        existingSnapshot: LibraryIndexSnapshot?,
        onProgress: ProgressHandler?
    ) -> LibraryIndexSnapshot {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        fetchOptions.includeAllBurstAssets = false
        
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        let total = fetchResult.count
        let step = max(250, total / 200)
        
        let lastIndexedAt = existingSnapshot?.lastIndexedAt ?? .distantPast
        let cachedAssets = Dictionary(uniqueKeysWithValues: (existingSnapshot?.assets ?? []).map { ($0.id, $0) })
        var indexedAssets: [IndexedAsset] = []
        indexedAssets.reserveCapacity(total)
        
        let calendar = Calendar.current
        var processed = 0
        
        fetchResult.enumerateObjects { asset, _, stop in
            if Task.isCancelled {
                stop.pointee = true
                return
            }
            
            defer {
                processed += 1
                if let onProgress, total > 0 {
                    if processed == 1 || processed == total || (processed % step) == 0 {
                        onProgress(processed, total)
                    }
                }
            }
            
            guard let creationDate = asset.creationDate else { return }
            
            let year = calendar.component(.year, from: creationDate)
            let changeDate = asset.modificationDate ?? creationDate
            let identifier = asset.localIdentifier
            
            // Reuse cached metadata when the asset hasn't changed since last index.
            if let cached = cachedAssets[identifier], changeDate <= lastIndexedAt {
                if cached.year == year {
                    indexedAssets.append(cached)
                } else {
                    // Creation date changed; reuse size but update year.
                    let updated = IndexedAsset(
                        id: cached.id,
                        year: year,
                        byteSize: cached.byteSize,
                        lastKnownChangeDate: cached.lastKnownChangeDate
                    )
                    indexedAssets.append(updated)
                }
                return
            }
            
            let byteSize = Self.estimatedByteSize(for: asset)
            let indexed = IndexedAsset(
                id: identifier,
                year: year,
                byteSize: byteSize,
                lastKnownChangeDate: changeDate
            )
            indexedAssets.append(indexed)
        }
        
        return LibraryIndexSnapshot(lastIndexedAt: Date(), assets: indexedAssets)
    }
    
    private nonisolated static func estimatedByteSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.reduce(Int64(0)) { sum, resource in
            if let size = resource.value(forKey: "fileSize") as? Int64 {
                return sum + size
            }
            return sum
        }
    }
}
