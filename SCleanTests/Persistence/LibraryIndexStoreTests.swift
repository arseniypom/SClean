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

    // MARK: - Insights Tests

    @Test func snapshot_insightBuckets_buildsAndSortsBySavings() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026
        let oldDate = Date(timeIntervalSince1970: 1_746_576_000) // May 8, 2025

        var assets: [IndexedAsset] = []

        // 12 old screenshots
        for index in 0..<12 {
            assets.append(
                TestFactory.indexedAsset(
                    id: "screenshot-\(index)",
                    byteSize: 5 * TestBytes.oneMB,
                    lastKnownChangeDate: oldDate,
                    mediaType: 1,
                    mediaSubtypes: 0x4
                )
            )
        }

        // 8 short videos
        for index in 0..<8 {
            assets.append(
                TestFactory.indexedAsset(
                    id: "short-video-\(index)",
                    byteSize: 20 * TestBytes.oneMB,
                    lastKnownChangeDate: oldDate,
                    mediaType: 2,
                    duration: 8
                )
            )
        }

        // 3 old screen recordings
        for index in 0..<3 {
            assets.append(
                TestFactory.indexedAsset(
                    id: "screen-recording-\(index)",
                    byteSize: 100 * TestBytes.oneMB,
                    lastKnownChangeDate: oldDate,
                    mediaType: 2,
                    mediaSubtypes: 0x80000,
                    duration: 30
                )
            )
        }

        // 8 aged live photos
        for index in 0..<8 {
            assets.append(
                TestFactory.indexedAsset(
                    id: "live-photo-\(index)",
                    byteSize: 6 * TestBytes.oneMB,
                    lastKnownChangeDate: oldDate,
                    mediaType: 1,
                    mediaSubtypes: 0x8
                )
            )
        }

        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let buckets = snapshot.insightBuckets(referenceDate: referenceDate)

        #expect(buckets.count == 4)
        #expect(buckets[0].category == .oldScreenRecordings)
        #expect(buckets[1].category == .shortVideos)
        #expect(buckets[2].category == .oldScreenshots)
        #expect(buckets[3].category == .agedLivePhotos)
    }

    @Test func snapshot_insightBuckets_skipsNonActionableSmallGroups() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026
        let oldDate = Date(timeIntervalSince1970: 1_746_576_000) // May 8, 2025

        let assets = [
            TestFactory.indexedAsset(id: "s1", lastKnownChangeDate: oldDate, mediaType: 1, mediaSubtypes: 0x4),
            TestFactory.indexedAsset(id: "s2", lastKnownChangeDate: oldDate, mediaType: 1, mediaSubtypes: 0x4),
            TestFactory.indexedAsset(id: "v1", lastKnownChangeDate: oldDate, mediaType: 2, duration: 8),
            TestFactory.indexedAsset(id: "v2", lastKnownChangeDate: oldDate, mediaType: 2, duration: 7),
            TestFactory.indexedAsset(id: "r1", lastKnownChangeDate: oldDate, mediaType: 2, mediaSubtypes: 0x80000)
        ]

        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let buckets = snapshot.insightBuckets(referenceDate: referenceDate)

        #expect(buckets.isEmpty)
    }

    @Test func snapshot_assetsForShortVideos_appliesAgeDurationAndSubtypeFilters() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026
        let oldDate = Date(timeIntervalSince1970: 1_746_576_000) // May 8, 2025
        let recentDate = Date(timeIntervalSince1970: 1_766_880_000) // December 28, 2025

        let assets = [
            TestFactory.indexedAsset(id: "keep-oldest", lastKnownChangeDate: oldDate, mediaType: 2, duration: 4),
            TestFactory.indexedAsset(id: "keep-newer", lastKnownChangeDate: oldDate.addingTimeInterval(3_600), mediaType: 2, duration: 9),
            TestFactory.indexedAsset(id: "skip-too-long", lastKnownChangeDate: oldDate, mediaType: 2, duration: 25),
            TestFactory.indexedAsset(id: "skip-recent", lastKnownChangeDate: recentDate, mediaType: 2, duration: 6),
            TestFactory.indexedAsset(id: "skip-screen-recording", lastKnownChangeDate: oldDate, mediaType: 2, mediaSubtypes: 0x80000, duration: 5)
        ]

        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let filtered = snapshot.assets(for: .shortVideos, referenceDate: referenceDate)

        #expect(filtered.map(\.id) == ["keep-oldest", "keep-newer"])
    }

    @Test func snapshot_assetsForOldScreenshots_appliesAgeCutoff() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026
        let oldDate = Date(timeIntervalSince1970: 1_746_576_000) // May 8, 2025
        let recentDate = Date(timeIntervalSince1970: 1_766_966_400) // December 29, 2025

        let assets = [
            TestFactory.indexedAsset(id: "old-shot", lastKnownChangeDate: oldDate, mediaType: 1, mediaSubtypes: 0x4),
            TestFactory.indexedAsset(id: "recent-shot", lastKnownChangeDate: recentDate, mediaType: 1, mediaSubtypes: 0x4),
            TestFactory.indexedAsset(id: "old-non-shot", lastKnownChangeDate: oldDate, mediaType: 1, mediaSubtypes: 0)
        ]

        let snapshot = TestFactory.librarySnapshot(assets: assets)
        let filtered = snapshot.assets(for: .oldScreenshots, referenceDate: referenceDate)

        #expect(filtered.map(\.id) == ["old-shot"])
    }
}
