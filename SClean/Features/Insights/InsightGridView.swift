//
//  InsightGridView.swift
//  SClean
//
//  Displays a grid of photos for a specific insight recommendation.
//

import SwiftUI

struct InsightGridView: View {
    let bucket: InsightBucket
    let snapshot: LibraryIndexSnapshot?
    @ObservedObject var permissionService: PhotoPermissionService

    @StateObject private var photosService: InsightPhotosService
    @ObservedObject private var trashService = TrashService.shared

    @State private var hasAppeared = false
    @State private var showMoveAllConfirmation = false
    
    private enum DuplicateRole {
        case keeper
        case extra
    }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    init(bucket: InsightBucket, snapshot: LibraryIndexSnapshot?, permissionService: PhotoPermissionService) {
        self.bucket = bucket
        self.snapshot = snapshot
        self.permissionService = permissionService
        self._photosService = StateObject(
            wrappedValue: InsightPhotosService(category: bucket.category, snapshot: snapshot)
        )
    }

    var body: some View {
        ZStack {
            Color.scBackground
                .ignoresSafeArea()

            content
        }
        .navigationTitle(bucket.category.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !visibleAssets.isEmpty {
                    Button(moveButtonTitle) {
                        showMoveAllConfirmation = true
                    }
                    .font(Typography.subheadline)
                    .foregroundStyle(Color.scDestructive)
                }
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                loadPhotos()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            permissionService.refreshStatus()
        }
        .alert(moveAlertTitle, isPresented: $showMoveAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move", role: .destructive) {
                moveAllVisibleToTrash()
            }
        } message: {
            Text(moveAlertMessage)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !permissionService.status.canAccessPhotos {
            EmptyStateView(
                icon: "lock.fill",
                title: "Access Required",
                message: "Photo access was removed. Please re-enable it in Settings.",
                actionTitle: "Open Settings"
            ) {
                permissionService.openSettings()
            }
        } else {
            switch photosService.state {
            case .idle, .loading:
                loadingView

            case .loaded(let assets):
                gridView(assets)

            case .empty:
                EmptyStateView(
                    icon: bucket.category.icon,
                    title: "Nothing to clean here",
                    message: "No items match this insight right now."
                )

            case .error(let message):
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Something went wrong",
                    message: message,
                    actionTitle: "Try Again"
                ) {
                    loadPhotos()
                }
            }
        }
    }

    private var loadingView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<min(bucket.count, 50), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.scBorder.opacity(0.3))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, 2)
        }
        .overlay {
            VStack {
                Spacer()
                LoadingStateView(message: "Loading insight photos…")
                    .padding()
                    .scCardStyle()
                    .padding(.bottom, Spacing.xxl)
            }
        }
    }

    private func gridView(_ originalAssets: [YearAsset]) -> some View {
        let excludedIDs = trashService.excludedIDs
        let filteredAssets = originalAssets.filter { !excludedIDs.contains($0.id) }
        let duplicateGroupByAssetID = photosService.exactDuplicateGroupByAssetID

        return GeometryReader { proxy in
            let horizontalPadding: CGFloat = 2 * 2
            let spacing: CGFloat = 2
            let totalSpacing: CGFloat = spacing * 2
            let side = (proxy.size.width - horizontalPadding - totalSpacing) / 3

            ScrollView {
                VStack(spacing: 0) {
                    InfoBanner(
                        icon: bucket.category.icon,
                        message: insightInfoMessage,
                        style: .info
                    )
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)

                    if permissionService.status.isLimited {
                        InfoBanner(
                            icon: "photo.badge.plus",
                            message: "Showing selected photos only",
                            style: .info
                        ) {
                            permissionService.presentLimitedLibraryPicker()
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.sm)
                    }

                    if bucket.category == .exactDuplicates && !duplicateGroupByAssetID.isEmpty {
                        exactDuplicateLegend
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, Spacing.sm)
                    }

                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(filteredAssets.indices, id: \.self) { filteredIndex in
                            let asset = filteredAssets[filteredIndex]
                            let originalIndex = originalAssets.firstIndex(where: { $0.id == asset.id }) ?? filteredIndex

                            NavigationLink {
                                MediaViewerView(
                                    assets: originalAssets,
                                    startIndex: originalIndex,
                                    year: Calendar.current.component(.year, from: asset.creationDate),
                                    permissionService: permissionService
                                )
                            } label: {
                                gridCell(for: asset, size: side)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("insightPhoto_\(filteredIndex)")
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private var visibleAssets: [YearAsset] {
        photosService.state.assets.filter { !trashService.excludedIDs.contains($0.id) }
    }

    private var moveButtonTitle: String {
        bucket.category == .exactDuplicates ? "Move Extras" : "Move All"
    }

    private var moveAlertTitle: String {
        bucket.category == .exactDuplicates ? "Move duplicate extras to Trash?" : "Move all to Trash?"
    }

    private var moveAlertMessage: String {
        if bucket.category == .exactDuplicates {
            let extrasCount = visibleAssets.filter { photosService.exactDuplicateDeletableIDs.contains($0.id) }.count
            return "All copies are visible for review. SClean will keep one best copy per group and move \(extrasCount) extras to Trash."
        }
        return "This adds \(visibleAssets.count) items to Trash. You can review and restore them later."
    }

    private var insightInfoMessage: String {
        if bucket.category == .exactDuplicates {
            return "All verified copies are shown. Move Extras keeps one best copy per group."
        }
        return bucket.category.ruleDescription
    }

    @ViewBuilder
    private func gridCell(for asset: YearAsset, size: CGFloat) -> some View {
        ThumbnailImageView(assetID: asset.id)
            .frame(width: size, height: size)
            .clipped()
            .overlay(alignment: .topLeading) {
                if let groupTag = duplicateGroupTag(for: asset.id) {
                    insightChip(groupTag, tint: .scInfo)
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let role = duplicateRole(for: asset.id) {
                    switch role {
                    case .keeper:
                        insightChip("Keep", tint: .scSuccess)
                            .padding(4)
                    case .extra:
                        insightChip("Extra", tint: .scWarning)
                            .padding(4)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.isVideo {
                    Text(formatDuration(asset.duration))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .padding(4)
                }
            }
            .overlay {
                if let role = duplicateRole(for: asset.id) {
                    Rectangle()
                        .strokeBorder(role == .keeper ? Color.scSuccess.opacity(0.65) : Color.scWarning.opacity(0.65), lineWidth: 2)
                }
            }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func moveAllVisibleToTrash() {
        guard !visibleAssets.isEmpty else { return }

        if bucket.category == .exactDuplicates {
            let deletable = photosService.exactDuplicateDeletableIDs
            let orderedIDs = visibleAssets.map(\.id)
            let idsToTrash = orderedIDs.filter { deletable.contains($0) }
            for id in idsToTrash {
                trashService.trash(id)
            }
            return
        }

        for asset in visibleAssets {
            trashService.trash(asset.id)
        }
    }
    
    @ViewBuilder
    private var exactDuplicateLegend: some View {
        HStack(spacing: Spacing.xs) {
            insightChip("Keep", tint: .scSuccess)
            insightChip("Extra", tint: .scWarning)
            if exactDuplicateGroupCount > 0 {
                insightChip("\(exactDuplicateGroupCount) groups", tint: .scInfo)
            }
            Spacer()
        }
    }
    
    private var exactDuplicateGroupCount: Int {
        Set(photosService.exactDuplicateGroupByAssetID.values).count
    }
    
    private func duplicateGroupTag(for assetID: String) -> String? {
        guard bucket.category == .exactDuplicates,
              let groupIndex = photosService.exactDuplicateGroupByAssetID[assetID] else {
            return nil
        }
        return "G\(groupIndex)"
    }
    
    private func duplicateRole(for assetID: String) -> DuplicateRole? {
        guard bucket.category == .exactDuplicates else { return nil }
        if photosService.exactDuplicateKeeperIDs.contains(assetID) {
            return .keeper
        }
        if photosService.exactDuplicateDeletableIDs.contains(assetID) {
            return .extra
        }
        return nil
    }
    
    private func insightChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Typography.caption2.weight(.semibold))
            .foregroundStyle(Color.scTextPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.2), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(tint.opacity(0.55), lineWidth: 1)
            }
    }

    private func loadPhotos() {
        Task {
            await photosService.fetchPhotos()
        }
    }
}

#Preview {
    let permissionService = PhotoPermissionService()
    let bucket = InsightBucket(category: .shortVideos, count: 42, totalBytes: 210_000_000)

    return NavigationStack {
        InsightGridView(bucket: bucket, snapshot: nil, permissionService: permissionService)
    }
}
