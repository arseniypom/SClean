//
//  InsightPhotosService.swift
//  SClean
//
//  Fetches photos for a specific insight category.
//

import Photos
import SwiftUI
import Combine

// MARK: - Insight Photos State

nonisolated enum InsightPhotosState: Equatable, Sendable {
    case idle
    case loading
    case loaded([YearAsset])
    case empty
    case error(String)

    var assets: [YearAsset] {
        if case .loaded(let items) = self {
            return items
        }
        return []
    }

    var isLoading: Bool {
        self == .loading
    }
}

// MARK: - Insight Photos Service

@MainActor
final class InsightPhotosService: ObservableObject {

    let category: InsightCategory

    @Published private(set) var state: InsightPhotosState = .idle

    private let snapshot: LibraryIndexSnapshot?

    init(category: InsightCategory, snapshot: LibraryIndexSnapshot?) {
        self.category = category
        self.snapshot = snapshot
    }

    // MARK: - Public Methods

    /// Fetches all photos for the given insight category
    func fetchPhotos(referenceDate: Date = Date()) async {
        state = .loading

        guard let snapshot = snapshot else {
            state = .error("No index available")
            return
        }

        let category = self.category
        let assets = await Task.detached(priority: .userInitiated) {
            Self.fetchAssetsForCategory(category, snapshot: snapshot, referenceDate: referenceDate)
        }.value

        if assets.isEmpty {
            state = .empty
        } else {
            state = .loaded(assets)
        }
    }

    // MARK: - Private Methods

    private nonisolated static func fetchAssetsForCategory(
        _ category: InsightCategory,
        snapshot: LibraryIndexSnapshot,
        referenceDate: Date
    ) -> [YearAsset] {
        let indexedAssets = snapshot.assets(for: category, referenceDate: referenceDate)
        guard !indexedAssets.isEmpty else { return [] }

        let identifiers = indexedAssets.map { $0.id }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)

        var phAssetByIdentifier: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            phAssetByIdentifier[asset.localIdentifier] = asset
        }

        var results: [YearAsset] = []
        results.reserveCapacity(indexedAssets.count)

        for indexed in indexedAssets {
            guard let phAsset = phAssetByIdentifier[indexed.id] else { continue }

            let mediaType: MediaType
            switch phAsset.mediaType {
            case .video:
                mediaType = .video
            case .image:
                mediaType = phAsset.mediaSubtypes.contains(.photoLive) ? .livePhoto : .photo
            default:
                mediaType = .unknown
            }

            results.append(
                YearAsset(
                    id: phAsset.localIdentifier,
                    creationDate: phAsset.creationDate ?? Date.distantPast,
                    mediaType: mediaType,
                    duration: phAsset.duration
                )
            )
        }

        return results
    }
}
