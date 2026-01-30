//
//  MediaViewerView.swift
//  SClean
//
//  Full-screen paging viewer for photos and videos with swipe-to-trash
//

import SwiftUI
import Photos

struct MediaViewerView: View {
    let assets: [YearAsset]
    let startIndex: Int
    let year: Int
    @ObservedObject var permissionService: PhotoPermissionService

    @StateObject private var trashService = TrashService.shared
    @StateObject private var animationState: SwipeToTrashAnimationState
    @State private var prefetchTasks: [String: Task<Void, Never>] = [:]
    @State private var toast: ToastData?
    @State private var showOnboarding: Bool
    @State private var currentAssetSize: Int64?
    @Environment(\.dismiss) private var dismiss

    /// Number of items to prefetch in each direction
    private let prefetchRange = 2

    /// Computed accessor for current index (maintained by animation state)
    private var currentIndex: Int {
        get { animationState.currentIndex }
    }

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
        self._animationState = StateObject(wrappedValue: SwipeToTrashAnimationState(currentIndex: startIndex))
        // Check all legacy keys for migration
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "SClean.hasCompletedViewerOnboarding") ||
            UserDefaults.standard.bool(forKey: "SlideClean.hasSeenBrowseHint") ||
            UserDefaults.standard.bool(forKey: "SClean.hasSeenBrowseHint") ||
            UserDefaults.standard.bool(forKey: "SlideClean.hasSeenTrashHint") ||
            UserDefaults.standard.bool(forKey: "SClean.hasSeenTrashHint")
        self._showOnboarding = State(initialValue: !hasCompletedOnboarding)
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
                }
                .accessibilityLabel("Trash (\(trashService.trashCount) items)")
            }
        }
        .statusBarHidden(false)
        .onAppear {
            prefetchAdjacent()
            fetchCurrentAssetSize()
        }
        .onChange(of: animationState.currentIndex) { _, _ in
            prefetchAdjacent()
            fetchCurrentAssetSize()
        }
        .onDisappear {
            cancelAllPrefetch()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            permissionService.refreshStatus()
        }
        .undoToast($toast)
        .sheet(isPresented: $showOnboarding) {
            ViewerOnboardingView()
        }
    }

    // MARK: - Paging Content

    /// Binding for TabView selection that syncs with animation state
    private var currentIndexBinding: Binding<Int> {
        Binding(
            get: { animationState.currentIndex },
            set: { animationState.currentIndex = $0 }
        )
    }

    private var pagingContent: some View {
        ZStack {
            Color.black

            // Preview layer - next photo visible underneath during swipe
            previewLayer

            // Main TabView
            TabView(selection: currentIndexBinding) {
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

    // MARK: - Preview Layer (Deck Effect)

    @ViewBuilder
    private var previewLayer: some View {
        if animationState.isAnimating,
           let previewID = animationState.previewAssetID,
           let previewAsset = assets.first(where: { $0.id == previewID }) {
            MediaPageView(
                asset: previewAsset,
                isCurrentPage: false,
                isTrashed: false
            )
        }
    }

    private func pageView(for index: Int, asset: YearAsset) -> some View {
        let isTrashed = trashService.isTrashed(asset.id)
        let nextAsset = findNextVisibleAsset(from: index)

        return MediaPageView(
            asset: asset,
            isCurrentPage: index == currentIndex,
            isTrashed: isTrashed
        ) {
            trashService.restore(asset.id)
        }
        .swipeToTrash(
            isEnabled: !isTrashed,
            onDragStart: {
                // Show preview of next photo underneath
                if let next = nextAsset {
                    animationState.startAnimation(nextAssetID: next.id)
                }
            },
            onDragProgress: { progress in
                animationState.updateDragProgress(progress)
            },
            onDragCancel: {
                animationState.cancelAnimation()
            },
            onTrash: {
                trashItem(at: index)
            }
        )
        .accessibilityIdentifier(index == currentIndex ? "currentPhotoView" : "photoView_\(index)")
    }

    /// Find the next visible (non-trashed) asset from a given index
    private func findNextVisibleAsset(from index: Int) -> YearAsset? {
        // Try forward first
        for i in (index + 1)..<assets.count {
            if !trashService.isTrashed(assets[i].id) {
                return assets[i]
            }
        }
        // Then try backward
        for i in stride(from: index - 1, through: 0, by: -1) {
            if !trashService.isTrashed(assets[i].id) {
                return assets[i]
            }
        }
        return nil
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

    private func trashItem(at index: Int) {
        guard index < assets.count else { return }

        let asset = assets[index]
        let assetID = asset.id

        // Find next visible BEFORE trashing (while current item is still "visible")
        let nextIndex = nextVisibleIndex(from: index)

        // Trash the item
        trashService.trash(assetID)

        // Show undo toast
        toast = ToastData(message: "Moved to Trash (not deleted)") {
            trashService.restore(assetID)
        }

        // Advance to next visible using animation state
        if let nextIndex {
            animationState.completeAnimation(nextIndex: nextIndex)
        } else {
            // No more visible items - reset animation state
            animationState.reset()
        }
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
        guard animationState.currentIndex > 0 else { return }
        animationState.currentIndex -= 1
    }

    private func goToNext() {
        guard animationState.currentIndex < assets.count - 1 else { return }
        animationState.currentIndex += 1
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
