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
    
    private let indexStore: LibraryIndexStore
    private let indexer: LibraryIndexer
    private var changeObserverWrapper: ChangeObserverWrapper?
    
    init(
        indexStore: LibraryIndexStore = .shared,
        indexer: LibraryIndexer? = nil
    ) {
        self.indexStore = indexStore
        self.indexer = indexer ?? LibraryIndexer()
    }
    
    // MARK: - Public Methods
    
    /// Fetches all photos and buckets them by year
    func fetchYears() async {
        indexingProgress = 0
        
        // Load cached snapshot for instant UI when available
        let cachedSnapshot = indexStore.loadSnapshot()
        if let cachedSnapshot, !cachedSnapshot.yearBuckets.isEmpty {
            state = .loaded(cachedSnapshot.yearBuckets)
        } else {
            state = .loading
        }
        
        let (progressStream, continuation) = AsyncStream<Double>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        
        let computeTask = Task { () -> LibraryIndexSnapshot in
            defer { continuation.finish() }
            return await indexer.buildIndex(
                existingSnapshot: cachedSnapshot,
                onProgress: { processed, total in
                    guard total > 0 else { return }
                    continuation.yield(Double(processed) / Double(total))
                }
            )
        }
        
        for await progress in progressStream {
            indexingProgress = progress
        }
        
        let snapshot = await computeTask.value
        indexStore.saveSnapshot(snapshot)
        
        indexingProgress = nil
        
        let buckets = snapshot.yearBuckets
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
