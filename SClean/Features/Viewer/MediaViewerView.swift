//
//  MediaViewerView.swift
//  SClean
//
//  Full-screen paging viewer for photos and videos with swipe-to-trash
//

import SwiftUI

struct MediaViewerView: View {
    let assets: [YearAsset]
    let startIndex: Int
    let year: Int
    
    @StateObject private var trashService = TrashService.shared
    @State private var currentIndex: Int
    @State private var prefetchTasks: [String: Task<Void, Never>] = [:]
    @State private var toast: ToastData?
    @State private var hasSeenHint: Bool
    @Environment(\.dismiss) private var dismiss
    
    /// Number of items to prefetch in each direction
    private let prefetchRange = 2
    
    /// Assets that haven't been trashed
    private var visibleAssets: [YearAsset] {
        assets.filter { !trashService.isTrashed($0.id) }
    }
    
    /// Current visible index (accounting for trashed items)
    private var currentVisibleIndex: Int {
        // Find the position of current asset in visible list
        guard currentIndex < assets.count else { return 0 }
        let currentAsset = assets[currentIndex]
        return visibleAssets.firstIndex(where: { $0.id == currentAsset.id }) ?? 0
    }
    
    init(assets: [YearAsset], startIndex: Int, year: Int) {
        self.assets = assets
        self.startIndex = startIndex
        self.year = year
        self._currentIndex = State(initialValue: startIndex)
        self._hasSeenHint = State(initialValue: UserDefaults.standard.bool(forKey: "SClean.hasSeenTrashHint"))
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if visibleAssets.isEmpty {
                doneView
            } else {
                pagingContent
            }
            
            // First-time hint overlay
            if !hasSeenHint && !visibleAssets.isEmpty {
                firstTimeHint
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                counterView
            }
            
            // Trash button (accessibility fallback)
            ToolbarItem(placement: .topBarTrailing) {
                if !visibleAssets.isEmpty {
                    Button {
                        trashCurrentItem()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
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
        .undoToast($toast)
    }
    
    // MARK: - Paging Content
    
    private var pagingContent: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                if !trashService.isTrashed(asset.id) {
                    MediaPageView(
                        asset: asset,
                        isCurrentPage: index == currentIndex
                    )
                    .swipeToTrash(isEnabled: true) {
                        trashItem(at: index)
                    }
                    .tag(index)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
    
    // MARK: - Counter View
    
    private var counterView: some View {
        Group {
            if visibleAssets.isEmpty {
                Text("Done")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text("\(currentVisibleIndex + 1) / \(visibleAssets.count)")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
            }
        }
    }
    
    // MARK: - Done View
    
    private var doneView: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.scSuccess.opacity(0.15))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color.scSuccess)
            }
            
            VStack(spacing: Spacing.xs) {
                Text("All Done!")
                    .font(Typography.title2)
                    .foregroundStyle(.white)
                
                Text("You've reviewed all items in \(year)")
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: Spacing.sm) {
                Button {
                    dismiss()
                } label: {
                    Text("Back to Grid")
                        .font(Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                }
                
                if trashService.trashCount > 0 {
                    Text("\(trashService.trashCount) items in Trash")
                        .font(Typography.caption1)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, Spacing.xxl)
        }
        .padding(Spacing.xl)
    }
    
    // MARK: - First Time Hint
    
    private var firstTimeHint: some View {
        VStack {
            Spacer()
            
            VStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                
                Text("Swipe down to move to Trash")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white)
                
                Text("Nothing is deleted until you empty Trash")
                    .font(Typography.caption1)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(Spacing.lg)
            .background(.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .padding(.bottom, Spacing.xxl * 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.3))
        .onTapGesture {
            dismissHint()
        }
    }
    
    private func dismissHint() {
        withAnimation(.easeOut(duration: AnimationDuration.fast)) {
            hasSeenHint = true
        }
        UserDefaults.standard.set(true, forKey: "SClean.hasSeenTrashHint")
    }
    
    // MARK: - Trash Actions
    
    private func trashCurrentItem() {
        trashItem(at: currentIndex)
    }
    
    private func trashItem(at index: Int) {
        guard index < assets.count else { return }
        
        let asset = assets[index]
        let assetID = asset.id
        
        // Dismiss hint on first trash
        if !hasSeenHint {
            dismissHint()
        }
        
        // Trash the item
        trashService.trash(assetID)
        
        // Show undo toast
        toast = ToastData(message: "Moved to Trash") {
            trashService.restore(assetID)
        }
        
        // Auto-advance to next visible item
        advanceToNextVisible(from: index)
    }
    
    private func advanceToNextVisible(from trashedIndex: Int) {
        // Find next non-trashed item after the trashed one
        for i in (trashedIndex + 1)..<assets.count {
            if !trashService.isTrashed(assets[i].id) {
                withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                    currentIndex = i
                }
                return
            }
        }
        
        // If no next, try previous
        for i in stride(from: trashedIndex - 1, through: 0, by: -1) {
            if !trashService.isTrashed(assets[i].id) {
                withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                    currentIndex = i
                }
                return
            }
        }
        
        // All items trashed - visibleAssets will be empty and doneView will show
    }
    
    // MARK: - Prefetching
    
    private func prefetchAdjacent() {
        guard !assets.isEmpty else { return }
        
        // Calculate range to prefetch
        let startPrefetch = max(0, currentIndex - prefetchRange)
        let endPrefetch = min(assets.count - 1, currentIndex + prefetchRange)
        
        guard startPrefetch <= endPrefetch else { return }
        
        // Prefetch assets in range (excluding videos and trashed)
        for index in startPrefetch...endPrefetch {
            let asset = assets[index]
            
            // Skip if trashed, already prefetching, or video
            guard !trashService.isTrashed(asset.id),
                  asset.mediaType != .video,
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
