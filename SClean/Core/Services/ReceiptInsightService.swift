//
//  ReceiptInsightService.swift
//  SClean
//
//  Detects receipt-like photos for Insights using on-device OCR with caching.
//

import Foundation
import Photos
import UIKit
import Vision

actor ReceiptInsightService {
    static let shared = ReceiptInsightService()

    private struct ReceiptSignal: Codable, Sendable {
        let assetID: String
        let lastKnownChangeDate: Date
        let score: Double
    }

    private let imageManager = PHCachingImageManager()
    private let storeURL: URL
    private var cache: [String: ReceiptSignal] = [:]
    private var isCacheLoaded = false

    private init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("SClean", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        storeURL = directory.appendingPathComponent("receipt-insight-cache.json")
    }

    // MARK: - Public

    func receiptBucket(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date = Date(),
        analysisBudget: Int = 180
    ) async -> InsightBucket? {
        let receiptAssets = await receiptAssets(
            snapshot: snapshot,
            referenceDate: referenceDate,
            analysisBudget: analysisBudget
        )

        guard receiptAssets.count >= Self.minBucketCount else { return nil }
        let totalBytes = receiptAssets.reduce(Int64(0)) { $0 + $1.byteSize }
        return InsightBucket(
            category: .receipts,
            count: receiptAssets.count,
            totalBytes: totalBytes,
            assetIDs: receiptAssets.map(\.id)
        )
    }

    func receiptAssetIDs(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date = Date(),
        analysisBudget: Int = 500
    ) async -> [String] {
        let assets = await receiptAssets(
            snapshot: snapshot,
            referenceDate: referenceDate,
            analysisBudget: analysisBudget
        )
        return assets.map(\.id)
    }

    // MARK: - Private

    private func receiptAssets(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date,
        analysisBudget: Int
    ) async -> [IndexedAsset] {
        await loadCacheIfNeeded()

        let candidates = snapshot.assets(for: .receipts, referenceDate: referenceDate)
        guard !candidates.isEmpty else { return [] }

        var remainingBudget = max(0, analysisBudget)
        var cacheChanged = false
        var matchedIDs: Set<String> = []

        for asset in candidates {
            // Stop promptly if the owning task was cancelled (refresh/backgrounding).
            // Work computed so far is still persisted by the saveCache() below.
            if Task.isCancelled { break }

            if let signal = cache[asset.id],
               signal.lastKnownChangeDate == asset.lastKnownChangeDate {
                if signal.score >= Self.receiptScoreThreshold {
                    matchedIDs.insert(asset.id)
                }
                continue
            }

            guard remainingBudget > 0 else { continue }
            remainingBudget -= 1

            let score = await computeReceiptScore(for: asset.id)
            cache[asset.id] = ReceiptSignal(
                assetID: asset.id,
                lastKnownChangeDate: asset.lastKnownChangeDate,
                score: score
            )
            cacheChanged = true

            if score >= Self.receiptScoreThreshold {
                matchedIDs.insert(asset.id)
            }
        }

        if cacheChanged {
            saveCache()
        }

        return candidates.filter { matchedIDs.contains($0.id) }
            .sorted { $0.creationDate < $1.creationDate }
    }

    /// Progressive scan: analyzes **every** receipt candidate (not just a budget slice),
    /// in cancellable chunks, invoking `onPartial` with an updated bucket after each chunk
    /// so the UI can grow the count live. Cached (unchanged) assets are skipped for free,
    /// so the second launch emits the full result almost immediately.
    /// Intended to run at a low QoS in the background.
    func receiptBucketProgressive(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date = Date(),
        chunkSize: Int = 120,
        onPartial: @Sendable (InsightBucket?) async -> Void
    ) async {
        await loadCacheIfNeeded()

        let candidates = snapshot.assets(for: .receipts, referenceDate: referenceDate)
        guard !candidates.isEmpty else {
            await onPartial(nil)
            return
        }

        var matchedIDs: Set<String> = []
        // Seed from cache so already-known matches surface immediately.
        for asset in candidates {
            if let signal = cache[asset.id],
               signal.lastKnownChangeDate == asset.lastKnownChangeDate,
               signal.score >= Self.receiptScoreThreshold {
                matchedIDs.insert(asset.id)
            }
        }
        await onPartial(Self.makeBucket(from: candidates, matchedIDs: matchedIDs))

        var analyzedSinceEmit = 0
        var cacheChanged = false

        for asset in candidates {
            if Task.isCancelled { break }

            if let signal = cache[asset.id],
               signal.lastKnownChangeDate == asset.lastKnownChangeDate {
                continue // already analyzed this exact version
            }

            let score = await computeReceiptScore(for: asset.id)
            cache[asset.id] = ReceiptSignal(
                assetID: asset.id,
                lastKnownChangeDate: asset.lastKnownChangeDate,
                score: score
            )
            cacheChanged = true
            if score >= Self.receiptScoreThreshold {
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

    private static func makeBucket(from candidates: [IndexedAsset], matchedIDs: Set<String>) -> InsightBucket? {
        let matched = candidates.filter { matchedIDs.contains($0.id) }
        // A single stray match is not an actionable cleanup — don't surface a card for it
        guard matched.count >= minBucketCount else { return nil }
        let totalBytes = matched.reduce(Int64(0)) { $0 + $1.byteSize }
        return InsightBucket(
            category: .receipts,
            count: matched.count,
            totalBytes: totalBytes,
            assetIDs: matched.map(\.id)
        )
    }

    private func computeReceiptScore(for assetID: String) async -> Double {
        guard let image = await loadImage(for: assetID) else { return 0 }
        guard let cgImage = image.cgImage else { return 0 }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.015
        request.recognitionLanguages = ["en-US", "ru-RU"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return 0
        }

        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string.lowercased() }
        let joinedText = lines.joined(separator: " ")

        return score(forRecognizedText: joinedText)
    }

    private func score(forRecognizedText text: String) -> Double {
        Self.receiptScore(for: text)
    }

    /// Pure, testable receipt scoring over recognized OCR text.
    /// A receipt must contain either an explicit receipt term or a monetary amount
    /// (number with cents or a currency symbol); this gate removes false positives
    /// from generic screenshots that merely contain a date or a bare number.
    static func receiptScore(for rawText: String) -> Double {
        let text = rawText.lowercased()
        guard !text.isEmpty else { return 0 }

        let fullRange = NSRange(text.startIndex..., in: text)
        let hasStrong = strongKeywords.contains { text.contains($0) }
        let hasMonetary = monetaryRegex.firstMatch(in: text, range: fullRange) != nil

        guard hasStrong || hasMonetary else { return 0 }

        var score = 0.0
        if hasStrong { score += 2.2 }
        if mediumKeywords.contains(where: { text.contains($0) }) { score += 0.8 }
        if hasMonetary { score += 1.6 }
        if dateRegex.firstMatch(in: text, range: fullRange) != nil { score += 0.7 }
        if text.count > 40 { score += 0.3 }

        return score
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
            let decoded = try JSONDecoder().decode([String: ReceiptSignal].self, from: data)
            cache = decoded
        } catch {
            cache = [:]
        }
    }

    private func saveCache() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // Non-fatal: insights still work without persistence.
        }
    }

    static let receiptScoreThreshold = 3.2

    /// A card with fewer matches than this is noise, not an actionable cleanup
    private static let minBucketCount = 3

    private static let strongKeywords = [
        "receipt", "merchant", "subtotal", "vat", "invoice",
        "чек", "касса", "итог", "сумма", "налог", "безнал"
    ]

    private static let mediumKeywords = [
        "total", "tax", "card", "cash", "terminal", "store",
        "руб", "₽", "коп", "оплата", "товар", "покупка"
    ]

    /// Matches a monetary amount: a number with two decimal places (cents) or a
    /// number preceded by a currency symbol. Deliberately does NOT match bare
    /// integers like "5 items" or "page 3", which previously produced false positives.
    private static let monetaryRegex = try! NSRegularExpression(
        pattern: #"(?:[$€£₽]\s?\d[\d., ]*)|(?:\b\d[\d., ]*[.,]\d{2}\b)"#,
        options: []
    )

    private static let dateRegex = try! NSRegularExpression(
        pattern: #"\b(\d{1,2}[./-]\d{1,2}([./-]\d{2,4})?)\b"#,
        options: []
    )
}
