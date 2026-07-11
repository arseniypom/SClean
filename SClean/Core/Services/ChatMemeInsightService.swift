//
//  ChatMemeInsightService.swift
//  SClean
//
//  Detects chat screenshot/meme dumps for Insights using lightweight OCR with caching.
//

import Foundation
import Photos
import UIKit
import Vision

actor ChatMemeInsightService {
    static let shared = ChatMemeInsightService()

    private struct ChatMemeSignal: Codable, Sendable {
        let assetID: String
        let lastKnownChangeDate: Date
        let score: Double
    }

    private let imageManager = PHCachingImageManager()
    private let storeURL: URL
    private var cache: [String: ChatMemeSignal] = [:]
    private var isCacheLoaded = false

    private init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("SClean", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        storeURL = directory.appendingPathComponent("chat-meme-insight-cache.json")
    }

    // MARK: - Public

    func chatMemeBucket(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date = Date(),
        analysisBudget: Int = 220
    ) async -> InsightBucket? {
        let matchedAssets = await chatMemeAssets(
            snapshot: snapshot,
            referenceDate: referenceDate,
            analysisBudget: analysisBudget
        )

        guard matchedAssets.count >= Self.minBucketCount else { return nil }
        let totalBytes = matchedAssets.reduce(Int64(0)) { $0 + $1.byteSize }
        return InsightBucket(
            category: .chatMemeDump,
            count: matchedAssets.count,
            totalBytes: totalBytes,
            assetIDs: matchedAssets.map(\.id)
        )
    }

    func chatMemeAssetIDs(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date = Date(),
        analysisBudget: Int = 650
    ) async -> [String] {
        let assets = await chatMemeAssets(
            snapshot: snapshot,
            referenceDate: referenceDate,
            analysisBudget: analysisBudget
        )
        return assets.map(\.id)
    }

    // MARK: - Private

    private func chatMemeAssets(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date,
        analysisBudget: Int
    ) async -> [IndexedAsset] {
        await loadCacheIfNeeded()

        let candidates = snapshot.assets(for: .chatMemeDump, referenceDate: referenceDate)
        guard !candidates.isEmpty else { return [] }

        var remainingBudget = max(0, analysisBudget)
        var cacheChanged = false
        var matchedIDs: Set<String> = []

        let sortedCandidates = candidates.sorted { lhs, rhs in
            let lhsScreenshot = (lhs.mediaSubtypes & Self.screenshotMask) != 0
            let rhsScreenshot = (rhs.mediaSubtypes & Self.screenshotMask) != 0
            if lhsScreenshot != rhsScreenshot {
                return lhsScreenshot && !rhsScreenshot
            }
            return lhs.creationDate < rhs.creationDate
        }

        for asset in sortedCandidates {
            // Stop promptly if the owning task was cancelled (refresh/backgrounding).
            // Work computed so far is still persisted by the saveCache() below.
            if Task.isCancelled { break }

            if let cached = cache[asset.id],
               cached.lastKnownChangeDate == asset.lastKnownChangeDate {
                if cached.score >= Self.chatMemeScoreThreshold {
                    matchedIDs.insert(asset.id)
                }
                continue
            }

            guard remainingBudget > 0 else { continue }
            remainingBudget -= 1

            let score = await computeChatMemeScore(for: asset)
            cache[asset.id] = ChatMemeSignal(
                assetID: asset.id,
                lastKnownChangeDate: asset.lastKnownChangeDate,
                score: score
            )
            cacheChanged = true

            if score >= Self.chatMemeScoreThreshold {
                matchedIDs.insert(asset.id)
            }
        }

        if cacheChanged {
            saveCache()
        }

        return candidates
            .filter { matchedIDs.contains($0.id) }
            .sorted { $0.creationDate < $1.creationDate }
    }

    /// Progressive scan: analyzes **every** chat/meme candidate (not just a budget slice),
    /// in cancellable chunks, invoking `onPartial` with an updated bucket after each chunk.
    /// Cached (unchanged) assets are skipped for free. Intended to run at a low QoS.
    func chatMemeBucketProgressive(
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date = Date(),
        chunkSize: Int = 120,
        onPartial: @Sendable (InsightBucket?) async -> Void
    ) async {
        await loadCacheIfNeeded()

        let candidates = snapshot.assets(for: .chatMemeDump, referenceDate: referenceDate)
        guard !candidates.isEmpty else {
            await onPartial(nil)
            return
        }

        // Screenshots first (highest-confidence), then oldest — matches the fast path.
        let sortedCandidates = candidates.sorted { lhs, rhs in
            let lhsScreenshot = (lhs.mediaSubtypes & Self.screenshotMask) != 0
            let rhsScreenshot = (rhs.mediaSubtypes & Self.screenshotMask) != 0
            if lhsScreenshot != rhsScreenshot {
                return lhsScreenshot && !rhsScreenshot
            }
            return lhs.creationDate < rhs.creationDate
        }

        var matchedIDs: Set<String> = []
        for asset in sortedCandidates {
            if let cached = cache[asset.id],
               cached.lastKnownChangeDate == asset.lastKnownChangeDate,
               cached.score >= Self.chatMemeScoreThreshold {
                matchedIDs.insert(asset.id)
            }
        }
        await onPartial(Self.makeBucket(from: candidates, matchedIDs: matchedIDs))

        var analyzedSinceEmit = 0
        var cacheChanged = false

        for asset in sortedCandidates {
            if Task.isCancelled { break }

            if let cached = cache[asset.id],
               cached.lastKnownChangeDate == asset.lastKnownChangeDate {
                continue
            }

            let score = await computeChatMemeScore(for: asset)
            cache[asset.id] = ChatMemeSignal(
                assetID: asset.id,
                lastKnownChangeDate: asset.lastKnownChangeDate,
                score: score
            )
            cacheChanged = true
            if score >= Self.chatMemeScoreThreshold {
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
        guard matched.count >= minBucketCount else { return nil }
        let totalBytes = matched.reduce(Int64(0)) { $0 + $1.byteSize }
        return InsightBucket(
            category: .chatMemeDump,
            count: matched.count,
            totalBytes: totalBytes,
            assetIDs: matched.map(\.id)
        )
    }

    private func computeChatMemeScore(for asset: IndexedAsset) async -> Double {
        let isScreenshot = (asset.mediaSubtypes & Self.screenshotMask) != 0
        let image = await loadImage(for: asset.id)
        let textData = recognizeText(in: image)
        let normalizedText = textData.text

        var score = 0.0

        if isScreenshot {
            score += 1.5
        }
        if asset.byteSize <= 2 * 1_048_576 {
            score += 0.6
        }

        score += Self.chatMemeTextScore(text: normalizedText, lineCount: textData.lineCount)
        return score
    }

    /// Pure, testable text-signal scoring for chat/meme detection. The asset-level
    /// signals (screenshot subtype, small file) are added by the caller.
    static func chatMemeTextScore(text rawText: String, lineCount: Int) -> Double {
        let text = rawText.lowercased()
        guard !text.isEmpty else { return 0 }

        let range = NSRange(text.startIndex..., in: text)
        var score = 0.0

        if strongKeywords.contains(where: { text.contains($0) }) { score += 2.0 }
        if mediumKeywords.contains(where: { text.contains($0) }) { score += 1.1 }
        if linkRegex.firstMatch(in: text, range: range) != nil { score += 0.8 }
        if laughterRegex.firstMatch(in: text, range: range) != nil { score += 0.7 }
        if lineCount >= 4 { score += 0.3 }
        if text.count >= 60 { score += 0.3 }

        return score
    }

    private func recognizeText(in image: UIImage?) -> (text: String, lineCount: Int) {
        guard
            let image,
            let cgImage = image.cgImage
        else {
            return ("", 0)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.012
        request.recognitionLanguages = ["en-US", "ru-RU"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ("", 0)
        }

        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string.lowercased() }
        return (lines.joined(separator: " "), lines.count)
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
            cache = try JSONDecoder().decode([String: ChatMemeSignal].self, from: data)
        } catch {
            cache = [:]
        }
    }

    private func saveCache() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // Non-fatal. We can recompute later.
        }
    }

    private static let screenshotMask = 0x4
    private static let minBucketCount = 8
    static let chatMemeScoreThreshold = 2.8

    private static let strongKeywords = [
        "telegram", "whatsapp", "messenger", "discord", "imessage",
        "message", "messages", "reply", "forwarded", "story", "reel",
        "meme", "me irl", "when you", "expectation", "reality",
        // Russian chat/messenger surface text
        "переслано", "сообщение", "ответить", "вотсап", "телеграм"
    ]

    private static let mediumKeywords = [
        "online", "typing", "delivered", "read", "sent",
        "lol", "lmao", "haha", "bro", "chat", "group",
        // Russian
        "онлайн", "печатает", "был", "вчера", "ахах", "лол"
    ]

    private static let linkRegex = try! NSRegularExpression(
        pattern: #"((https?://)|(www\.))[a-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+"#,
        options: [.caseInsensitive]
    )

    private static let laughterRegex = try! NSRegularExpression(
        pattern: #"\b(ha){2,}\b|\blol+\b|\blmao+\b"#,
        options: [.caseInsensitive]
    )
}
