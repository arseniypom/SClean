//
//  MediaViewerView.swift
//  SClean
//
//  Full-screen paging viewer for photos and videos
//

import SwiftUI

struct MediaViewerView: View {
    let assets: [YearAsset]
    let startIndex: Int
    let year: Int
    
    @State private var currentIndex: Int
    @State private var prefetchTasks: [String: Task<Void, Never>] = [:]
    @Environment(\.dismiss) private var dismiss
    
    /// Number of items to prefetch in each direction
    private let prefetchRange = 2
    
    init(assets: [YearAsset], startIndex: Int, year: Int) {
        self.assets = assets
        self.startIndex = startIndex
        self.year = year
        self._currentIndex = State(initialValue: startIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if assets.isEmpty {
                emptyView
            } else {
                pagingContent
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                counterView
            }
        }
        .statusBarHidden(false)
        .onAppear {
            prefetchAdjacent()
        }
        .onChange(of: currentIndex) { _, _ in
            prefetchAdjacent()
        }
        .onDisappear {
            cancelAllPrefetch()
        }
    }
    
    // MARK: - Paging Content
    
    private var pagingContent: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                MediaPageView(
                    asset: asset,
                    isCurrentPage: index == currentIndex
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
    
    // MARK: - Counter View
    
    private var counterView: some View {
        Text("\(currentIndex + 1) / \(assets.count)")
            .font(Typography.subheadline)
            .foregroundStyle(.white.opacity(0.9))
            .monospacedDigit()
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            
            Text("No items to display")
                .font(Typography.body)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
    
    // MARK: - Prefetching
    
    private func prefetchAdjacent() {
        // Calculate range to prefetch
        let startPrefetch = max(0, currentIndex - prefetchRange)
        let endPrefetch = min(assets.count - 1, currentIndex + prefetchRange)
        
        // Prefetch assets in range (excluding videos - they load on demand)
        for index in startPrefetch...endPrefetch {
            let asset = assets[index]
            
            // Skip if already prefetching or if it's a video
            guard asset.mediaType != .video,
                  prefetchTasks[asset.id] == nil else {
                continue
            }
            
            // Start prefetch task
            prefetchTasks[asset.id] = Task {
                _ = await FullImageLoader.shared.loadFullImage(for: asset.id)
            }
        }
        
        // Cancel prefetch for assets outside range
        let prefetchIDs = Set((startPrefetch...endPrefetch).map { assets[$0].id })
        for (id, task) in prefetchTasks where !prefetchIDs.contains(id) {
            task.cancel()
            prefetchTasks.removeValue(forKey: id)
        }
    }
    
    private func cancelAllPrefetch() {
        for (_, task) in prefetchTasks {
            task.cancel()
        }
        prefetchTasks.removeAll()
    }
}

// MARK: - Preview

#Preview {
    let sampleAssets = [
        YearAsset(id: "1", creationDate: Date(), mediaType: .photo),
        YearAsset(id: "2", creationDate: Date(), mediaType: .video, duration: 30),
        YearAsset(id: "3", creationDate: Date(), mediaType: .photo),
    ]
    
    return NavigationStack {
        MediaViewerView(assets: sampleAssets, startIndex: 0, year: 2024)
    }
}

