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

    /// Current month buckets derived from the latest snapshot
    private(set) var monthBuckets: [MonthBucket] = []

    /// Current type buckets derived from the latest snapshot
    private(set) var typeBuckets: [TypeBucket] = []

    /// Current insight buckets derived from the latest snapshot.
    /// Published so async receipt analysis can refresh Home without full state reload.
    @Published private(set) var insightBuckets: [InsightBucket] = [] {
        didSet { recomputeReclaimableBytes() }
    }

    /// Categories whose background content analysis is still running
    @Published private(set) var analyzingInsightCategories: Set<InsightCategory> = []

    /// Whether any insight content analysis is still running
    var isAnalyzingInsights: Bool { !analyzingInsightCategories.isEmpty }

    /// De-duplicated total bytes across all insight candidates (an asset that
    /// appears in several categories is counted once)
    @Published private(set) var reclaimableBytes: Int64 = 0

    /// De-duplicated count of insight candidate assets
    @Published private(set) var reclaimableCount: Int = 0

    /// byteSize lookup for the current snapshot, rebuilt when it changes
    private var byteSizeByID: [String: Int64] = [:]

    /// Current snapshot for type-filtered asset lookups
    private(set) var currentSnapshot: LibraryIndexSnapshot?

    private let indexStore: LibraryIndexStore
    private let indexer: LibraryIndexer
    private var changeObserverWrapper: ChangeObserverWrapper?
    private var exactDuplicateInsightTask: Task<Void, Never>?
    private var receiptInsightTask: Task<Void, Never>?
    private var chatMemeInsightTask: Task<Void, Never>?
    private var similarShotsInsightTask: Task<Void, Never>?
    private var lowQualityInsightTask: Task<Void, Never>?

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
            monthBuckets = cachedSnapshot.monthBuckets
            typeBuckets = cachedSnapshot.typeBuckets
            rebuildByteSizeIndex(from: cachedSnapshot)
            insightBuckets = cachedSnapshot.insightBuckets.filter { $0.category != .exactDuplicates }
            currentSnapshot = cachedSnapshot
            startExactDuplicateInsightRefresh(for: cachedSnapshot)
            startReceiptInsightRefresh(for: cachedSnapshot)
            startChatMemeInsightRefresh(for: cachedSnapshot)
            startSimilarShotsInsightRefresh(for: cachedSnapshot)
            startLowQualityInsightRefresh(for: cachedSnapshot)
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
        currentSnapshot = snapshot
        monthBuckets = snapshot.monthBuckets
        typeBuckets = snapshot.typeBuckets
        rebuildByteSizeIndex(from: snapshot)
        insightBuckets = snapshot.insightBuckets.filter { $0.category != .exactDuplicates }
        startExactDuplicateInsightRefresh(for: snapshot)
        startReceiptInsightRefresh(for: snapshot)
        startChatMemeInsightRefresh(for: snapshot)
        startSimilarShotsInsightRefresh(for: snapshot)
        startLowQualityInsightRefresh(for: snapshot)

        let buckets = snapshot.yearBuckets
        if buckets.isEmpty {
            state = .empty
            monthBuckets = []
            typeBuckets = []
            rebuildByteSizeIndex(from: nil)
            insightBuckets = []
            currentSnapshot = nil
            cancelInsightTasks()
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
        cancelInsightTasks()
    }

    private func cancelInsightTasks() {
        exactDuplicateInsightTask?.cancel()
        exactDuplicateInsightTask = nil
        receiptInsightTask?.cancel()
        receiptInsightTask = nil
        chatMemeInsightTask?.cancel()
        chatMemeInsightTask = nil
        similarShotsInsightTask?.cancel()
        similarShotsInsightTask = nil
        lowQualityInsightTask?.cancel()
        lowQualityInsightTask = nil
        // Cancelled tasks skip their endAnalyzing — clear the flags here
        analyzingInsightCategories.removeAll()
    }

    // Progressive insight refreshes run at a low QoS and scan the *entire* candidate set,
    // not just a budget slice, emitting partial buckets as they go so the count grows live.
    // Persisted per-asset caches make every launch after the first nearly free.

    private func startExactDuplicateInsightRefresh(for snapshot: LibraryIndexSnapshot) {
        exactDuplicateInsightTask?.cancel()
        beginAnalyzing(.exactDuplicates)
        exactDuplicateInsightTask = Task(priority: .utility) { [weak self] in
            await ExactDuplicateInsightService.shared.exactDuplicateBucketProgressive(
                snapshot: snapshot
            ) { bucket in
                guard !Task.isCancelled else { return } // superseded by a newer refresh
                await self?.mergeAsyncInsightBucket(bucket, category: .exactDuplicates)
            }
            guard !Task.isCancelled else { return } // a newer refresh owns the flag
            await self?.endAnalyzing(.exactDuplicates)
        }
    }

    private func startReceiptInsightRefresh(for snapshot: LibraryIndexSnapshot) {
        receiptInsightTask?.cancel()
        beginAnalyzing(.receipts)
        receiptInsightTask = Task(priority: .utility) { [weak self] in
            await ReceiptInsightService.shared.receiptBucketProgressive(
                snapshot: snapshot
            ) { bucket in
                guard !Task.isCancelled else { return } // superseded by a newer refresh
                await self?.mergeAsyncInsightBucket(bucket, category: .receipts)
            }
            guard !Task.isCancelled else { return } // a newer refresh owns the flag
            await self?.endAnalyzing(.receipts)
        }
    }

    private func startChatMemeInsightRefresh(for snapshot: LibraryIndexSnapshot) {
        chatMemeInsightTask?.cancel()
        beginAnalyzing(.chatMemeDump)
        chatMemeInsightTask = Task(priority: .utility) { [weak self] in
            await ChatMemeInsightService.shared.chatMemeBucketProgressive(
                snapshot: snapshot
            ) { bucket in
                guard !Task.isCancelled else { return } // superseded by a newer refresh
                await self?.mergeAsyncInsightBucket(bucket, category: .chatMemeDump)
            }
            guard !Task.isCancelled else { return } // a newer refresh owns the flag
            await self?.endAnalyzing(.chatMemeDump)
        }
    }

    private func startSimilarShotsInsightRefresh(for snapshot: LibraryIndexSnapshot) {
        similarShotsInsightTask?.cancel()
        beginAnalyzing(.similarShots)
        similarShotsInsightTask = Task(priority: .utility) { [weak self] in
            await SimilarShotsInsightService.shared.similarShotsBucketProgressive(
                snapshot: snapshot
            ) { bucket in
                guard !Task.isCancelled else { return } // superseded by a newer refresh
                await self?.mergeAsyncInsightBucket(bucket, category: .similarShots)
            }
            guard !Task.isCancelled else { return } // a newer refresh owns the flag
            await self?.endAnalyzing(.similarShots)
        }
    }

    private func startLowQualityInsightRefresh(for snapshot: LibraryIndexSnapshot) {
        lowQualityInsightTask?.cancel()
        beginAnalyzing(.lowQuality)
        lowQualityInsightTask = Task(priority: .utility) { [weak self] in
            await AestheticsInsightService.shared.lowQualityBucketProgressive(
                snapshot: snapshot
            ) { bucket in
                guard !Task.isCancelled else { return } // superseded by a newer refresh
                await self?.mergeAsyncInsightBucket(bucket, category: .lowQuality)
            }
            guard !Task.isCancelled else { return } // a newer refresh owns the flag
            await self?.endAnalyzing(.lowQuality)
        }
    }

    @MainActor
    private func mergeAsyncInsightBucket(_ bucket: InsightBucket?, category: InsightCategory) {
        insightBuckets.removeAll { $0.category == category }
        if let bucket {
            insightBuckets.append(bucket)
        }
        insightBuckets.sort { lhs, rhs in
            if lhs.totalBytes == rhs.totalBytes {
                return lhs.count > rhs.count
            }
            return lhs.totalBytes > rhs.totalBytes
        }
    }

    // MARK: - Analysis Progress & Reclaimable Total

    @MainActor
    private func beginAnalyzing(_ category: InsightCategory) {
        analyzingInsightCategories.insert(category)
    }

    @MainActor
    private func endAnalyzing(_ category: InsightCategory) {
        analyzingInsightCategories.remove(category)
    }

    private func rebuildByteSizeIndex(from snapshot: LibraryIndexSnapshot?) {
        guard let snapshot else {
            byteSizeByID = [:]
            return
        }
        var index: [String: Int64] = [:]
        index.reserveCapacity(snapshot.assets.count)
        for asset in snapshot.assets {
            index[asset.id] = asset.byteSize
        }
        byteSizeByID = index
    }

    private func recomputeReclaimableBytes() {
        var uniqueIDs: Set<String> = []
        for bucket in insightBuckets {
            uniqueIDs.formUnion(bucket.assetIDs)
        }
        reclaimableBytes = uniqueIDs.reduce(Int64(0)) { $0 + (byteSizeByID[$1] ?? 0) }
        reclaimableCount = uniqueIDs.count
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
