//
//  LibraryIndexStore.swift
//  SClean
//
//  Persists lightweight photo library index to avoid full reindex on launch.
//

@preconcurrency import Foundation

// MARK: - Indexed Asset

/// Cached metadata for a photo/video asset
nonisolated struct IndexedAsset: Codable, Equatable, Identifiable, Sendable {
    let id: String // PHAsset localIdentifier
    let year: Int
    let byteSize: Int64
    let creationDate: Date
    let lastKnownChangeDate: Date

    // Media metadata used for types + insights
    let mediaType: Int         // PHAssetMediaType.rawValue (1=image, 2=video)
    let mediaSubtypes: Int     // PHAssetMediaSubtype bitmask
    let duration: TimeInterval // For videos, 0 for photos
    let pixelWidth: Int
    let pixelHeight: Int
    let isFavorite: Bool

    init(
        id: String,
        year: Int,
        byteSize: Int64,
        creationDate: Date = .distantPast,
        lastKnownChangeDate: Date,
        mediaType: Int = 0,
        mediaSubtypes: Int = 0,
        duration: TimeInterval = 0,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.year = year
        self.byteSize = byteSize
        self.creationDate = creationDate
        self.lastKnownChangeDate = lastKnownChangeDate
        self.mediaType = mediaType
        self.mediaSubtypes = mediaSubtypes
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isFavorite = isFavorite
    }
}

// MARK: - Month Bucket

/// Aggregated month for UI
nonisolated struct MonthBucket: Identifiable, Equatable, Sendable {
    let id: String       // "2024-03" for uniqueness
    let year: Int
    let month: Int       // 1-12
    let count: Int
    let totalBytes: Int64

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"  // "March 2024"
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else {
            return "\(month)/\(year)"
        }
        return formatter.string(from: date)
    }
}

// MARK: - Type Category

/// Media type categories for the Types tab
nonisolated enum TypeCategory: String, CaseIterable, Identifiable, Sendable {
    case screenshots = "Screenshots"
    case screenRecordings = "Screen Recordings"
    case videos = "Videos"
    case photos = "Photos"
    case livePhotos = "Live Photos"

    nonisolated var id: String { rawValue }

    var icon: String {
        switch self {
        case .screenshots: return "rectangle.dashed"
        case .screenRecordings: return "record.circle"
        case .videos: return "video"
        case .photos: return "photo"
        case .livePhotos: return "livephoto"
        }
    }
}

// MARK: - Type Bucket

/// Aggregated type group for UI
nonisolated struct TypeBucket: Identifiable, Equatable, Sendable {
    let category: TypeCategory
    let count: Int
    let totalBytes: Int64

    var id: String { category.rawValue }
}

// MARK: - Insight Category

/// Actionable cleanup scenarios for the Insights tab
nonisolated enum InsightCategory: String, CaseIterable, Identifiable, Sendable {
    case largeVideos = "Large Videos"
    case largePhotos = "Large Photos"
    case exactDuplicates = "Exact Duplicates"
    case heavyOldVideos = "Heavy Old Videos"
    case similarShots = "Similar Shots"
    case receipts = "Receipts"
    case chatMemeDump = "Chat/Meme Dump"
    case shortVideos = "Short Videos"

    nonisolated var id: String { rawValue }

    var icon: String {
        switch self {
        case .largeVideos: return "video.fill"
        case .largePhotos: return "photo.fill"
        case .exactDuplicates: return "square.on.square"
        case .heavyOldVideos: return "film"
        case .similarShots: return "photo.on.rectangle.angled"
        case .receipts: return "doc.text"
        case .chatMemeDump: return "message.fill"
        case .shortVideos: return "video.fill"
        }
    }

    var ruleDescription: String {
        switch self {
        case .largeVideos:
            return "Top 50 largest videos by file size (favorites excluded)"
        case .largePhotos:
            return "Top 50 largest photos by file size (favorites excluded)"
        case .exactDuplicates:
            return "Verified duplicate groups. One best copy is kept."
        case .heavyOldVideos:
            return "Videos over 200 MB, older than 90 days"
        case .similarShots:
            return "Shots taken within a few seconds"
        case .receipts:
            return "Detected from text (OCR), older than 45 days"
        case .chatMemeDump:
            return "Chat screenshots and meme-like images"
        case .shortVideos:
            return "Videos up to 6s, older than 14 days"
        }
    }
}

// MARK: - Insight Bucket

/// Aggregated cleanup recommendation for UI
nonisolated struct InsightBucket: Identifiable, Equatable, Sendable {
    let category: InsightCategory
    let count: Int
    let totalBytes: Int64

    var id: String { category.rawValue }
}

// MARK: - Library Index Snapshot

nonisolated struct LibraryIndexSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 3

    let version: Int
    let lastIndexedAt: Date
    let assets: [IndexedAsset]

    private enum CodingKeys: String, CodingKey {
        case version, lastIndexedAt, assets
    }

    init(version: Int = Self.currentVersion, lastIndexedAt: Date, assets: [IndexedAsset]) {
        self.version = version
        self.lastIndexedAt = lastIndexedAt
        self.assets = assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.lastIndexedAt = try container.decode(Date.self, forKey: .lastIndexedAt)
        self.assets = try container.decode([IndexedAsset].self, forKey: .assets)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(lastIndexedAt, forKey: .lastIndexedAt)
        try container.encode(assets, forKey: .assets)
    }

    /// Aggregated year buckets for UI
    var yearBuckets: [YearBucket] {
        guard !assets.isEmpty else { return [] }

        var counts: [Int: (count: Int, bytes: Int64)] = [:]
        for asset in assets {
            let current = counts[asset.year, default: (0, 0)]
            counts[asset.year] = (current.count + 1, current.bytes + asset.byteSize)
        }

        return counts
            .map { YearBucket(year: $0.key, count: $0.value.count, totalBytes: $0.value.bytes) }
            .sorted { $0.year > $1.year }
    }

    /// Aggregated month buckets for UI (derived from creationDate)
    var monthBuckets: [MonthBucket] {
        guard !assets.isEmpty else { return [] }
        let calendar = Calendar.current

        var counts: [String: (year: Int, month: Int, count: Int, bytes: Int64)] = [:]
        for asset in assets {
            let month = calendar.component(.month, from: asset.creationDate)
            let key = "\(asset.year)-\(String(format: "%02d", month))"
            let current = counts[key] ?? (asset.year, month, 0, 0)
            counts[key] = (current.year, current.month, current.count + 1, current.bytes + asset.byteSize)
        }

        return counts
            .map { MonthBucket(id: $0.key, year: $0.value.year, month: $0.value.month,
                               count: $0.value.count, totalBytes: $0.value.bytes) }
            .sorted { ($0.year, $0.month) > ($1.year, $1.month) }  // Newest first
    }

    /// Aggregated type buckets for UI
    var typeBuckets: [TypeBucket] {
        guard !assets.isEmpty else { return [] }

        // PHAssetMediaType raw values: 1=image, 2=video
        // PHAssetMediaSubtype: photoLive=0x8 (bit 3), photoScreenshot=0x4 (bit 2)
        // Screen recordings use undocumented value 0x80000 (bit 19)
        let photoLiveMask = 0x8
        let screenshotMask = 0x4
        let screenRecordingMask = 0x80000  // Undocumented but reliable

        var videoCount = 0, videoBytes: Int64 = 0
        var photoCount = 0, photoBytes: Int64 = 0
        var livePhotoCount = 0, livePhotoBytes: Int64 = 0
        var screenshotCount = 0, screenshotBytes: Int64 = 0
        var screenRecordingCount = 0, screenRecordingBytes: Int64 = 0

        for asset in assets {
            if asset.mediaType == 2 { // Video
                videoCount += 1
                videoBytes += asset.byteSize
                // Check if it's a screen recording
                if (asset.mediaSubtypes & screenRecordingMask) != 0 {
                    screenRecordingCount += 1
                    screenRecordingBytes += asset.byteSize
                }
            } else if asset.mediaType == 1 { // Image
                let isLivePhoto = (asset.mediaSubtypes & photoLiveMask) != 0
                let isScreenshot = (asset.mediaSubtypes & screenshotMask) != 0

                if isLivePhoto {
                    livePhotoCount += 1
                    livePhotoBytes += asset.byteSize
                } else if isScreenshot {
                    screenshotCount += 1
                    screenshotBytes += asset.byteSize
                } else {
                    photoCount += 1
                    photoBytes += asset.byteSize
                }
            }
        }

        return [
            TypeBucket(category: .screenshots, count: screenshotCount, totalBytes: screenshotBytes),
            TypeBucket(category: .screenRecordings, count: screenRecordingCount, totalBytes: screenRecordingBytes),
            TypeBucket(category: .videos, count: videoCount, totalBytes: videoBytes),
            TypeBucket(category: .photos, count: photoCount, totalBytes: photoBytes),
            TypeBucket(category: .livePhotos, count: livePhotoCount, totalBytes: livePhotoBytes)
        ]
    }

    /// Aggregated insight buckets for UI
    var insightBuckets: [InsightBucket] {
        insightBuckets(referenceDate: Date())
    }

    /// Aggregated insight buckets using an injected reference date (test-friendly)
    func insightBuckets(referenceDate: Date) -> [InsightBucket] {
        guard !assets.isEmpty else { return [] }

        var buckets: [InsightBucket] = []

        let largeVideos = assets(for: .largeVideos, referenceDate: referenceDate)
        let largeVideosBytes = largeVideos.reduce(Int64(0)) { $0 + $1.byteSize }
        if largeVideos.count >= Self.largeVideosMinCount && largeVideosBytes >= Self.largeVideosMinTotalBytes {
            buckets.append(InsightBucket(
                category: .largeVideos,
                count: largeVideos.count,
                totalBytes: largeVideosBytes
            ))
        }

        let largePhotos = assets(for: .largePhotos, referenceDate: referenceDate)
        let largePhotosBytes = largePhotos.reduce(Int64(0)) { $0 + $1.byteSize }
        if largePhotos.count >= Self.largePhotosMinCount && largePhotosBytes >= Self.largePhotosMinTotalBytes {
            buckets.append(InsightBucket(
                category: .largePhotos,
                count: largePhotos.count,
                totalBytes: largePhotosBytes
            ))
        }

        let heavyVideos = assets(for: .heavyOldVideos, referenceDate: referenceDate)
        if heavyVideos.count >= 1 {
            buckets.append(InsightBucket(
                category: .heavyOldVideos,
                count: heavyVideos.count,
                totalBytes: heavyVideos.reduce(0) { $0 + $1.byteSize }
            ))
        }

        let similarCandidates = assets(for: .similarShots, referenceDate: referenceDate)
        if similarCandidates.count >= 2 {
            buckets.append(InsightBucket(
                category: .similarShots,
                count: similarCandidates.count,
                totalBytes: similarCandidates.reduce(0) { $0 + $1.byteSize }
            ))
        }

        let shortVideos = assets(for: .shortVideos, referenceDate: referenceDate)
        if shortVideos.count >= 4 {
            buckets.append(InsightBucket(
                category: .shortVideos,
                count: shortVideos.count,
                totalBytes: shortVideos.reduce(0) { $0 + $1.byteSize }
            ))
        }

        return buckets.sorted { lhs, rhs in
            if lhs.totalBytes == rhs.totalBytes {
                return lhs.count > rhs.count
            }
            return lhs.totalBytes > rhs.totalBytes
        }
    }

    /// Get assets filtered by type category
    func assets(for category: TypeCategory) -> [IndexedAsset] {
        switch category {
        case .videos:
            return assets.filter { $0.mediaType == 2 }
                .sorted { $0.creationDate > $1.creationDate }

        case .photos:
            return assets.filter {
                $0.mediaType == 1 &&
                ($0.mediaSubtypes & Self.photoLiveMask) == 0 &&
                ($0.mediaSubtypes & Self.screenshotMask) == 0
            }
            .sorted { $0.creationDate > $1.creationDate }

        case .livePhotos:
            return assets.filter {
                $0.mediaType == 1 && ($0.mediaSubtypes & Self.photoLiveMask) != 0
            }
            .sorted { $0.creationDate > $1.creationDate }

        case .screenshots:
            return assets.filter {
                $0.mediaType == 1 && ($0.mediaSubtypes & Self.screenshotMask) != 0
            }
            .sorted { $0.creationDate > $1.creationDate }

        case .screenRecordings:
            return assets.filter {
                $0.mediaType == 2 && ($0.mediaSubtypes & Self.screenRecordingMask) != 0
            }
            .sorted { $0.creationDate > $1.creationDate }
        }
    }

    /// Get assets filtered by insight category
    func assets(for category: InsightCategory, referenceDate: Date = Date()) -> [IndexedAsset] {
        let cutoffShortVideos = Self.cutoffDate(daysAgo: Self.shortVideoMinAgeDays, referenceDate: referenceDate)
        let cutoffHeavyVideos = Self.cutoffDate(daysAgo: Self.heavyVideoMinAgeDays, referenceDate: referenceDate)
        let cutoffSimilarShots = Self.cutoffDate(daysAgo: Self.similarShotsMinAgeDays, referenceDate: referenceDate)
        let cutoffReceipts = Self.cutoffDate(daysAgo: Self.receiptMinAgeDays, referenceDate: referenceDate)

        switch category {
        case .largeVideos:
            return assets.filter {
                $0.mediaType == 2 &&
                !$0.isFavorite
            }
            .sorted { $0.byteSize > $1.byteSize }
            .prefix(Self.largeMediaLimit)
            .map { $0 }

        case .largePhotos:
            return assets.filter {
                $0.mediaType == 1 &&
                ($0.mediaSubtypes & Self.photoLiveMask) == 0 &&
                ($0.mediaSubtypes & Self.screenshotMask) == 0 &&
                !$0.isFavorite
            }
            .sorted { $0.byteSize > $1.byteSize }
            .prefix(Self.largeMediaLimit)
            .map { $0 }

        case .exactDuplicates:
            return duplicateCandidates()
                .sorted { $0.creationDate < $1.creationDate }

        case .heavyOldVideos:
            return assets.filter {
                $0.mediaType == 2 &&
                !$0.isFavorite &&
                $0.byteSize >= Self.heavyVideoMinBytes &&
                $0.creationDate < cutoffHeavyVideos
            }
            .sorted { $0.byteSize > $1.byteSize }

        case .shortVideos:
            return assets.filter {
                $0.mediaType == 2 &&
                ($0.mediaSubtypes & Self.screenRecordingMask) == 0 &&
                !$0.isFavorite &&
                $0.duration > 0 &&
                $0.duration <= Self.shortVideoMaxDuration &&
                $0.creationDate < cutoffShortVideos
            }
            .sorted { $0.creationDate < $1.creationDate }

        case .similarShots:
            return similarShotCandidates(maxCutoffDate: cutoffSimilarShots)
                .sorted { $0.creationDate < $1.creationDate }

        case .receipts:
            // Receipt detection requires OCR and is computed by ReceiptInsightService.
            return assets.filter {
                $0.mediaType == 1 &&
                $0.creationDate < cutoffReceipts
            }
            .sorted { $0.creationDate < $1.creationDate }

        case .chatMemeDump:
            return assets.filter {
                guard $0.mediaType == 1 else { return false }
                guard !$0.isFavorite else { return false }
                guard ($0.mediaSubtypes & Self.photoLiveMask) == 0 else { return false }

                let isScreenshot = ($0.mediaSubtypes & Self.screenshotMask) != 0
                let isSmallWebImage = $0.byteSize <= Self.chatMemeMaxBytes && min($0.pixelWidth, $0.pixelHeight) <= 1600
                return isScreenshot || isSmallWebImage
            }
            .sorted { $0.creationDate < $1.creationDate }
        }
    }

    private func duplicateCandidates() -> [IndexedAsset] {
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

        var result: [IndexedAsset] = []
        for group in groups.values where group.count >= 2 {
            let keeperID = Self.preferredKeeper(in: group).id
            result.append(contentsOf: group.filter { $0.id != keeperID })
        }

        return result
    }

    private func similarShotCandidates(maxCutoffDate: Date) -> [IndexedAsset] {
        let candidates = assets.filter {
            $0.mediaType == 1 &&
            $0.creationDate < maxCutoffDate &&
            ($0.mediaSubtypes & Self.screenshotMask) == 0 &&
            ($0.mediaSubtypes & Self.photoLiveMask) == 0
        }
        .sorted { $0.creationDate < $1.creationDate }

        guard candidates.count >= 3 else { return [] }

        var clusters: [[IndexedAsset]] = []
        var currentCluster: [IndexedAsset] = []

        for asset in candidates {
            if currentCluster.isEmpty {
                currentCluster.append(asset)
                continue
            }

            guard let last = currentCluster.last else { continue }
            let delta = asset.creationDate.timeIntervalSince(last.creationDate)

            if delta <= Self.similarShotsWindowSeconds {
                currentCluster.append(asset)
            } else {
                if currentCluster.count >= 3 {
                    clusters.append(currentCluster)
                }
                currentCluster = [asset]
            }
        }

        if currentCluster.count >= 3 {
            clusters.append(currentCluster)
        }

        var result: [IndexedAsset] = []
        for cluster in clusters {
            let keeperID = Self.preferredKeeper(in: cluster).id
            result.append(contentsOf: cluster.filter { $0.id != keeperID })
        }
        return result
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

    private static func cutoffDate(daysAgo: Int, referenceDate: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: referenceDate) ?? .distantPast
    }

    private struct DuplicateKey: Hashable {
        let mediaType: Int
        let byteSize: Int64
        let pixelWidth: Int
        let pixelHeight: Int
        let roundedDuration: Int
    }

    private static let photoLiveMask = 0x8
    private static let screenshotMask = 0x4
    private static let screenRecordingMask = 0x80000
    private static let shortVideoMaxDuration: TimeInterval = 6
    private static let shortVideoMinAgeDays = 14
    private static let heavyVideoMinBytes: Int64 = 200 * 1_048_576
    private static let heavyVideoMinAgeDays = 90
    private static let similarShotsWindowSeconds: TimeInterval = 8
    private static let similarShotsMinAgeDays = 7
    private static let receiptMinAgeDays = 45
    private static let chatMemeMaxBytes: Int64 = 8 * 1_048_576
    private static let largeMediaLimit = 50
    private static let largeVideosMinCount = 3
    private static let largeVideosMinTotalBytes: Int64 = 500 * 1_048_576
    private static let largePhotosMinCount = 5
    private static let largePhotosMinTotalBytes: Int64 = 300 * 1_048_576
}

// MARK: - Disk Store

actor LibraryIndexStore {
    static let shared = LibraryIndexStore()

    private nonisolated(unsafe) let fileManager: FileManager
    private let storeURL: URL

    init(fileManager: FileManager = .default, storeURL: URL? = nil) {
        self.fileManager = fileManager

        if let customURL = storeURL {
            self.storeURL = customURL
            // Ensure directory exists for custom URL
            let directory = customURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directory = appSupport.appendingPathComponent("SClean", isDirectory: true)
            self.storeURL = directory.appendingPathComponent("library-index.json")

            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }
    
    nonisolated func loadSnapshot() -> LibraryIndexSnapshot? {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: storeURL)
            let snapshot = try JSONDecoder().decode(LibraryIndexSnapshot.self, from: data)
            guard snapshot.version == LibraryIndexSnapshot.currentVersion else {
                return nil
            }
            return snapshot
        } catch {
            return nil
        }
    }
    
    nonisolated func saveSnapshot(_ snapshot: LibraryIndexSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // Intentionally ignoring write failures for MVP; caller can re-index next launch.
        }
    }
    
    nonisolated func clearSnapshot() {
        try? fileManager.removeItem(at: storeURL)
    }
}
