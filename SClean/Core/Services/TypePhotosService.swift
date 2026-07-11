//
//  TypePhotosService.swift
//  SClean
//
//  Fetches photos for a specific type category
//

import Photos
import SwiftUI
import Combine

// MARK: - Type Photos State

nonisolated enum TypePhotosState: Equatable, Sendable {
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

// MARK: - Type Photos Service

@MainActor
final class TypePhotosService: ObservableObject {

    let category: TypeCategory

    @Published private(set) var state: TypePhotosState = .idle

    private let snapshot: LibraryIndexSnapshot?

    init(category: TypeCategory, snapshot: LibraryIndexSnapshot?) {
        self.category = category
        self.snapshot = snapshot
    }

    // MARK: - Public Methods

    /// Fetches all photos for the given type category
    func fetchPhotos() async {
        state = .loading

        guard let snapshot = snapshot else {
            state = .error("No index available")
            return
        }

        let category = self.category
        let assets = await Task.detached(priority: .userInitiated) {
            Self.fetchAssetsForCategory(category, snapshot: snapshot)
        }.value

        if assets.isEmpty {
            state = .empty
        } else {
            state = .loaded(assets)
        }
    }

    // MARK: - Private Methods

    private nonisolated static func fetchAssetsForCategory(
        _ category: TypeCategory,
        snapshot: LibraryIndexSnapshot
    ) -> [YearAsset] {
        // Get filtered indexed assets from snapshot
        let indexedAssets = snapshot.assets(for: category)

        guard !indexedAssets.isEmpty else { return [] }

        // Fetch PHAssets by IDs
        let identifiers = indexedAssets.map { $0.id }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)

        // Build PHAsset results in the order from indexedAssets (preserves sort order)
        var assetMap: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { phAsset, _, _ in
            assetMap[phAsset.localIdentifier] = phAsset
        }

        var result: [YearAsset] = []
        result.reserveCapacity(indexedAssets.count)

        for indexed in indexedAssets {
            guard let phAsset = assetMap[indexed.id] else { continue }

            let mediaType: MediaType
            switch phAsset.mediaType {
            case .video:
                mediaType = .video
            case .image:
                if phAsset.mediaSubtypes.contains(.photoLive) {
                    mediaType = .livePhoto
                } else {
                    mediaType = .photo
                }
            default:
                mediaType = .unknown
            }

            let asset = YearAsset(
                id: phAsset.localIdentifier,
                creationDate: phAsset.creationDate ?? Date.distantPast,
                mediaType: mediaType,
                duration: phAsset.duration
            )
            result.append(asset)
        }

        return result
    }
}
