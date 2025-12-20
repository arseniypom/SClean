//
//  YearGridView.swift
//  SClean
//
//  Displays a grid of photos for a specific year
//

import SwiftUI

struct YearGridView: View {
    let year: Int
    let itemCount: Int
    @ObservedObject var permissionService: PhotoPermissionService
    
    @StateObject private var photosService: YearPhotosService
    @State private var hasAppeared = false
    
    // Grid layout: 3 columns with small spacing
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    init(year: Int, itemCount: Int, permissionService: PhotoPermissionService) {
        self.year = year
        self.itemCount = itemCount
        self.permissionService = permissionService
        self._photosService = StateObject(wrappedValue: YearPhotosService(year: year))
    }
    
    var body: some View {
        ZStack {
            Color.scBackground
                .ignoresSafeArea()
            
            content
        }
        .navigationTitle(String(year))
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
                    title: "No Photos",
                    message: "No photos found for \(year)."
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
                ForEach(0..<min(itemCount, 50), id: \.self) { _ in
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
                LoadingStateView(message: "Loading photos…")
                    .padding()
                    .scCardStyle()
                    .padding(.bottom, Spacing.xxl)
            }
        }
    }
    
    // MARK: - Grid View
    
    private func gridView(_ assets: [YearAsset]) -> some View {
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
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                        NavigationLink {
                            MediaViewerView(
                                assets: assets,
                                startIndex: index,
                                year: year,
                                permissionService: permissionService
                            )
                        } label: {
                            gridCell(for: asset)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
    
    // MARK: - Grid Cell
    
    @ViewBuilder
    private func gridCell(for asset: YearAsset) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ThumbnailImageView(assetID: asset.id)
            
            // Video duration badge
            if asset.isVideo {
                videoDurationBadge(duration: asset.duration)
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
    
    // MARK: - Actions
    
    private func loadPhotos() {
        Task {
            await photosService.fetchPhotos()
        }
    }
}

// MARK: - Preview

#Preview {
    let permissionService = PhotoPermissionService()
    return NavigationStack {
        YearGridView(year: 2024, itemCount: 100, permissionService: permissionService)
    }
}

