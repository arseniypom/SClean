//
//  SimilarShotsInsightService.swift
//  SClean
//
//  Refines time-clustered "similar shots" into *visually* similar groups using
//  Vision image feature prints, so only true near-duplicate bursts are offered
//  for cleanup (not merely photos taken seconds apart). Aesthetics scores from the
//  same Vision pass pick the best-looking frame to keep.
//

import Foundation
import Photos
import UIKit
import Vision

actor SimilarShotsInsightService {
    static let shared = SimilarShotsInsightService()

    private struct VisionSignal: Codable, Sendable {
        let assetID: String
        let lastKnownChangeDate: Date
        let featurePrint: Data   // archived VNFeaturePrintObservation
        let aesthetics: Float    // overall aesthetics score, higher = better
    }

    private let imageManager = PHCachingImageManager()
    private let storeURL: URL
    private var cache: [String: VisionSignal] = [:]
    private var isCacheLoaded = false

    private init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("SClean", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        storeURL = directory.appendingPathComponent("similar-shots-cache.json")
    }

    // MARK: - Public

    /// Progressive scan: refines **every** time cluster into visual subgroups, emitting an
    /// updated bucket as it goes. Cached (unchanged) feature prints are reused for free.
    func similarShotsBucketProgressive(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date = Date(),
        chunkSize: Int = 80,
        onPartial: @Sendable (InsightBucket?) async -> Void
    ) async {
        await loadCacheIfNeeded()

        let clusters = snapshot.similarShotClusters(referenceDate: referenceDate)
        guard !clusters.isEmpty else {
            await onPartial(nil)
            return
        }

        var deletable: [IndexedAsset] = []
        var analyzedSinceEmit = 0
        var cacheChanged = false

        for cluster in clusters {
            if Task.isCancelled { break }

            for asset in cluster {
                if let cached = cache[asset.id], cached.lastKnownChangeDate == asset.lastKnownChangeDate {
                    continue
                }
                if Task.isCancelled { break }
                guard let signal = await computeSignals(for: asset.id, changeDate: asset.lastKnownChangeDate) else { continue }
                cache[asset.id] = signal
                cacheChanged = true

                analyzedSinceEmit += 1
                if analyzedSinceEmit >= chunkSize {
                    analyzedSinceEmit = 0
                    saveCache()
                    cacheChanged = false
                    await onPartial(Self.makeBucket(from: deletable))
                    await Task.yield()
                }
            }

            deletable.append(contentsOf: visualExtras(in: cluster))
            await onPartial(Self.makeBucket(from: deletable))
        }

        if cacheChanged { saveCache() }
        await onPartial(Self.makeBucket(from: deletable))
    }

    /// Visually-refined deletable asset IDs (the extras, keeper excluded) for the grid.
    func similarShotsDeletableIDs(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date = Date()
    ) async -> [String] {
        await loadCacheIfNeeded()

        let clusters = snapshot.similarShotClusters(referenceDate: referenceDate)
        guard !clusters.isEmpty else { return [] }

        var cacheChanged = false
        var deletable: [IndexedAsset] = []

        for cluster in clusters {
            if Task.isCancelled { break }
            for asset in cluster {
                if let cached = cache[asset.id], cached.lastKnownChangeDate == asset.lastKnownChangeDate {
                    continue
                }
                guard let signal = await computeSignals(for: asset.id, changeDate: asset.lastKnownChangeDate) else { continue }
                cache[asset.id] = signal
                cacheChanged = true
            }
            deletable.append(contentsOf: visualExtras(in: cluster))
        }

        if cacheChanged { saveCache() }
        return deletable
            .sorted { $0.creationDate < $1.creationDate }
            .map(\.id)
    }

    // MARK: - Visual grouping

    /// Splits a time cluster into connected visual subgroups and returns the extras
    /// (every member except the chosen keeper) for each subgroup of size ≥ 2.
    private func visualExtras(in cluster: [IndexedAsset]) -> [IndexedAsset] {
        // Only consider members whose feature print we actually have.
        let members = cluster.filter { cache[$0.id] != nil }
        guard members.count >= 2 else { return [] }

        let prints: [VNFeaturePrintObservation?] = members.map { featurePrint(from: cache[$0.id]!.featurePrint) }

        // Union-find over members; link i~j when feature-print distance is below threshold.
        var parent = Array(0..<members.count)
        func find(_ x: Int) -> Int {
            var root = x
            while parent[root] != root { root = parent[root] }
            var cur = x
            while parent[cur] != cur { let next = parent[cur]; parent[cur] = root; cur = next }
            return root
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        for i in 0..<members.count {
            guard let pi = prints[i] else { continue }
            for j in (i + 1)..<members.count {
                guard let pj = prints[j] else { continue }
                if let d = distance(pi, pj), d <= Self.similarDistanceThreshold {
                    union(i, j)
                }
            }
        }

        var components: [Int: [Int]] = [:]
        for i in 0..<members.count {
            components[find(i), default: []].append(i)
        }

        var extras: [IndexedAsset] = []
        for indices in components.values where indices.count >= 2 {
            let group = indices.map { members[$0] }
            let keeperID = keeper(in: group).id
            extras.append(contentsOf: group.filter { $0.id != keeperID })
        }
        return extras
    }

    /// Keeper preference: favorite, then highest aesthetics, then largest file.
    private func keeper(in group: [IndexedAsset]) -> IndexedAsset {
        group.max { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return !lhs.isFavorite && rhs.isFavorite
            }
            let lhsScore = cache[lhs.id]?.aesthetics ?? -Float.greatestFiniteMagnitude
            let rhsScore = cache[rhs.id]?.aesthetics ?? -Float.greatestFiniteMagnitude
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return lhs.byteSize < rhs.byteSize
        }
        ?? group[0]
    }

    private static func makeBucket(from deletable: [IndexedAsset]) -> InsightBucket? {
        guard !deletable.isEmpty else { return nil }
        let totalBytes = deletable.reduce(Int64(0)) { $0 + $1.byteSize }
        return InsightBucket(
            category: .similarShots,
            count: deletable.count,
            totalBytes: totalBytes,
            assetIDs: deletable.map(\.id)
        )
    }

    // MARK: - Vision

    private func computeSignals(for assetID: String, changeDate: Date) async -> VisionSignal? {
        guard let image = await loadImage(for: assetID), let cgImage = image.cgImage else { return nil }

        let featureRequest = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Aesthetics scoring (used to pick the best-looking keeper) is iOS 18+.
        // On older systems we fall back to size-based keeper selection.
        var aesthetics: Float = 0
        do {
            if #available(iOS 18.0, *) {
                let aestheticsRequest = VNCalculateImageAestheticsScoresRequest()
                try handler.perform([featureRequest, aestheticsRequest])
                aesthetics = aestheticsRequest.results?.first?.overallScore ?? 0
            } else {
                try handler.perform([featureRequest])
            }
        } catch {
            return nil
        }

        guard
            let observation = featureRequest.results?.first,
            let data = try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
        else {
            return nil
        }

        return VisionSignal(assetID: assetID, lastKnownChangeDate: changeDate, featurePrint: data, aesthetics: aesthetics)
    }

    private func featurePrint(from data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    private func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var value: Float = 0
        do {
            try a.computeDistance(&value, to: b)
        } catch {
            return nil
        }
        return value
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

    private func loadCacheIfNeeded() async {
        guard !isCacheLoaded else { return }
        isCacheLoaded = true

        do {
            let data = try Data(contentsOf: storeURL)
            cache = try JSONDecoder().decode([String: VisionSignal].self, from: data)
        } catch {
            cache = [:]
        }
    }

    private func saveCache() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // Non-fatal: recomputed on next launch.
        }
    }

    /// Feature-print distance below which two shots count as visually the same scene.
    /// Conservative default; tune against a real library.
    private static let similarDistanceThreshold: Float = 0.6
}
