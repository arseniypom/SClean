//
//  TypeGridView.swift
//  SClean
//
//  Displays a grid of photos for a specific type category
//

import SwiftUI

struct TypeGridView: View {
    let bucket: TypeBucket
    let snapshot: LibraryIndexSnapshot?
    @ObservedObject var permissionService: PhotoPermissionService

    @StateObject private var photosService: TypePhotosService
    @ObservedObject private var trashService = TrashService.shared
    @State private var hasAppeared = false

    // Grid layout: 3 columns with small spacing
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    init(bucket: TypeBucket, snapshot: LibraryIndexSnapshot?, permissionService: PhotoPermissionService) {
        self.bucket = bucket
        self.snapshot = snapshot
        self.permissionService = permissionService
        self._photosService = StateObject(wrappedValue: TypePhotosService(category: bucket.category, snapshot: snapshot))
    }

    var body: some View {
        ZStack {
            Color.scBackground
                .ignoresSafeArea()

            content
        }
        .navigationTitle(bucket.category.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                loadPhotos()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            permissionService.refreshStatus()
        }
    }

    @ViewBuilder
    private var content: some View {
        // Check if permission was revoked mid-session
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
                    icon: "photo.on.rectangle",
                    title: "No \(bucket.category.rawValue)",
                    message: "No media found in this category."
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

    // MARK: - Loading View

    private var loadingView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                // Show placeholder grid matching expected count
                ForEach(0..<min(bucket.count, 50), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.scBorder.opacity(0.3))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, 2)
        }
        .overlay {
            // Subtle loading indicator on top
            VStack {
                Spacer()
                LoadingStateView(message: "Loading \(bucket.category.rawValue.lowercased())...")
                    .padding()
                    .scCardStyle()
                    .padding(.bottom, Spacing.xxl)
            }
        }
    }

    // MARK: - Grid View

    private func gridView(_ assets: [YearAsset]) -> some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 2 * 2 // .padding(.horizontal, 2)
            let spacing: CGFloat = 2
            let totalSpacing: CGFloat = spacing * 2 // 3 columns -> 2 gaps
            let side = (proxy.size.width - horizontalPadding - totalSpacing) / 3

            ScrollView {
                VStack(spacing: 0) {
                    // Limited Access banner
                    if permissionService.status.isLimited {
                        InfoBanner(
                            icon: "photo.badge.plus",
                            message: "Showing selected photos only",
                            style: .info
                        ) {
                            permissionService.presentLimitedLibraryPicker()
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                    }

                    // Photo grid
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(assets.indices, id: \.self) { index in
                            let asset = assets[index]
                            NavigationLink {
                                MediaViewerView(
                                    assets: assets,
                                    startIndex: index,
                                    year: Calendar.current.component(.year, from: asset.creationDate),
                                    permissionService: permissionService
                                )
                            } label: {
                                gridCell(for: asset, size: side, showSizeBadge: isLargestCategory)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("gridPhoto_\(index)")
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private var isLargestCategory: Bool {
        bucket.category == .largestVideos || bucket.category == .largestPhotos
    }

    // MARK: - Grid Cell

    @ViewBuilder
    private func gridCell(for asset: YearAsset, size: CGFloat, showSizeBadge: Bool) -> some View {
        let isTrashed = trashService.isTrashed(asset.id)

        ThumbnailImageView(assetID: asset.id)
            .opacity(isTrashed ? 0.5 : 1.0)
            .frame(width: size, height: size)
            .clipped()
            // Overlays applied AFTER frame/clip so they use fixed bounds
            .overlay(alignment: .bottomTrailing) {
                if asset.isVideo {
                    videoDurationBadge(duration: asset.duration)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isTrashed {
                    trashedBadge
                }
            }
    }

    private func videoDurationBadge(duration: TimeInterval) -> some View {
        Text(formatDuration(duration))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .padding(4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var trashedBadge: some View {
        Image(systemName: "trash.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(5)
            .background(.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(4)
    }

    // MARK: - Actions

    private func loadPhotos() {
        Task {
            await photosService.fetchPhotos()
        }
    }
}

// MARK: - Preview

#Preview {
    let bucket = TypeBucket(category: .videos, count: 100, totalBytes: 500_000_000)
    let permissionService = PhotoPermissionService()
    return NavigationStack {
        TypeGridView(bucket: bucket, snapshot: nil, permissionService: permissionService)
    }
}
