//
//  ExactDuplicateInsightService.swift
//  SClean
//
//  Verifies exact duplicates via image hash and returns safe deletion candidates.
//

import CryptoKit
import Foundation
import Photos
import UIKit

actor ExactDuplicateInsightService {
    static let shared = ExactDuplicateInsightService()

    struct DuplicateGroup: Sendable {
        let index: Int
        let assetIDs: [String]
        let keeperID: String
    }

    private struct HashSignal: Codable, Sendable {
        let assetID: String
        let lastKnownChangeDate: Date
        let quickHash: String
    }

    private struct AnalysisResult: Sendable {
        let groups: [DuplicateGroup]
    }

    private let imageManager = PHCachingImageManager()
    private let storeURL: URL
    private var cache: [String: HashSignal] = [:]
    private var isCacheLoaded = false

    private init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("SClean", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        storeURL = directory.appendingPathComponent("exact-duplicate-cache.json")
    }

    // MARK: - Public

    func exactDuplicateBucket(
        snapshot: LibraryIndexSnapshot,
        analysisBudget: Int = 260
    ) async -> InsightBucket? {
        let analysis = await analyzeDuplicates(snapshot: snapshot, analysisBudget: analysisBudget)
        let deletableIDs = deletionIDs(from: analysis.groups)
        guard !deletableIDs.isEmpty else { return nil }

        let bytesByID = Dictionary(uniqueKeysWithValues: snapshot.assets.map { ($0.id, $0.byteSize) })
        let totalBytes = deletableIDs.reduce(Int64(0)) { partial, id in
            partial + (bytesByID[id] ?? 0)
        }

        return InsightBucket(
            category: .exactDuplicates,
            count: deletableIDs.count,
            totalBytes: totalBytes
        )
    }

    func exactDuplicateDisplayAssetIDs(
        snapshot: LibraryIndexSnapshot,
        analysisBudget: Int = 900
    ) async -> [String] {
        let analysis = await analyzeDuplicates(snapshot: snapshot, analysisBudget: analysisBudget)
        return displayIDs(from: analysis.groups)
    }

    func exactDuplicateDeletionAssetIDs(
        snapshot: LibraryIndexSnapshot,
        analysisBudget: Int = 900
    ) async -> Set<String> {
        let analysis = await analyzeDuplicates(snapshot: snapshot, analysisBudget: analysisBudget)
        return deletionIDs(from: analysis.groups)
    }

    func exactDuplicateGroups(
        snapshot: LibraryIndexSnapshot,
        analysisBudget: Int = 900
    ) async -> [DuplicateGroup] {
        let analysis = await analyzeDuplicates(snapshot: snapshot, analysisBudget: analysisBudget)
        return analysis.groups
    }

    // MARK: - Private

    private func analyzeDuplicates(
        snapshot: LibraryIndexSnapshot,
        analysisBudget: Int
    ) async -> AnalysisResult {
        await loadCacheIfNeeded()

        let groups = coarseDuplicateGroups(from: snapshot.assets)
        guard !groups.isEmpty else {
            return AnalysisResult(groups: [])
        }

        var remainingBudget = max(0, analysisBudget)
        var cacheChanged = false

        var groupsOut: [DuplicateGroup] = []
        var nextGroupIndex = 1

        for group in groups {
            var byHash: [String: [IndexedAsset]] = [:]

            for asset in group {
                if let cached = cache[asset.id],
                   cached.lastKnownChangeDate == asset.lastKnownChangeDate {
                    byHash[cached.quickHash, default: []].append(asset)
                    continue
                }

                guard remainingBudget > 0 else { continue }
                remainingBudget -= 1

                guard let quickHash = await computeQuickHash(for: asset.id) else { continue }
                cache[asset.id] = HashSignal(
                    assetID: asset.id,
                    lastKnownChangeDate: asset.lastKnownChangeDate,
                    quickHash: quickHash
                )
                cacheChanged = true
                byHash[quickHash, default: []].append(asset)
            }

            for hashGroup in byHash.values where hashGroup.count >= 2 {
                let sortedGroup = hashGroup.sorted { $0.creationDate < $1.creationDate }
                let keeperID = Self.preferredKeeper(in: hashGroup).id
                groupsOut.append(
                    DuplicateGroup(
                        index: nextGroupIndex,
                        assetIDs: sortedGroup.map(\.id),
                        keeperID: keeperID
                    )
                )
                nextGroupIndex += 1
            }
        }

        if cacheChanged {
            saveCache()
        }

        return AnalysisResult(groups: groupsOut)
    }

    private func displayIDs(from groups: [DuplicateGroup]) -> [String] {
        groups.flatMap(\.assetIDs)
    }

    private func deletionIDs(from groups: [DuplicateGroup]) -> Set<String> {
        var ids: Set<String> = []
        for group in groups {
            for id in group.assetIDs where id != group.keeperID {
                ids.insert(id)
            }
        }
        return ids
    }

    private func coarseDuplicateGroups(from assets: [IndexedAsset]) -> [[IndexedAsset]] {
        var groups: [DuplicateKey: [IndexedAsset]] = [:]
        groups.reserveCapacity(assets.count)

        for asset in assets where (asset.mediaType == 1 || asset.mediaType == 2) && asset.byteSize > 0 {
            let key = DuplicateKey(
                mediaType: asset.mediaType,
                byteSize: asset.byteSize,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                roundedDuration: Int((asset.duration * 10).rounded())
            )
            groups[key, default: []].append(asset)
        }

        return groups.values
            .filter { $0.count >= 2 }
            .map { $0.sorted { $0.creationDate < $1.creationDate } }
    }

    private func computeQuickHash(for assetID: String) async -> String? {
        guard let image = await loadImage(for: assetID),
              let data = image.jpegData(compressionQuality: 0.82) else {
            return nil
        }

        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func loadImage(for assetID: String) async -> UIImage? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.version = .current

        return await withCheckedContinuation { continuation in
            var resumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 512, height: 512),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = info?[PHImageErrorKey] != nil

                if (isCancelled || hasError) && !resumed {
                    resumed = true
                    continuation.resume(returning: nil)
                    return
                }

                if !isDegraded && !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    private static func preferredKeeper(in group: [IndexedAsset]) -> IndexedAsset {
        group.max { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return !lhs.isFavorite && rhs.isFavorite
            }
            if lhs.byteSize != rhs.byteSize {
                return lhs.byteSize < rhs.byteSize
            }
            return lhs.creationDate < rhs.creationDate
        }
        ?? group[0]
    }

    private func loadCacheIfNeeded() async {
        guard !isCacheLoaded else { return }
        isCacheLoaded = true

        do {
            let data = try Data(contentsOf: storeURL)
            cache = try JSONDecoder().decode([String: HashSignal].self, from: data)
        } catch {
            cache = [:]
        }
    }

    private func saveCache() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // Non-fatal. Verification will rerun on next launch.
        }
    }

    private struct DuplicateKey: Hashable {
        let mediaType: Int
        let byteSize: Int64
        let pixelWidth: Int
        let pixelHeight: Int
        let roundedDuration: Int
    }
}
