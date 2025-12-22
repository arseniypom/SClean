//
//  TrashViewerView.swift
//  SClean
//
//  Full-screen viewer for trashed items with restore action
//

import SwiftUI

struct TrashViewerView: View {
    let trashedItems: [TrashedItem]
    let startIndex: Int
    
    @StateObject private var trashService = TrashService.shared
    @State private var currentIndex: Int
    @State private var prefetchTasks: [String: Task<Void, Never>] = [:]
    @Environment(\.dismiss) private var dismiss
    
    /// Number of items to prefetch in each direction
    private let prefetchRange = 2
    
    /// Filtered items that are still in trash
    private var visibleItems: [TrashedItem] {
        trashedItems.filter { trashService.isTrashed($0.assetID) }
    }
    
    /// Current visible index
    private var currentVisibleIndex: Int {
        guard currentIndex < trashedItems.count else { return 0 }
        let currentItem = trashedItems[currentIndex]
        return visibleItems.firstIndex(where: { $0.assetID == currentItem.assetID }) ?? 0
    }
    
    init(trashedItems: [TrashedItem], startIndex: Int) {
        self.trashedItems = trashedItems
        self.startIndex = startIndex
        self._currentIndex = State(initialValue: startIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if visibleItems.isEmpty {
                allRestoredView
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
            
            // Restore button
            ToolbarItem(placement: .topBarTrailing) {
                if !visibleItems.isEmpty {
                    Button {
                        restoreCurrentItem()
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 14, weight: .medium))
                            Text("Restore")
                                .font(Typography.subheadline)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
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
    }
    
    // MARK: - Paging Content
    
    private var pagingContent: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(trashedItems.enumerated()), id: \.element.assetID) { index, item in
                if trashService.isTrashed(item.assetID) {
                    TrashMediaPageView(assetID: item.assetID, isCurrentPage: index == currentIndex)
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
            if visibleItems.isEmpty {
                Text("Done")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text("\(currentVisibleIndex + 1) / \(visibleItems.count)")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
            }
        }
    }
    
    // MARK: - All Restored View
    
    private var allRestoredView: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.scSuccess.opacity(0.15))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color.scSuccess)
            }
            
            VStack(spacing: Spacing.xs) {
                Text("All Restored")
                    .font(Typography.title2)
                    .foregroundStyle(.white)
                
                Text("All items have been restored")
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            
            Button {
                dismiss()
            } label: {
                Text("Back to Trash")
                    .font(Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            }
            .padding(.horizontal, Spacing.xxl)
        }
        .padding(Spacing.xl)
    }
    
    // MARK: - Actions
    
    private func restoreCurrentItem() {
        guard currentIndex < trashedItems.count else { return }
        
        let item = trashedItems[currentIndex]
        
        // Light haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // Restore the item
        trashService.restore(item.assetID)
        
        // Advance to next visible item
        advanceToNextVisible(from: currentIndex)
    }
    
    private func advanceToNextVisible(from restoredIndex: Int) {
        // Find next item still in trash
        for i in (restoredIndex + 1)..<trashedItems.count {
            if trashService.isTrashed(trashedItems[i].assetID) {
                withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                    currentIndex = i
                }
                return
            }
        }
        
        // If no next, try previous
        for i in stride(from: restoredIndex - 1, through: 0, by: -1) {
            if trashService.isTrashed(trashedItems[i].assetID) {
                withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                    currentIndex = i
                }
                return
            }
        }
        
        // All items restored - visibleItems will be empty
    }
    
    // MARK: - Prefetching
    
    private func prefetchAdjacent() {
        guard !trashedItems.isEmpty else { return }
        
        let startPrefetch = max(0, currentIndex - prefetchRange)
        let endPrefetch = min(trashedItems.count - 1, currentIndex + prefetchRange)
        
        guard startPrefetch <= endPrefetch else { return }
        
        for index in startPrefetch...endPrefetch {
            let item = trashedItems[index]
            
            guard trashService.isTrashed(item.assetID),
                  prefetchTasks[item.assetID] == nil else {
                continue
            }
            
            prefetchTasks[item.assetID] = Task {
                _ = await FullImageLoader.shared.loadFullImage(for: item.assetID)
            }
        }
        
        // Cancel prefetch for items outside range
        let prefetchIDs = Set((startPrefetch...endPrefetch).map { trashedItems[$0].assetID })
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

// MARK: - Trash Media Page View

/// Displays a single trashed media item (photo/video)
struct TrashMediaPageView: View {
    let assetID: String
    let isCurrentPage: Bool
    
    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            if isCurrentPage {
                loadFullImage()
            }
        }
        .onChange(of: isCurrentPage) { _, isCurrent in
            if isCurrent && image == nil {
                loadFullImage()
            }
        }
        .onDisappear {
            cancelLoad()
        }
    }
    
    private func loadFullImage() {
        guard image == nil else { return }
        
        loadTask = Task {
            let loaded = await FullImageLoader.shared.loadFullImage(for: assetID)
            if !Task.isCancelled {
                withAnimation(.easeIn(duration: AnimationDuration.fast)) {
                    image = loaded
                }
            }
        }
    }
    
    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }
}

// MARK: - Preview

#Preview {
    let items = [
        TrashedItem(assetID: "1"),
        TrashedItem(assetID: "2"),
        TrashedItem(assetID: "3"),
    ]
    
    return NavigationStack {
        TrashViewerView(trashedItems: items, startIndex: 0)
    }
}



