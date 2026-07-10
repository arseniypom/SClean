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
    @Published private(set) var exactDuplicateGroupByAssetID: [String: Int] = [:]
    @Published private(set) var exactDuplicateDeletableIDs: Set<String> = []
    @Published private(set) var exactDuplicateKeeperIDs: Set<String> = []

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
        let assets: [YearAsset]
        if category == .exactDuplicates {
            let groups = await ExactDuplicateInsightService.shared.exactDuplicateGroups(
                snapshot: snapshot,
                analysisBudget: 1_200
            )
            let exactIDs = groups.flatMap(\.assetIDs)
            var groupByID: [String: Int] = [:]
            var deletableIDs: Set<String> = []
            var keeperIDs: Set<String> = []
            for group in groups {
                keeperIDs.insert(group.keeperID)
                for id in group.assetIDs {
                    groupByID[id] = group.index
                    if id != group.keeperID {
                        deletableIDs.insert(id)
                    }
                }
            }
            exactDuplicateGroupByAssetID = groupByID
            exactDuplicateDeletableIDs = deletableIDs
            exactDuplicateKeeperIDs = keeperIDs
            assets = await Task.detached(priority: .userInitiated) {
                Self.fetchAssetsForIdentifiers(exactIDs, snapshot: snapshot)
            }.value
        } else if category == .receipts {
            exactDuplicateGroupByAssetID = [:]
            exactDuplicateDeletableIDs = []
            exactDuplicateKeeperIDs = []
            let receiptIDs = await ReceiptInsightService.shared.receiptAssetIDs(
                snapshot: snapshot,
                referenceDate: referenceDate,
                analysisBudget: 600
            )
            assets = await Task.detached(priority: .userInitiated) {
                Self.fetchAssetsForIdentifiers(receiptIDs, snapshot: snapshot)
            }.value
        } else if category == .chatMemeDump {
            exactDuplicateGroupByAssetID = [:]
            exactDuplicateDeletableIDs = []
            exactDuplicateKeeperIDs = []
            let chatMemeIDs = await ChatMemeInsightService.shared.chatMemeAssetIDs(
                snapshot: snapshot,
                referenceDate: referenceDate,
                analysisBudget: 700
            )
            assets = await Task.detached(priority: .userInitiated) {
                Self.fetchAssetsForIdentifiers(chatMemeIDs, snapshot: snapshot)
            }.value
        } else if category == .similarShots {
            exactDuplicateGroupByAssetID = [:]
            exactDuplicateDeletableIDs = []
            exactDuplicateKeeperIDs = []
            let similarIDs = await SimilarShotsInsightService.shared.similarShotsDeletableIDs(
                snapshot: snapshot,
                referenceDate: referenceDate
            )
            assets = await Task.detached(priority: .userInitiated) {
                Self.fetchAssetsForIdentifiers(similarIDs, snapshot: snapshot)
            }.value
        } else if category == .lowQuality {
            exactDuplicateGroupByAssetID = [:]
            exactDuplicateDeletableIDs = []
            exactDuplicateKeeperIDs = []
            let lowQualityIDs = await AestheticsInsightService.shared.lowQualityAssetIDs(
                snapshot: snapshot,
                referenceDate: referenceDate
            )
            assets = await Task.detached(priority: .userInitiated) {
                Self.fetchAssetsForIdentifiers(lowQualityIDs, snapshot: snapshot)
            }.value
        } else {
            exactDuplicateGroupByAssetID = [:]
            exactDuplicateDeletableIDs = []
            exactDuplicateKeeperIDs = []
            assets = await Task.detached(priority: .userInitiated) {
                Self.fetchAssetsForCategory(category, snapshot: snapshot, referenceDate: referenceDate)
            }.value
        }

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

    private nonisolated static func fetchAssetsForIdentifiers(
        _ identifiers: [String],
        snapshot: LibraryIndexSnapshot
    ) -> [YearAsset] {
        guard !identifiers.isEmpty else { return [] }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var phAssetByIdentifier: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            phAssetByIdentifier[asset.localIdentifier] = asset
        }

        let indexByIdentifier = Dictionary(
            uniqueKeysWithValues: snapshot.assets.map { ($0.id, $0) }
        )

        var results: [YearAsset] = []
        results.reserveCapacity(identifiers.count)

        for id in identifiers {
            guard let phAsset = phAssetByIdentifier[id] else { continue }

            let mediaType: MediaType
            switch phAsset.mediaType {
            case .video:
                mediaType = .video
            case .image:
                mediaType = phAsset.mediaSubtypes.contains(.photoLive) ? .livePhoto : .photo
            default:
                mediaType = .unknown
            }

            let creationDate = indexByIdentifier[id]?.creationDate ?? phAsset.creationDate ?? .distantPast
            results.append(
                YearAsset(
                    id: phAsset.localIdentifier,
                    creationDate: creationDate,
                    mediaType: mediaType,
                    duration: phAsset.duration
                )
            )
        }

        return results.sorted { $0.creationDate < $1.creationDate }
    }
}
