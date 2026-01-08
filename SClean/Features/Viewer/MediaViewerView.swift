//
//  MediaViewerView.swift
//  SClean
//
//  Full-screen paging viewer for photos and videos with swipe-to-trash
//

import SwiftUI
import Photos

// MARK: - Trash Icon Position Key

private struct TrashIconPositionKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

struct MediaViewerView: View {
    let assets: [YearAsset]
    let startIndex: Int
    let year: Int
    @ObservedObject var permissionService: PhotoPermissionService
    
    @StateObject private var trashService = TrashService.shared
    @State private var currentIndex: Int
    @State private var prefetchTasks: [String: Task<Void, Never>] = [:]
    @State private var toast: ToastData?
    @State private var hasSeenBrowseHint: Bool
    @State private var hasSeenTrashHint: Bool
    @State private var swipeCount: Int = 0
    @State private var showTrashTip: Bool = false
    @State private var currentAssetSize: Int64?
    @State private var isTrashAnimating = false
    @State private var trashIconPosition: CGPoint = .zero
    @Environment(\.dismiss) private var dismiss
    
    /// Number of items to prefetch in each direction
    private let prefetchRange = 2
    
    /// Current asset for the active page
    private var currentAsset: YearAsset? {
        guard currentIndex < assets.count else { return nil }
        return assets[currentIndex]
    }
    
    /// Assets that haven't been trashed
    private var visibleAssets: [YearAsset] {
        assets.filter { !trashService.isTrashed($0.id) }
    }
    
    /// Current visible index (accounting for trashed items)
    private var currentVisibleIndex: Int {
        // Find the position of current asset in visible list
        guard let currentAsset else { return 0 }
        return visibleAssets.firstIndex(where: { $0.id == currentAsset.id }) ?? 0
    }
    
    /// Whether the active page is already in the in-app trash
    private var isCurrentAssetTrashed: Bool {
        guard let currentAsset else { return false }
        return trashService.isTrashed(currentAsset.id)
    }
    
    init(assets: [YearAsset], startIndex: Int, year: Int, permissionService: PhotoPermissionService) {
        self.assets = assets
        self.startIndex = startIndex
        self.year = year
        self.permissionService = permissionService
        self._currentIndex = State(initialValue: startIndex)
        // Migrate hint flags from old keys if needed
        let browseSeen = UserDefaults.standard.bool(forKey: "SlideClean.hasSeenBrowseHint") ||
            UserDefaults.standard.bool(forKey: "SClean.hasSeenBrowseHint")
        let trashSeen = UserDefaults.standard.bool(forKey: "SlideClean.hasSeenTrashHint") ||
            UserDefaults.standard.bool(forKey: "SClean.hasSeenTrashHint")
        self._hasSeenBrowseHint = State(initialValue: browseSeen)
        self._hasSeenTrashHint = State(initialValue: trashSeen)
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
            
            // First-time browse hint
            if !hasSeenBrowseHint && !visibleAssets.isEmpty {
                browseHint
            }

            // One-time trash tip after some browsing
            if showTrashTip && !visibleAssets.isEmpty {
                trashTip
            }

            // Access changed overlay
            if !permissionService.status.canAccessPhotos {
                accessChangedOverlay
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                counterView
            }
            
            // Trash icon - opens trash screen
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TrashViewWithNavigation(permissionService: permissionService)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))

                        // Badge
                        if trashService.trashCount > 0 {
                            Text("\(trashService.trashCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .offset(x: 8, y: -6)
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: TrashIconPositionKey.self,
                                value: CGPoint(
                                    x: geo.frame(in: .global).midX,
                                    y: geo.frame(in: .global).midY
                                )
                            )
                        }
                    )
                }
                .accessibilityLabel("Trash (\(trashService.trashCount) items)")
            }
        }
        .onPreferenceChange(TrashIconPositionKey.self) { position in
            trashIconPosition = position
        }
        .statusBarHidden(false)
        .onAppear {
            prefetchAdjacent()
            fetchCurrentAssetSize()
        }
        .onChange(of: currentIndex) { _, _ in
            prefetchAdjacent()
            fetchCurrentAssetSize()
            // Count browsing swipes
            swipeCount += 1
            if !hasSeenTrashHint && !showTrashTip && swipeCount >= 8 {
                withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                    showTrashTip = true
                }
            }
        }
        .onDisappear {
            cancelAllPrefetch()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            permissionService.refreshStatus()
        }
        .undoToast($toast)
    }
    
    // MARK: - Paging Content
    
    private var pagingContent: some View {
        ZStack {
            // Next photo preview (shown during trash animation - appears behind)
            if isTrashAnimating, let nextIndex = nextVisibleIndex(from: currentIndex) {
                MediaPageView(
                    asset: assets[nextIndex],
                    isCurrentPage: false,
                    isTrashed: false
                ) { }
            }

            // Main TabView (on top)
            TabView(selection: $currentIndex) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    pageView(for: index, asset: asset)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { location in
            handleEdgeTap(at: location)
        }
    }

    private func pageView(for index: Int, asset: YearAsset) -> some View {
        let isTrashed = trashService.isTrashed(asset.id)

        return MediaPageView(
            asset: asset,
            isCurrentPage: index == currentIndex,
            isTrashed: isTrashed
        ) {
            trashService.restore(asset.id)
        }
        .swipeToTrash(
            isEnabled: !isTrashed,
            targetPosition: trashIconPosition,
            onAnimationStart: { isTrashAnimating = true }
        ) {
            trashItem(at: index)
        }
    }
    
    // MARK: - Counter View

    private var counterView: some View {
        VStack(spacing: 2) {
            if visibleAssets.isEmpty {
                Text("Done")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            } else if isCurrentAssetTrashed {
                Text("Marked for deletion")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text("\(currentVisibleIndex + 1) / \(visibleAssets.count)")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()

                // Metadata line: date and size
                if let asset = currentAsset {
                    metadataText(for: asset)
                }
            }
        }
    }

    private func metadataText(for asset: YearAsset) -> some View {
        let dateText = formattedDate(asset.creationDate)
        let sizeText = currentAssetSize.map { formattedSize($0) }

        return Group {
            if let sizeText {
                Text("\(dateText) · \(sizeText)")
            } else {
                Text(dateText)
            }
        }
        .font(Typography.caption2)
        .foregroundStyle(.white.opacity(0.6))
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        let gb = Double(bytes) / 1_073_741_824

        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 0.1 {
            return String(format: "%.1f MB", mb)
        } else {
            return "< 0.1 MB"
        }
    }

    private func fetchCurrentAssetSize() {
        currentAssetSize = nil
        guard let asset = currentAsset else { return }

        Task.detached(priority: .userInitiated) {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil)
            guard let phAsset = fetchResult.firstObject else { return }

            let resources = PHAssetResource.assetResources(for: phAsset)
            let totalSize = resources.reduce(Int64(0)) { sum, resource in
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    return sum + size
                }
                return sum
            }

            await MainActor.run {
                // Only update if still on the same asset
                if self.currentAsset?.id == asset.id {
                    self.currentAssetSize = totalSize > 0 ? totalSize : nil
                }
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
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
                }
                
                // Go to Trash button
                if trashService.trashCount > 0 {
                    NavigationLink {
                        TrashViewWithNavigation(permissionService: permissionService)
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))
                            Text("Go to Trash (\(trashService.trashCount))")
                                .font(Typography.headline)
                        }
                        .foregroundStyle(Color.scTextPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.scSurfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, Spacing.xxl)
        }
        .padding(Spacing.xl)
    }
    
    // MARK: - First Time Hint
    
    private var browseHint: some View {
        VStack {
            Spacer()
            
            VStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)

                Text("Swipe left/right to browse")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white)
                Text("Swipe up to move to Trash")
                    .font(Typography.caption1)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(Spacing.lg)
            .background(.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .padding(.bottom, Spacing.xxl * 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.3))
        .onTapGesture {
            dismissBrowseHint()
        }
        .onAppear {
            // Auto-fade after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                dismissBrowseHint()
            }
        }
    }

    private var trashTip: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()
                
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Tip: Swipe up to move to Trash")
                        .font(Typography.caption1)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(Spacing.md)
                .background(.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                .padding(.trailing, Spacing.lg)
            }
            .padding(.bottom, Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.001)) // tap-through safe background
        .onTapGesture {
            dismissTrashTip()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                dismissTrashTip()
            }
        }
    }

    private func dismissBrowseHint() {
        guard !hasSeenBrowseHint else { return }
        withAnimation(.easeOut(duration: AnimationDuration.fast)) {
            hasSeenBrowseHint = true
        }
        UserDefaults.standard.set(true, forKey: "SlideClean.hasSeenBrowseHint")
    }

    private func dismissTrashTip() {
        if showTrashTip {
            withAnimation(.easeOut(duration: AnimationDuration.fast)) {
                showTrashTip = false
            }
        }
        if !hasSeenTrashHint {
            hasSeenTrashHint = true
            UserDefaults.standard.set(true, forKey: "SlideClean.hasSeenTrashHint")
        }
    }

    // MARK: - Access Changed Overlay
    private var accessChangedOverlay: some View {
        VStack {
            Spacer()
            
            VStack(spacing: Spacing.sm) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                Text("Access changed")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white)
                Text("Photo access was changed. Re-enable in Settings.")
                    .font(Typography.caption1)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(Spacing.lg)
            .background(.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .padding(.bottom, Spacing.xxl * 2)

            SCButton("Open Settings", icon: "gear", style: .secondary) {
                permissionService.openSettings()
            }
            .padding(.bottom, Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.4))
        .ignoresSafeArea()
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
        if !hasSeenTrashHint {
            dismissTrashTip()
        }
        
        // Trash the item
        trashService.trash(assetID)
        
        // Show undo toast
        toast = ToastData(message: "Moved to Trash (not deleted)") {
            trashService.restore(assetID)
        }

        // Auto-advance to next visible item (slight delay for animation sequencing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.advanceToNextVisible(from: index)
        }
    }
    
    private func advanceToNextVisible(from trashedIndex: Int) {
        guard let nextIndex = nextVisibleIndex(from: trashedIndex) else {
            // All items trashed - visibleAssets will be empty and doneView will show
            isTrashAnimating = false
            return
        }

        // Use transaction to disable TabView's slide animation
        // (next photo is already visible behind via stack preview)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            currentIndex = nextIndex
        }

        // Reset preview flag
        isTrashAnimating = false
    }

    private func nextVisibleIndex(from index: Int) -> Int? {
        // Try forward first
        for i in (index + 1)..<assets.count {
            if !trashService.isTrashed(assets[i].id) {
                return i
            }
        }
        // Then try backward
        for i in stride(from: index - 1, through: 0, by: -1) {
            if !trashService.isTrashed(assets[i].id) {
                return i
            }
        }
        return nil
    }

    // MARK: - Tap Navigation

    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        withAnimation(.easeInOut(duration: AnimationDuration.normal)) {
            currentIndex -= 1
        }
    }

    private func goToNext() {
        guard currentIndex < assets.count - 1 else { return }
        withAnimation(.easeInOut(duration: AnimationDuration.normal)) {
            currentIndex += 1
        }
    }

    private func handleEdgeTap(at location: CGPoint) {
        let screenWidth = UIScreen.main.bounds.width
        let edgeZone = screenWidth * 0.2  // 20% on each side

        if location.x < edgeZone {
            goToPrevious()
        } else if location.x > screenWidth - edgeZone {
            goToNext()
        }
        // Center taps are ignored
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
        MediaViewerView(
            assets: sampleAssets,
            startIndex: 0,
            year: 2024,
            permissionService: PhotoPermissionService()
        )
    }
}
