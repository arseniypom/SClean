//
//  PhotoLibraryService.swift
//  SClean
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
    let totalBytes: Int64
    
    init(year: Int, count: Int, totalBytes: Int64 = 0) {
        self.id = year
        self.year = year
        self.count = count
        self.totalBytes = totalBytes
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
    @Published private(set) var indexingProgress: Double? = nil
    
    private var changeObserverWrapper: ChangeObserverWrapper?
    
    init() {}
    
    // MARK: - Public Methods
    
    /// Fetches all photos and buckets them by year
    func fetchYears() async {
        state = .loading
        indexingProgress = 0
        
        let (progressStream, continuation) = AsyncStream<Double>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        
        let computeTask = Task.detached(priority: .userInitiated) { () -> [YearBucket] in
            defer { continuation.finish() }
            return Self.computeYearBuckets(onProgress: { processed, total in
                guard total > 0 else { return }
                continuation.yield(Double(processed) / Double(total))
            })
        }
        
        // Consume progress on MainActor without capturing self in the detached task.
        for await progress in progressStream {
            indexingProgress = progress
        }
        
        let buckets = await computeTask.value
        indexingProgress = nil
        
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
    
    private nonisolated static func computeYearBuckets(
        onProgress: (@Sendable (_ processed: Int, _ total: Int) -> Void)? = nil
    ) -> [YearBucket] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        fetchOptions.includeAllBurstAssets = false
        
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        
        let total = assets.count
        let step = max(250, total / 200) // ~<=200 updates, capped for perf
        
        // Count items and size per year
        var yearData: [Int: (count: Int, bytes: Int64)] = [:]
        var processed = 0
        
        assets.enumerateObjects { asset, _, stop in
            if Task.isCancelled {
                stop.pointee = true
                return
            }
            
            defer {
                processed += 1
                if let onProgress, total > 0 {
                    if processed == 1 || processed == total || (processed % step) == 0 {
                        onProgress(processed, total)
                    }
                }
            }
            
            guard let date = asset.creationDate else { return }
            let year = Calendar.current.component(.year, from: date)
            
            // Get estimated file size from asset resources
            let resources = PHAssetResource.assetResources(for: asset)
            let totalSize = resources.reduce(Int64(0)) { sum, resource in
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    return sum + size
                }
                return sum
            }
            
            let current = yearData[year, default: (0, 0)]
            yearData[year] = (current.count + 1, current.bytes + totalSize)
        }
        
        // Convert to buckets, sorted newest first
        return yearData
            .map { YearBucket(year: $0.key, count: $0.value.count, totalBytes: $0.value.bytes) }
            .sorted { $0.year > $1.year }
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


