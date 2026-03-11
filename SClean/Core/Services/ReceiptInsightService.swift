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

        guard !receiptAssets.isEmpty else { return nil }
        let totalBytes = receiptAssets.reduce(Int64(0)) { $0 + $1.byteSize }
        return InsightBucket(category: .receipts, count: receiptAssets.count, totalBytes: totalBytes)
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
        guard !text.isEmpty else { return 0 }

        var score = 0.0

        let strongKeywords = [
            "receipt", "merchant", "subtotal", "vat", "invoice",
            "чек", "касса", "итог", "сумма", "налог", "безнал"
        ]
        let mediumKeywords = [
            "total", "tax", "card", "cash", "terminal", "store",
            "руб", "₽", "коп", "оплата", "товар", "покупка"
        ]

        if strongKeywords.contains(where: { text.contains($0) }) {
            score += 2.2
        }
        if mediumKeywords.contains(where: { text.contains($0) }) {
            score += 1.2
        }
        if Self.amountRegex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) != nil {
            score += 1.4
        }
        if Self.dateRegex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) != nil {
            score += 0.9
        }
        if text.count > 40 {
            score += 0.4
        }

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

    private static let receiptScoreThreshold = 3.2

    private static let amountRegex = try! NSRegularExpression(
        pattern: #"(\d{1,3}([., ]\d{3})*([.,]\d{2})?)"#,
        options: []
    )

    private static let dateRegex = try! NSRegularExpression(
        pattern: #"\b(\d{1,2}[./-]\d{1,2}([./-]\d{2,4})?)\b"#,
        options: []
    )
}
