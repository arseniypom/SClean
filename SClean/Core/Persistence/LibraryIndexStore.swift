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
    let lastKnownChangeDate: Date

    // v2 fields for media type detection
    let mediaType: Int         // PHAssetMediaType.rawValue (1=image, 2=video)
    let mediaSubtypes: Int     // PHAssetMediaSubtype bitmask
    let duration: TimeInterval // For videos, 0 for photos

    /// Backward-compatible initializer for v1 data (defaults for new fields)
    init(id: String, year: Int, byteSize: Int64, lastKnownChangeDate: Date,
         mediaType: Int = 0, mediaSubtypes: Int = 0, duration: TimeInterval = 0) {
        self.id = id
        self.year = year
        self.byteSize = byteSize
        self.lastKnownChangeDate = lastKnownChangeDate
        self.mediaType = mediaType
        self.mediaSubtypes = mediaSubtypes
        self.duration = duration
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
    case largestVideos = "Largest Videos"
    case largestPhotos = "Largest Photos"
    case screenshots = "Screenshots"
    case screenRecordings = "Screen Recordings"
    case videos = "Videos"
    case photos = "Photos"
    case livePhotos = "Live Photos"

    nonisolated var id: String { rawValue }

    var icon: String {
        switch self {
        case .largestVideos: return "video.fill"
        case .largestPhotos: return "photo.fill"
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
    case oldScreenshots = "Old Screenshots"
    case shortVideos = "Short Videos"
    case oldScreenRecordings = "Old Screen Recordings"
    case agedLivePhotos = "Aged Live Photos"

    nonisolated var id: String { rawValue }

    var icon: String {
        switch self {
        case .oldScreenshots: return "rectangle.dashed"
        case .shortVideos: return "video.badge.clock"
        case .oldScreenRecordings: return "record.circle"
        case .agedLivePhotos: return "livephoto"
        }
    }

    var ruleDescription: String {
        switch self {
        case .oldScreenshots:
            return "Screenshots older than 45 days"
        case .shortVideos:
            return "Videos up to 10s, older than 14 days"
        case .oldScreenRecordings:
            return "Screen recordings older than 21 days"
        case .agedLivePhotos:
            return "Live Photos older than 180 days"
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
    static let currentVersion = 2  // Bumped from 1 to add mediaType/mediaSubtypes/duration

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

    /// Aggregated month buckets for UI (derived from lastKnownChangeDate)
    var monthBuckets: [MonthBucket] {
        guard !assets.isEmpty else { return [] }
        let calendar = Calendar.current

        var counts: [String: (year: Int, month: Int, count: Int, bytes: Int64)] = [:]
        for asset in assets {
            let month = calendar.component(.month, from: asset.lastKnownChangeDate)
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
            TypeBucket(category: .largestVideos, count: min(videoCount, 50), totalBytes: videoBytes),
            TypeBucket(category: .largestPhotos, count: min(photoCount, 50), totalBytes: photoBytes),
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

        let cutoffOldScreenshots = Calendar.current.date(byAdding: .day, value: -45, to: referenceDate) ?? .distantPast
        let cutoffShortVideos = Calendar.current.date(byAdding: .day, value: -14, to: referenceDate) ?? .distantPast
        let cutoffOldScreenRecordings = Calendar.current.date(byAdding: .day, value: -21, to: referenceDate) ?? .distantPast
        let cutoffAgedLivePhotos = Calendar.current.date(byAdding: .day, value: -180, to: referenceDate) ?? .distantPast

        var oldScreenshotsCount = 0, oldScreenshotsBytes: Int64 = 0
        var shortVideosCount = 0, shortVideosBytes: Int64 = 0
        var oldScreenRecordingsCount = 0, oldScreenRecordingsBytes: Int64 = 0
        var agedLivePhotosCount = 0, agedLivePhotosBytes: Int64 = 0

        for asset in assets {
            let isScreenshot = (asset.mediaSubtypes & Self.screenshotMask) != 0
            let isLivePhoto = (asset.mediaSubtypes & Self.photoLiveMask) != 0
            let isScreenRecording = (asset.mediaSubtypes & Self.screenRecordingMask) != 0
            let assetDate = asset.lastKnownChangeDate

            if asset.mediaType == 1, isScreenshot, assetDate < cutoffOldScreenshots {
                oldScreenshotsCount += 1
                oldScreenshotsBytes += asset.byteSize
            }

            if asset.mediaType == 2, isScreenRecording, assetDate < cutoffOldScreenRecordings {
                oldScreenRecordingsCount += 1
                oldScreenRecordingsBytes += asset.byteSize
            }

            if asset.mediaType == 2,
               !isScreenRecording,
               asset.duration > 0,
               asset.duration <= 10,
               assetDate < cutoffShortVideos {
                shortVideosCount += 1
                shortVideosBytes += asset.byteSize
            }

            if asset.mediaType == 1, isLivePhoto, assetDate < cutoffAgedLivePhotos {
                agedLivePhotosCount += 1
                agedLivePhotosBytes += asset.byteSize
            }
        }

        var buckets: [InsightBucket] = []
        if oldScreenshotsCount >= 12 {
            buckets.append(InsightBucket(
                category: .oldScreenshots,
                count: oldScreenshotsCount,
                totalBytes: oldScreenshotsBytes
            ))
        }
        if shortVideosCount >= 8 {
            buckets.append(InsightBucket(
                category: .shortVideos,
                count: shortVideosCount,
                totalBytes: shortVideosBytes
            ))
        }
        if oldScreenRecordingsCount >= 3 {
            buckets.append(InsightBucket(
                category: .oldScreenRecordings,
                count: oldScreenRecordingsCount,
                totalBytes: oldScreenRecordingsBytes
            ))
        }
        if agedLivePhotosCount >= 8 {
            buckets.append(InsightBucket(
                category: .agedLivePhotos,
                count: agedLivePhotosCount,
                totalBytes: agedLivePhotosBytes
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
                .sorted { $0.lastKnownChangeDate > $1.lastKnownChangeDate }

        case .largestVideos:
            return assets.filter { $0.mediaType == 2 }
                .sorted { $0.byteSize > $1.byteSize }
                .prefix(50)
                .map { $0 }

        case .photos:
            return assets.filter {
                $0.mediaType == 1 &&
                ($0.mediaSubtypes & Self.photoLiveMask) == 0 &&
                ($0.mediaSubtypes & Self.screenshotMask) == 0
            }
            .sorted { $0.lastKnownChangeDate > $1.lastKnownChangeDate }

        case .largestPhotos:
            return assets.filter {
                $0.mediaType == 1 &&
                ($0.mediaSubtypes & Self.photoLiveMask) == 0 &&
                ($0.mediaSubtypes & Self.screenshotMask) == 0
            }
            .sorted { $0.byteSize > $1.byteSize }
            .prefix(50)
            .map { $0 }

        case .livePhotos:
            return assets.filter {
                $0.mediaType == 1 && ($0.mediaSubtypes & Self.photoLiveMask) != 0
            }
            .sorted { $0.lastKnownChangeDate > $1.lastKnownChangeDate }

        case .screenshots:
            return assets.filter {
                $0.mediaType == 1 && ($0.mediaSubtypes & Self.screenshotMask) != 0
            }
            .sorted { $0.lastKnownChangeDate > $1.lastKnownChangeDate }

        case .screenRecordings:
            return assets.filter {
                $0.mediaType == 2 && ($0.mediaSubtypes & Self.screenRecordingMask) != 0
            }
            .sorted { $0.lastKnownChangeDate > $1.lastKnownChangeDate }
        }
    }

    /// Get assets filtered by insight category
    func assets(for category: InsightCategory, referenceDate: Date = Date()) -> [IndexedAsset] {
        let cutoffOldScreenshots = Calendar.current.date(byAdding: .day, value: -45, to: referenceDate) ?? .distantPast
        let cutoffShortVideos = Calendar.current.date(byAdding: .day, value: -14, to: referenceDate) ?? .distantPast
        let cutoffOldScreenRecordings = Calendar.current.date(byAdding: .day, value: -21, to: referenceDate) ?? .distantPast
        let cutoffAgedLivePhotos = Calendar.current.date(byAdding: .day, value: -180, to: referenceDate) ?? .distantPast

        switch category {
        case .oldScreenshots:
            return assets.filter {
                $0.mediaType == 1 &&
                ($0.mediaSubtypes & Self.screenshotMask) != 0 &&
                $0.lastKnownChangeDate < cutoffOldScreenshots
            }
            .sorted { $0.lastKnownChangeDate < $1.lastKnownChangeDate }

        case .shortVideos:
            return assets.filter {
                $0.mediaType == 2 &&
                ($0.mediaSubtypes & Self.screenRecordingMask) == 0 &&
                $0.duration > 0 &&
                $0.duration <= 10 &&
                $0.lastKnownChangeDate < cutoffShortVideos
            }
            .sorted { $0.lastKnownChangeDate < $1.lastKnownChangeDate }

        case .oldScreenRecordings:
            return assets.filter {
                $0.mediaType == 2 &&
                ($0.mediaSubtypes & Self.screenRecordingMask) != 0 &&
                $0.lastKnownChangeDate < cutoffOldScreenRecordings
            }
            .sorted { $0.lastKnownChangeDate < $1.lastKnownChangeDate }

        case .agedLivePhotos:
            return assets.filter {
                $0.mediaType == 1 &&
                ($0.mediaSubtypes & Self.photoLiveMask) != 0 &&
                $0.lastKnownChangeDate < cutoffAgedLivePhotos
            }
            .sorted { $0.lastKnownChangeDate < $1.lastKnownChangeDate }
        }
    }

    private static let photoLiveMask = 0x8
    private static let screenshotMask = 0x4
    private static let screenRecordingMask = 0x80000
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
