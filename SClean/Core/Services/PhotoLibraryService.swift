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
    @Published private(set) var insightBuckets: [InsightBucket] = []

    /// Current snapshot for type-filtered asset lookups
    private(set) var currentSnapshot: LibraryIndexSnapshot?

    private let indexStore: LibraryIndexStore
    private let indexer: LibraryIndexer
    private var changeObserverWrapper: ChangeObserverWrapper?
    private var exactDuplicateInsightTask: Task<Void, Never>?
    private var receiptInsightTask: Task<Void, Never>?
    private var chatMemeInsightTask: Task<Void, Never>?
    
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
            insightBuckets = cachedSnapshot.insightBuckets.filter { $0.category != .exactDuplicates }
            currentSnapshot = cachedSnapshot
            startExactDuplicateInsightRefresh(for: cachedSnapshot, analysisBudget: 220)
            startReceiptInsightRefresh(for: cachedSnapshot, analysisBudget: 120)
            startChatMemeInsightRefresh(for: cachedSnapshot, analysisBudget: 140)
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
        insightBuckets = snapshot.insightBuckets.filter { $0.category != .exactDuplicates }
        startExactDuplicateInsightRefresh(for: snapshot, analysisBudget: 300)
        startReceiptInsightRefresh(for: snapshot, analysisBudget: 220)
        startChatMemeInsightRefresh(for: snapshot, analysisBudget: 250)

        let buckets = snapshot.yearBuckets
        if buckets.isEmpty {
            state = .empty
            monthBuckets = []
            typeBuckets = []
            insightBuckets = []
            currentSnapshot = nil
            exactDuplicateInsightTask?.cancel()
            exactDuplicateInsightTask = nil
            receiptInsightTask?.cancel()
            receiptInsightTask = nil
            chatMemeInsightTask?.cancel()
            chatMemeInsightTask = nil
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
        exactDuplicateInsightTask?.cancel()
        exactDuplicateInsightTask = nil
        receiptInsightTask?.cancel()
        receiptInsightTask = nil
        chatMemeInsightTask?.cancel()
        chatMemeInsightTask = nil
    }

    private func startExactDuplicateInsightRefresh(for snapshot: LibraryIndexSnapshot, analysisBudget: Int) {
        exactDuplicateInsightTask?.cancel()
        exactDuplicateInsightTask = Task { [weak self] in
            let exactBucket = await ExactDuplicateInsightService.shared.exactDuplicateBucket(
                snapshot: snapshot,
                analysisBudget: analysisBudget
            )
            guard !Task.isCancelled else { return }
            await self?.mergeAsyncInsightBucket(exactBucket, category: .exactDuplicates)
        }
    }

    private func startReceiptInsightRefresh(for snapshot: LibraryIndexSnapshot, analysisBudget: Int) {
        receiptInsightTask?.cancel()
        receiptInsightTask = Task { [weak self] in
            let receiptBucket = await ReceiptInsightService.shared.receiptBucket(
                snapshot: snapshot,
                analysisBudget: analysisBudget
            )
            guard !Task.isCancelled else { return }
            await self?.mergeAsyncInsightBucket(receiptBucket, category: .receipts)
        }
    }

    private func startChatMemeInsightRefresh(for snapshot: LibraryIndexSnapshot, analysisBudget: Int) {
        chatMemeInsightTask?.cancel()
        chatMemeInsightTask = Task { [weak self] in
            let chatMemeBucket = await ChatMemeInsightService.shared.chatMemeBucket(
                snapshot: snapshot,
                analysisBudget: analysisBudget
            )
            guard !Task.isCancelled else { return }
            await self?.mergeAsyncInsightBucket(chatMemeBucket, category: .chatMemeDump)
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
