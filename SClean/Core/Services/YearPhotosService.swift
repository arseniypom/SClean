//
//  YearPhotosService.swift
//  SClean
//
//  Fetches photos for a specific year
//

import Photos
import SwiftUI
import Combine

// MARK: - Media Type

nonisolated enum MediaType: Sendable, Equatable {
    case photo
    case video
    case livePhoto
    case unknown
}

// MARK: - Year Asset

/// Lightweight reference to a photo/video asset
nonisolated struct YearAsset: Identifiable, Equatable, Sendable {
    let id: String // PHAsset localIdentifier
    let creationDate: Date
    let mediaType: MediaType
    let duration: TimeInterval // For videos, 0 for photos
    
    init(id: String, creationDate: Date, mediaType: MediaType = .photo, duration: TimeInterval = 0) {
        self.id = id
        self.creationDate = creationDate
        self.mediaType = mediaType
        self.duration = duration
    }
    
    var isVideo: Bool {
        mediaType == .video
    }
}

// MARK: - Year Photos State

nonisolated enum YearPhotosState: Equatable, Sendable {
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

// MARK: - Year Photos Service

@MainActor
final class YearPhotosService: ObservableObject {
    
    let year: Int
    
    @Published private(set) var state: YearPhotosState = .idle
    
    init(year: Int) {
        self.year = year
    }
    
    // MARK: - Public Methods
    
    /// Fetches all photos for the given year, newest first
    func fetchPhotos() async {
        state = .loading
        
        let year = self.year
        let assets = await Task.detached(priority: .userInitiated) {
            Self.fetchAssetsForYear(year)
        }.value
        
        if assets.isEmpty {
            state = .empty
        } else {
            state = .loaded(assets)
        }
    }
    
    // MARK: - Private Methods
    
    private nonisolated static func fetchAssetsForYear(_ year: Int) -> [YearAsset] {
        // Create date range for the year
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1
        startComponents.hour = 0
        startComponents.minute = 0
        startComponents.second = 0
        
        var endComponents = DateComponents()
        endComponents.year = year + 1
        endComponents.month = 1
        endComponents.day = 1
        endComponents.hour = 0
        endComponents.minute = 0
        endComponents.second = 0
        
        let calendar = Calendar.current
        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(from: endComponents) else {
            return []
        }
        
        // Fetch options: filter by year, sort newest first
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            startDate as NSDate,
            endDate as NSDate
        )
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
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

