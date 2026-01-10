//
//  MonthPhotosService.swift
//  SClean
//
//  Fetches photos for a specific month
//

import Photos
import SwiftUI
import Combine

// MARK: - Month Photos State

nonisolated enum MonthPhotosState: Equatable, Sendable {
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

// MARK: - Month Photos Service

@MainActor
final class MonthPhotosService: ObservableObject {

    let year: Int
    let month: Int

    @Published private(set) var state: MonthPhotosState = .idle
    @Published var sortOrder: SortOrder = .newestFirst

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    // MARK: - Public Methods

    /// Fetches all photos for the given month
    func fetchPhotos() async {
        state = .loading

        let year = self.year
        let month = self.month
        let ascending = sortOrder.isAscending
        let assets = await Task.detached(priority: .userInitiated) {
            Self.fetchAssetsForMonth(year: year, month: month, ascending: ascending)
        }.value

        if assets.isEmpty {
            state = .empty
        } else {
            state = .loaded(assets)
        }
    }

    // MARK: - Private Methods

    private nonisolated static func fetchAssetsForMonth(year: Int, month: Int, ascending: Bool) -> [YearAsset] {
        // Create date range for the month
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = month
        startComponents.day = 1
        startComponents.hour = 0
        startComponents.minute = 0
        startComponents.second = 0

        var endComponents = DateComponents()
        endComponents.year = month == 12 ? year + 1 : year
        endComponents.month = month == 12 ? 1 : month + 1
        endComponents.day = 1
        endComponents.hour = 0
        endComponents.minute = 0
        endComponents.second = 0

        let calendar = Calendar.current
        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(from: endComponents) else {
            return []
        }

        // Fetch options: filter by month date range
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            startDate as NSDate,
            endDate as NSDate
        )
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: ascending)
        ]
        fetchOptions.includeHiddenAssets = false
        fetchOptions.includeAllBurstAssets = false

        let results = PHAsset.fetchAssets(with: fetchOptions)

        var assets: [YearAsset] = []
        assets.reserveCapacity(results.count)

        results.enumerateObjects { phAsset, _, _ in
            let mediaType: MediaType
            switch phAsset.mediaType {
            case .video:
                mediaType = .video
            case .image:
                // Check for Live Photo
                if (phAsset.mediaSubtypes.contains(.photoLive)) {
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
            assets.append(asset)
        }

        return assets
    }
}
