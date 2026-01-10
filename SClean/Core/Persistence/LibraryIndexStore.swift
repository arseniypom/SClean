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

// MARK: - Library Index Snapshot

nonisolated struct LibraryIndexSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

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
