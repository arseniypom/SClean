//
//  AestheticsInsightService.swift
//  SClean
//
//  Flags blurry / low-quality photos for the Insights tab using Vision's on-device
//  aesthetics scoring (VNCalculateImageAestheticsScoresRequest). Utility images
//  (screenshots, documents, receipts) are never flagged as "bad shots".
//

import Foundation
import Photos
import UIKit
import Vision

actor AestheticsInsightService {
    static let shared = AestheticsInsightService()

    private struct AestheticsSignal: Codable, Sendable {
        let assetID: String
        let lastKnownChangeDate: Date
        let score: Float       // overall aesthetics score, higher = better
        let isUtility: Bool    // screenshot/document/receipt-like, excluded from "bad shots"
    }

    private let imageManager = PHCachingImageManager()
    private let storeURL: URL
    private var cache: [String: AestheticsSignal] = [:]
    private var isCacheLoaded = false

    private init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("SClean", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        storeURL = directory.appendingPathComponent("aesthetics-cache.json")
    }

    // MARK: - Public

    /// Progressive scan: scores **every** candidate photo, emitting an updated bucket as it
    /// goes. Cached (unchanged) scores are reused for free.
    func lowQualityBucketProgressive(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date = Date(),
        chunkSize: Int = 120,
        onPartial: @Sendable (InsightBucket?) async -> Void
    ) async {
        await loadCacheIfNeeded()

        let candidates = snapshot.assets(for: .lowQuality, referenceDate: referenceDate)
        guard !candidates.isEmpty else {
            await onPartial(nil)
            return
        }

        var matchedIDs: Set<String> = []
        for asset in candidates where isLowQuality(cache[asset.id], matching: asset) {
            matchedIDs.insert(asset.id)
        }
        await onPartial(Self.makeBucket(from: candidates, matchedIDs: matchedIDs))

        var analyzedSinceEmit = 0
        var cacheChanged = false

        for asset in candidates {
            if Task.isCancelled { break }

            if let cached = cache[asset.id], cached.lastKnownChangeDate == asset.lastKnownChangeDate {
                continue
            }

            guard let signal = await computeAesthetics(for: asset.id, changeDate: asset.lastKnownChangeDate) else { continue }
            cache[asset.id] = signal
            cacheChanged = true
            if isLowQuality(signal, matching: asset) {
                matchedIDs.insert(asset.id)
            }

            analyzedSinceEmit += 1
            if analyzedSinceEmit >= chunkSize {
                analyzedSinceEmit = 0
                saveCache()
                cacheChanged = false
                await onPartial(Self.makeBucket(from: candidates, matchedIDs: matchedIDs))
                await Task.yield()
            }
        }

        if cacheChanged { saveCache() }
        await onPartial(Self.makeBucket(from: candidates, matchedIDs: matchedIDs))
    }

    /// Low-quality asset IDs for the grid.
    func lowQualityAssetIDs(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date = Date()
    ) async -> [String] {
        await loadCacheIfNeeded()

        let candidates = snapshot.assets(for: .lowQuality, referenceDate: referenceDate)
        guard !candidates.isEmpty else { return [] }

        var cacheChanged = false
        var matched: [IndexedAsset] = []

        for asset in candidates {
            if Task.isCancelled { break }

            if let cached = cache[asset.id], cached.lastKnownChangeDate == asset.lastKnownChangeDate {
                if isLowQuality(cached, matching: asset) { matched.append(asset) }
                continue
            }
            guard let signal = await computeAesthetics(for: asset.id, changeDate: asset.lastKnownChangeDate) else { continue }
            cache[asset.id] = signal
            cacheChanged = true
            if isLowQuality(signal, matching: asset) { matched.append(asset) }
        }

        if cacheChanged { saveCache() }
        return matched
            .sorted { $0.creationDate < $1.creationDate }
            .map(\.id)
    }

    /// Cached aesthetics score for an asset, if already computed (used by other services
    /// to pick the best-looking keeper). Returns nil when not yet scored.
    func cachedScore(for assetID: String, lastKnownChangeDate: Date) -> Float? {
        guard let signal = cache[assetID], signal.lastKnownChangeDate == lastKnownChangeDate else { return nil }
        return signal.score
    }

    // MARK: - Private

    private func isLowQuality(_ signal: AestheticsSignal?, matching asset: IndexedAsset) -> Bool {
        guard let signal, signal.lastKnownChangeDate == asset.lastKnownChangeDate else { return false }
        return !signal.isUtility && signal.score <= Self.lowQualityMaxScore
    }

    private static func makeBucket(from candidates: [IndexedAsset], matchedIDs: Set<String>) -> InsightBucket? {
        let matched = candidates.filter { matchedIDs.contains($0.id) }
        guard matched.count >= minBucketCount else { return nil }
        let totalBytes = matched.reduce(Int64(0)) { $0 + $1.byteSize }
        return InsightBucket(
            category: .lowQuality,
            count: matched.count,
            totalBytes: totalBytes,
            assetIDs: matched.map(\.id)
        )
    }

    private func computeAesthetics(for assetID: String, changeDate: Date) async -> AestheticsSignal? {
        // The aesthetics insight requires Vision's iOS 18+ scoring API; on older
        // systems the low-quality bucket simply never appears.
        guard #available(iOS 18.0, *) else { return nil }
        guard let image = await loadImage(for: assetID), let cgImage = image.cgImage else { return nil }

        let request = VNCalculateImageAestheticsScoresRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else { return nil }
        return AestheticsSignal(
            assetID: assetID,
            lastKnownChangeDate: changeDate,
            score: observation.overallScore,
            isUtility: observation.isUtility
        )
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
                targetSize: CGSize(width: 1024, height: 1024),
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
            cache = try JSONDecoder().decode([String: AestheticsSignal].self, from: data)
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

    private static let minBucketCount = 5

    /// Photos scoring at or below this overall aesthetics value are treated as
    /// low quality. Conservative default (range is roughly -1...1); tune on device.
    private static let lowQualityMaxScore: Float = -0.3
}
