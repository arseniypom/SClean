//
//  PhotoLibraryService.swift
//  SlideClean
//
//  Fetches and organizes photos from the library
//

import Photos
import SwiftUI
import Combine

// MARK: - Year Bucket

/// Explicitly nonisolated to allow creation from background threads
nonisolated struct YearBucket: Identifiable, Equatable, Sendable {
    let id: Int // year as ID
    let year: Int
    let count: Int
    
    init(year: Int, count: Int) {
        self.id = year
        self.year = year
        self.count = count
    }
}

// MARK: - Library State

nonisolated enum LibraryState: Equatable, Sendable {
    case idle
    case loading
    case loaded([YearBucket])
    case empty
    case error(String)
    
    var years: [YearBucket] {
        if case .loaded(let buckets) = self {
            return buckets
        }
        return []
    }
    
    var isLoading: Bool {
        self == .loading
    }
}

// MARK: - Photo Library Service

@MainActor
final class PhotoLibraryService: ObservableObject {
    
    @Published private(set) var state: LibraryState = .idle
    
    private var changeObserverWrapper: ChangeObserverWrapper?
    
    init() {}
    
    // MARK: - Public Methods
    
    /// Fetches all photos and buckets them by year
    func fetchYears() async {
        state = .loading
        
        // Run the heavy work off main thread
        let buckets = await Task.detached(priority: .userInitiated) {
            Self.computeYearBuckets()
        }.value
        
        if buckets.isEmpty {
            state = .empty
        } else {
            state = .loaded(buckets)
        }
    }
    
    /// Refreshes the years list
    func refresh() async {
        await fetchYears()
    }
    
    // MARK: - Private Methods
    
    private nonisolated static func computeYearBuckets() -> [YearBucket] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        fetchOptions.includeAllBurstAssets = false
        
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        
        // Count items per year
        var yearCounts: [Int: Int] = [:]
        
        assets.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let year = Calendar.current.component(.year, from: date)
            yearCounts[year, default: 0] += 1
        }
        
        // Convert to buckets, sorted newest first
        let buckets = yearCounts
            .map { YearBucket(year: $0.key, count: $0.value) }
            .sorted { $0.year > $1.year }
        
        return buckets
    }
    
    // MARK: - Change Observer
    
    func startObservingChanges() {
        guard changeObserverWrapper == nil else { return }
        changeObserverWrapper = ChangeObserverWrapper { [weak self] in
            Task { @MainActor in
                if case .loaded = self?.state {
                    await self?.refresh()
                }
            }
        }
    }
    
    func stopObservingChanges() {
        changeObserverWrapper = nil
    }
}

// MARK: - Change Observer Wrapper (NSObject required for PHPhotoLibraryChangeObserver)

/// Nonisolated because PHPhotoLibraryChangeObserver callbacks come from background threads
private nonisolated final class ChangeObserverWrapper: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    private let onChange: @Sendable () -> Void
    
    override nonisolated init() {
        self.onChange = {}
        super.init()
    }
    
    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}
