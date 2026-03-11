//
//  TestHelpers.swift
//  SCleanTests
//
//  Factory functions and utilities for test data
//

import Foundation
@testable import SClean

/// Factory for creating test data
enum TestFactory {

    /// Create a YearAsset for testing
    static func yearAsset(
        id: String,
        creationDate: Date = Date(),
        mediaType: MediaType = .photo,
        duration: TimeInterval = 0
    ) -> YearAsset {
        YearAsset(
            id: id,
            creationDate: creationDate,
            mediaType: mediaType,
            duration: duration
        )
    }

    /// Create multiple YearAssets with sequential IDs
    static func yearAssets(count: Int, year: Int = 2024) -> [YearAsset] {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = 6
        components.day = 15
        let baseDate = calendar.date(from: components) ?? Date()

        return (0..<count).map { index in
            yearAsset(
                id: "asset-\(index)",
                creationDate: baseDate.addingTimeInterval(TimeInterval(index * 3600))
            )
        }
    }

    /// Create a TrashedItem for testing
    static func trashedItem(
        assetID: String,
        trashedAt: Date = Date()
    ) -> TrashedItem {
        TrashedItem(assetID: assetID, trashedAt: trashedAt)
    }

    /// Create an IndexedAsset for testing
    static func indexedAsset(
        id: String,
        year: Int = 2024,
        byteSize: Int64 = 1_000_000,
        creationDate: Date = Date(),
        lastKnownChangeDate: Date = Date(),
        mediaType: Int = 0,
        mediaSubtypes: Int = 0,
        duration: TimeInterval = 0,
        pixelWidth: Int = 1200,
        pixelHeight: Int = 900,
        isFavorite: Bool = false
    ) -> IndexedAsset {
        IndexedAsset(
            id: id,
            year: year,
            byteSize: byteSize,
            creationDate: creationDate,
            lastKnownChangeDate: lastKnownChangeDate,
            mediaType: mediaType,
            mediaSubtypes: mediaSubtypes,
            duration: duration,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            isFavorite: isFavorite
        )
    }

    /// Create a LibraryIndexSnapshot for testing
    static func librarySnapshot(
        version: Int = LibraryIndexSnapshot.currentVersion,
        lastIndexedAt: Date = Date(),
        assets: [IndexedAsset] = []
    ) -> LibraryIndexSnapshot {
        LibraryIndexSnapshot(
            version: version,
            lastIndexedAt: lastIndexedAt,
            assets: assets
        )
    }
}

/// Byte size constants for readable tests
enum TestBytes {
    static let oneMB: Int64 = 1_048_576
    static let oneGB: Int64 = 1_073_741_824
    static let halfGB: Int64 = 536_870_912
    static let twoGB: Int64 = 2_147_483_648
}
