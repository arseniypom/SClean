//
//  LibraryIndexStoreTests.swift
//  SCleanTests
//
//  Tests for LibraryIndexStore
//

import Testing
import Foundation
@testable import SClean

struct LibraryIndexStoreTests {

    // MARK: - Test Setup

    private func makeTempStoreURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("SCleanTests-\(UUID().uuidString)", isDirectory: true)
        return testDir.appendingPathComponent("library-index.json")
    }

    private func cleanup(_ url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Save/Load Tests

    @Test func saveAndLoad_roundTrips() async throws {
        let storeURL = makeTempStoreURL()
        defer { cleanup(storeURL) }

        let store = LibraryIndexStore(storeURL: storeURL)

        let assets = [
            TestFactory.indexedAsset(id: "asset1", year: 2024, byteSize: 1000),
            TestFactory.indexedAsset(id: "asset2", year: 2023, byteSize: 2000)
        ]
        let snapshot = TestFactory.librarySnapshot(assets: assets)

        store.saveSnapshot(snapshot)
        let loaded = store.loadSnapshot()

        #expect(loaded != nil)
        #expect(loaded?.assets.count == 2)
        #expect(loaded?.version == LibraryIndexSnapshot.currentVersion)
    }

    @Test func load_returnsNilWhenNoFile() async throws {
        let storeURL = makeTempStoreURL()
        defer { cleanup(storeURL) }

        let store = LibraryIndexStore(storeURL: storeURL)

        let loaded = store.loadSnapshot()

        #expect(loaded == nil)
    }

    @Test func load_returnsNilForVersionMismatch() async throws {
        let storeURL = makeTempStoreURL()
        defer { cleanup(storeURL) }

        // Create snapshot with wrong version
        let oldSnapshot = LibraryIndexSnapshot(
            version: 999, // Wrong version
            lastIndexedAt: Date(),
            assets: []
        )

        // Manually write to file to bypass version check in save
        let directory = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(oldSnapshot)
        try data.write(to: storeURL)

        let store = LibraryIndexStore(storeURL: storeURL)
        let loaded = store.loadSnapshot()

        #expect(loaded == nil)
    }

    @Test func clearSnapshot_deletesFile() async throws {
        let storeURL = makeTempStoreURL()
        defer { cleanup(storeURL) }

        let store = LibraryIndexStore(storeURL: storeURL)

        // Save a snapshot
        let snapshot = TestFactory.librarySnapshot(assets: [
            TestFactory.indexedAsset(id: "asset1")
        ])
        store.saveSnapshot(snapshot)
        #expect(store.loadSnapshot() != nil)

        // Clear and verify
        store.clearSnapshot()
        #expect(store.loadSnapshot() == nil)
    }

    @Test func save_createsDirectoryIfNeeded() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let nestedDir = tempDir
            .appendingPathComponent("SCleanTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("deep", isDirectory: true)
        let storeURL = nestedDir.appendingPathComponent("library-index.json")
        defer { cleanup(tempDir.appendingPathComponent(nestedDir.pathComponents[tempDir.pathComponents.count])) }

        let store = LibraryIndexStore(storeURL: storeURL)

        let snapshot = TestFactory.librarySnapshot(assets: [
            TestFactory.indexedAsset(id: "asset1")
        ])
        store.saveSnapshot(snapshot)

        let loaded = store.loadSnapshot()
        #expect(loaded != nil)
    }

    // MARK: - LibraryIndexSnapshot Tests

    @Test func snapshot_yearBuckets_aggregatesCorrectly() {
        let assets = [
            TestFactory.indexedAsset(id: "a1", year: 2024, byteSize: 1000),
            TestFactory.indexedAsset(id: "a2", year: 2024, byteSize: 2000),
            TestFactory.indexedAsset(id: "a3", year: 2024, byteSize: 3000),
            TestFactory.indexedAsset(id: "b1", year: 2023, byteSize: 500),
            TestFactory.indexedAsset(id: "b2", year: 2023, byteSize: 500)
        ]
        let snapshot = TestFactory.librarySnapshot(assets: assets)

        let buckets = snapshot.yearBuckets

        #expect(buckets.count == 2)

        let bucket2024 = buckets.first { $0.year == 2024 }
        #expect(bucket2024?.count == 3)
        #expect(bucket2024?.totalBytes == 6000)

        let bucket2023 = buckets.first { $0.year == 2023 }
        #expect(bucket2023?.count == 2)
        #expect(bucket2023?.totalBytes == 1000)
    }

    @Test func snapshot_yearBuckets_sortedNewestFirst() {
        let assets = [
            TestFactory.indexedAsset(id: "a1", year: 2020),
            TestFactory.indexedAsset(id: "a2", year: 2024),
            TestFactory.indexedAsset(id: "a3", year: 2022)
        ]
        let snapshot = TestFactory.librarySnapshot(assets: assets)

        let buckets = snapshot.yearBuckets

        #expect(buckets.map(\.year) == [2024, 2022, 2020])
    }

    @Test func snapshot_codable_roundTrips() throws {
        let assets = [
            TestFactory.indexedAsset(id: "asset1", year: 2024, byteSize: 1000)
        ]
        let original = TestFactory.librarySnapshot(
            lastIndexedAt: Date(timeIntervalSince1970: 1000000),
            assets: assets
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LibraryIndexSnapshot.self, from: data)

        #expect(decoded == original)
    }
    
    @Test func snapshot_monthBuckets_useCreationMonthNotModificationMonth() {
        let creationDate = Date(timeIntervalSince1970: 1_706_745_600) // February 1, 2024
        let modificationDate = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026

        let assets = [
            TestFactory.indexedAsset(
                id: "mismatch-month",
                year: 2024,
                creationDate: creationDate,
                lastKnownChangeDate: modificationDate,
                mediaType: 1
            )
        ]
        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let buckets = snapshot.monthBuckets

        #expect(buckets.count == 1)
        #expect(buckets[0].id == "2024-02")
    }
    
    // MARK: - Type Sorting Tests
    
    @Test func snapshot_assetsForScreenshots_sortedByCreationDateNotModificationDate() {
        let oldCreation = Date(timeIntervalSince1970: 1_640_995_200) // January 1, 2022
        let newCreation = Date(timeIntervalSince1970: 1_735_689_600) // January 1, 2025
        let veryRecentModification = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026

        let assets = [
            TestFactory.indexedAsset(
                id: "old-but-modified-recently",
                year: 2022,
                creationDate: oldCreation,
                lastKnownChangeDate: veryRecentModification,
                mediaType: 1,
                mediaSubtypes: 0x4
            ),
            TestFactory.indexedAsset(
                id: "newer-screenshot",
                year: 2025,
                creationDate: newCreation,
                lastKnownChangeDate: newCreation,
                mediaType: 1,
                mediaSubtypes: 0x4
            )
        ]

        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let result = snapshot.assets(for: .screenshots)

        #expect(result.map(\.id) == ["newer-screenshot", "old-but-modified-recently"])
    }
    
    @Test func snapshot_assetsForVideos_sortedByCreationDateNotModificationDate() {
        let oldCreation = Date(timeIntervalSince1970: 1_609_459_200) // January 1, 2021
        let newCreation = Date(timeIntervalSince1970: 1_704_067_200) // January 1, 2024
        let veryRecentModification = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026

        let assets = [
            TestFactory.indexedAsset(
                id: "old-video-modified-recently",
                year: 2021,
                creationDate: oldCreation,
                lastKnownChangeDate: veryRecentModification,
                mediaType: 2,
                duration: 12
            ),
            TestFactory.indexedAsset(
                id: "newer-video",
                year: 2024,
                creationDate: newCreation,
                lastKnownChangeDate: newCreation,
                mediaType: 2,
                duration: 12
            )
        ]

        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let result = snapshot.assets(for: .videos)

        #expect(result.map(\.id) == ["newer-video", "old-video-modified-recently"])
    }

    // MARK: - Insights Tests

    @Test func snapshot_insightBuckets_buildsAndSortsBySavings() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026
        let oldDate = Date(timeIntervalSince1970: 1_746_576_000) // May 8, 2025

        var assets: [IndexedAsset] = []

        // Exact duplicate group (3 -> 2 candidates)
        for index in 0..<3 {
            assets.append(
                TestFactory.indexedAsset(
                    id: "dup-\(index)",
                    byteSize: 4 * TestBytes.oneMB,
                    creationDate: oldDate.addingTimeInterval(Double(index)),
                    lastKnownChangeDate: oldDate,
                    mediaType: 1,
                    pixelWidth: 1200,
                    pixelHeight: 900,
                    isFavorite: index == 0
                )
            )
        }

        // Heavy old videos
        for index in 0..<3 {
            assets.append(
                TestFactory.indexedAsset(
                    id: "heavy-\(index)",
                    byteSize: 300 * TestBytes.oneMB,
                    creationDate: oldDate,
                    lastKnownChangeDate: oldDate,
                    mediaType: 2,
                    duration: 58
                )
            )
        }

        // Short videos (<= 6 sec)
        for index in 0..<8 {
            assets.append(
                TestFactory.indexedAsset(
                    id: "short-video-\(index)",
                    byteSize: 10 * TestBytes.oneMB,
                    creationDate: oldDate.addingTimeInterval(Double(index)),
                    lastKnownChangeDate: oldDate,
                    mediaType: 2,
                    duration: 6
                )
            )
        }

        // Similar shots cluster (4 -> 3 candidates)
        for index in 0..<4 {
            assets.append(
                TestFactory.indexedAsset(
                    id: "similar-\(index)",
                    byteSize: 6 * TestBytes.oneMB,
                    creationDate: oldDate.addingTimeInterval(Double(index)),
                    lastKnownChangeDate: oldDate,
                    mediaType: 1,
                    pixelWidth: 2000,
                    pixelHeight: 1500
                )
            )
        }

        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let buckets = snapshot.insightBuckets(referenceDate: referenceDate)

        #expect(buckets.count == 3)
        #expect(buckets[0].category == .heavyOldVideos)
        #expect(buckets[1].category == .shortVideos)
        #expect(buckets[2].category == .similarShots)
    }

    @Test func snapshot_insightBuckets_skipsNonActionableSmallGroups() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026
        let oldDate = Date(timeIntervalSince1970: 1_746_576_000) // May 8, 2025

        let assets = [
            TestFactory.indexedAsset(id: "single-photo", byteSize: 3 * TestBytes.oneMB, creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 1),
            TestFactory.indexedAsset(id: "short1", creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 2, duration: 5),
            TestFactory.indexedAsset(id: "short2", creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 2, duration: 5)
        ]

        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let buckets = snapshot.insightBuckets(referenceDate: referenceDate)

        #expect(buckets.isEmpty)
    }

    @Test func snapshot_assetsForExactDuplicates_excludesPreferredKeeper() {
        let oldDate = Date(timeIntervalSince1970: 1_746_576_000)
        let assets = [
            TestFactory.indexedAsset(id: "keep", creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 1, isFavorite: true, byteSize: 4 * TestBytes.oneMB),
            TestFactory.indexedAsset(id: "delete1", creationDate: oldDate.addingTimeInterval(1), lastKnownChangeDate: oldDate, mediaType: 1, byteSize: 4 * TestBytes.oneMB),
            TestFactory.indexedAsset(id: "delete2", creationDate: oldDate.addingTimeInterval(2), lastKnownChangeDate: oldDate, mediaType: 1, byteSize: 4 * TestBytes.oneMB)
        ]
        let snapshot = TestFactory.librarySnapshot(assets: assets)

        let filtered = snapshot.assets(for: .exactDuplicates)
        #expect(filtered.map(\.id).sorted() == ["delete1", "delete2"])
    }

    @Test func snapshot_assetsForHeavyOldVideos_appliesSizeAgeAndFavoriteFilters() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026
        let oldDate = Date(timeIntervalSince1970: 1_746_576_000) // May 8, 2025
        let recentDate = Date(timeIntervalSince1970: 1_766_880_000) // December 28, 2025

        let assets = [
            TestFactory.indexedAsset(id: "keep-1", byteSize: 350 * TestBytes.oneMB, creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 2),
            TestFactory.indexedAsset(id: "keep-2", byteSize: 210 * TestBytes.oneMB, creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 2),
            TestFactory.indexedAsset(id: "skip-small", byteSize: 150 * TestBytes.oneMB, creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 2),
            TestFactory.indexedAsset(id: "skip-recent", byteSize: 400 * TestBytes.oneMB, creationDate: recentDate, lastKnownChangeDate: recentDate, mediaType: 2),
            TestFactory.indexedAsset(id: "skip-favorite", byteSize: 500 * TestBytes.oneMB, creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 2, isFavorite: true)
        ]

        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let filtered = snapshot.assets(for: .heavyOldVideos, referenceDate: referenceDate)

        #expect(filtered.map(\.id) == ["keep-1", "keep-2"])
    }

    @Test func snapshot_assetsForSimilarShots_clustersByTimeWindow() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
        let baseDate = Date(timeIntervalSince1970: 1_746_576_000)
        let assets = [
            TestFactory.indexedAsset(id: "cluster-1", creationDate: baseDate, lastKnownChangeDate: baseDate, mediaType: 1, byteSize: 5 * TestBytes.oneMB),
            TestFactory.indexedAsset(id: "cluster-2", creationDate: baseDate.addingTimeInterval(2), lastKnownChangeDate: baseDate, mediaType: 1, byteSize: 6 * TestBytes.oneMB),
            TestFactory.indexedAsset(id: "cluster-3", creationDate: baseDate.addingTimeInterval(4), lastKnownChangeDate: baseDate, mediaType: 1, byteSize: 7 * TestBytes.oneMB),
            TestFactory.indexedAsset(id: "cluster-4", creationDate: baseDate.addingTimeInterval(6), lastKnownChangeDate: baseDate, mediaType: 1, byteSize: 4 * TestBytes.oneMB),
            TestFactory.indexedAsset(id: "single", creationDate: baseDate.addingTimeInterval(30), lastKnownChangeDate: baseDate, mediaType: 1, byteSize: 9 * TestBytes.oneMB)
        ]
        let snapshot = TestFactory.librarySnapshot(assets: assets)

        let filtered = snapshot.assets(for: .similarShots, referenceDate: referenceDate)
        #expect(filtered.count == 3)
        #expect(!filtered.map(\.id).contains("cluster-3")) // largest in cluster kept
    }

    @Test func snapshot_assetsForShortVideos_applies6SecondThreshold() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026
        let oldDate = Date(timeIntervalSince1970: 1_746_576_000) // May 8, 2025
        let recentDate = Date(timeIntervalSince1970: 1_766_966_400) // December 29, 2025

        let assets = [
            TestFactory.indexedAsset(id: "keep-6s", creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 2, duration: 6),
            TestFactory.indexedAsset(id: "skip-over", creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 2, duration: 6.1),
            TestFactory.indexedAsset(id: "skip-recent", creationDate: recentDate, lastKnownChangeDate: recentDate, mediaType: 2, duration: 5),
            TestFactory.indexedAsset(id: "skip-screen-record", creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 2, mediaSubtypes: 0x80000, duration: 5),
            TestFactory.indexedAsset(id: "skip-favorite", creationDate: oldDate, lastKnownChangeDate: oldDate, mediaType: 2, duration: 4, isFavorite: true)
        ]

        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let filtered = snapshot.assets(for: .shortVideos, referenceDate: referenceDate)

        #expect(filtered.map(\.id) == ["keep-6s"])
    }

    @Test func snapshot_assetsForChatMemeDump_appliesFavoriteAndHeuristics() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026
        let oldDate = Date(timeIntervalSince1970: 1_746_576_000) // May 8, 2025
        let recentDate = Date(timeIntervalSince1970: 1_766_966_400) // December 29, 2025

        let assets = [
            // Keep: old screenshot
            TestFactory.indexedAsset(
                id: "keep-screenshot",
                byteSize: 3 * TestBytes.oneMB,
                creationDate: oldDate,
                lastKnownChangeDate: oldDate,
                mediaType: 1,
                mediaSubtypes: 0x4
            ),
            // Keep: old small image likely from chat/web
            TestFactory.indexedAsset(
                id: "keep-small-web",
                byteSize: Int64(1.5 * Double(TestBytes.oneMB)),
                creationDate: oldDate.addingTimeInterval(10),
                lastKnownChangeDate: oldDate,
                mediaType: 1,
                pixelWidth: 1080,
                pixelHeight: 1080
            ),
            // Keep: recent screenshot (no age rule)
            TestFactory.indexedAsset(
                id: "keep-recent",
                byteSize: 2 * TestBytes.oneMB,
                creationDate: recentDate,
                lastKnownChangeDate: recentDate,
                mediaType: 1,
                mediaSubtypes: 0x4
            ),
            // Skip: favorite
            TestFactory.indexedAsset(
                id: "skip-favorite",
                byteSize: 2 * TestBytes.oneMB,
                creationDate: oldDate,
                lastKnownChangeDate: oldDate,
                mediaType: 1,
                mediaSubtypes: 0x4,
                isFavorite: true
            ),
            // Skip: live photo
            TestFactory.indexedAsset(
                id: "skip-live",
                byteSize: 2 * TestBytes.oneMB,
                creationDate: oldDate,
                lastKnownChangeDate: oldDate,
                mediaType: 1,
                mediaSubtypes: 0x8
            ),
            // Skip: large non-screenshot photo
            TestFactory.indexedAsset(
                id: "skip-large-photo",
                byteSize: 18 * TestBytes.oneMB,
                creationDate: oldDate,
                lastKnownChangeDate: oldDate,
                mediaType: 1,
                pixelWidth: 4032,
                pixelHeight: 3024
            )
        ]

        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let filtered = snapshot.assets(for: .chatMemeDump, referenceDate: referenceDate)

        #expect(filtered.map(\.id) == ["keep-screenshot", "keep-small-web", "keep-recent"])
    }
}
