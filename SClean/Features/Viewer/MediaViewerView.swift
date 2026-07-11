//
//  MediaViewerView.swift
//  SClean
//
//  Full-screen viewer for photos and videos with swipe-to-trash,
//  driven by the custom DeckPagerView.
//

import SwiftUI
import Photos

struct MediaViewerView: View {
    let assets: [YearAsset]
    let startIndex: Int
    let year: Int
    @ObservedObject var permissionService: PhotoPermissionService

    @StateObject private var trashService = TrashService.shared
    @StateObject private var deckModel: ViewerDeckModel
    @State private var prefetchTasks: [String: Task<Void, Never>] = [:]
    @State private var toast: ToastData?
    @State private var showOnboarding: Bool
    @State private var currentAssetSize: Int64?
    @Environment(\.dismiss) private var dismiss

    /// Number of items to prefetch in each direction
    private let prefetchRange = 2

    init(assets: [YearAsset], startIndex: Int, year: Int, permissionService: PhotoPermissionService) {
        self.assets = assets
        self.startIndex = startIndex
        self.year = year
        self.permissionService = permissionService
        self._deckModel = StateObject(
            wrappedValue: ViewerDeckModel(assets: assets, startIndex: startIndex)
        )
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

            if deckModel.isEmpty {
                doneView
                    .transition(.opacity)
            } else {
                pagingContent

                // Keeps the white toolbar text legible over bright media
                topScrim
            }

            // Access changed overlay
            if !permissionService.status.canAccessPhotos {
                accessChangedOverlay
            }
        }
        .animation(.easeInOut(duration: 0.25), value: deckModel.isEmpty)
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
            // Picks up restores and permanent deletions made on the Trash screen
            deckModel.reconcileWithTrashService()
            prefetchAdjacent()
            fetchCurrentAssetSize()
        }
        .onChange(of: deckModel.currentAsset?.id) { _, _ in
            // Covers both page changes and deck mutations (trash/undo)
            prefetchAdjacent()
            fetchCurrentAssetSize()
        }
        .onDisappear {
            cancelAllPrefetch()
            VideoPreheater.shared.cancelAll()
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

    private var pagingContent: some View {
        DeckPagerView(
            deckModel: deckModel,
            onTrashCommitted: { removed in
                toast = ToastData(message: "Moved to Trash (not deleted)") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        deckModel.restore(removed)
                    }
                }
            }
        )
        .ignoresSafeArea()
    }

    // MARK: - Top Scrim

    /// Subtle top-edge darkening so the counter, metadata and toolbar
    /// buttons stay readable over light content (e.g. white screenshots).
    private var topScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.45), location: 0),
                .init(color: .black.opacity(0.25), location: 0.5),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 140)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    // MARK: - Counter View

    private var counterView: some View {
        VStack(spacing: 2) {
            if deckModel.isEmpty {
                Text("Done")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text("\(deckModel.currentIndex + 1) / \(deckModel.deck.count)")
                    .font(Typography.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()

                // Metadata line: date and size
                if let asset = deckModel.currentAsset {
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
        guard let asset = deckModel.currentAsset else { return }
        let deckModel = self.deckModel

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
                if deckModel.currentAsset?.id == asset.id {
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

    // MARK: - Prefetching

    private func prefetchAdjacent() {
        let deck = deckModel.deck
        guard !deck.isEmpty else {
            FullImageLoader.shared.updateCachingWindow(assetIDs: [])
            return
        }

        let currentIndex = deckModel.currentIndex
        let startPrefetch = max(0, currentIndex - prefetchRange)
        let endPrefetch = min(deck.count - 1, currentIndex + prefetchRange)
        guard startPrefetch <= endPrefetch else { return }

        var imageWindowIDs: [String] = []
        for index in startPrefetch...endPrefetch {
            let asset = deck[index]

            // Preheat player items for immediate video neighbors so
            // playback starts instantly when swiped to
            if asset.isVideo && index != currentIndex && abs(index - currentIndex) <= 1 {
                VideoPreheater.shared.preheat(assetID: asset.id)
            }

            // Videos are included in the image window too: their poster
            // frame powers instant page display and the fly-out snapshot
            imageWindowIDs.append(asset.id)
            if prefetchTasks[asset.id] == nil {
                prefetchTasks[asset.id] = Task {
                    _ = await FullImageLoader.shared.loadFullImage(for: asset.id)
                }
            }
        }

        // Warm PhotoKit's own pipeline for the same window
        FullImageLoader.shared.updateCachingWindow(assetIDs: imageWindowIDs)

        // Cancel prefetch for assets outside the window
        let windowIDs = Set(imageWindowIDs)
        for (id, task) in prefetchTasks where !windowIDs.contains(id) {
            task.cancel()
            prefetchTasks.removeValue(forKey: id)
        }
    }

    private func cancelAllPrefetch() {
        for (_, task) in prefetchTasks {
            task.cancel()
        }
        prefetchTasks.removeAll()
        FullImageLoader.shared.updateCachingWindow(assetIDs: [])
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
