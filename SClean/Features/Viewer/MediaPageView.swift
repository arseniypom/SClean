//
//  MediaPageView.swift
//  SClean
//
//  Single page view for photo or video in the paging viewer
//

import SwiftUI

struct MediaPageView: View {
    let asset: YearAsset
    let isCurrentPage: Bool
    let isTrashed: Bool
    let onUndoTrash: (() -> Void)?
    
    init(
        asset: YearAsset,
        isCurrentPage: Bool,
        isTrashed: Bool = false,
        onUndoTrash: (() -> Void)? = nil
    ) {
        self.asset = asset
        self.isCurrentPage = isCurrentPage
        self.isTrashed = isTrashed
        self.onUndoTrash = onUndoTrash
    }
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            Color.black
            
            switch asset.mediaType {
            case .video:
                if isCurrentPage {
                    VideoPlayerView(assetID: asset.id)
                } else {
                    // Show static thumbnail when not current page
                    thumbnailView
                }
                
            case .photo, .livePhoto, .unknown:
                photoView
            }
        }
        .onAppear {
            if asset.mediaType != .video {
                loadImage()
            }
        }
        .onDisappear {
            cancelLoad()
        }
        .onChange(of: isCurrentPage) { _, isCurrent in
            // Reload if becoming current and no image yet
            if isCurrent && image == nil && asset.mediaType != .video {
                loadImage()
            }
        }
        .overlay {
            trashedOverlay
        }
    }
    
    // MARK: - Photo View
    
    @ViewBuilder
    private var photoView: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .transition(.opacity.animation(.easeIn(duration: AnimationDuration.fast)))
        } else if isLoading {
            VStack(spacing: Spacing.md) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                Text("Loading…")
                    .font(Typography.caption1)
                    .foregroundStyle(.white.opacity(0.8))
            }
        } else if hasError {
            errorView
        }
    }
    
    // MARK: - Thumbnail View (for non-current video pages)
    
    @ViewBuilder
    private var thumbnailView: some View {
        ThumbnailImageView(assetID: asset.id)
            .overlay {
                // Video indicator
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.4))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                }
            }
    }
    
    // MARK: - Error View
    
    private var errorView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "photo")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.5))

            Text("Can't load right now")
                .font(Typography.body)
                .foregroundStyle(.white.opacity(0.8))

            Text("Swipe to skip")
                .font(Typography.caption1)
                .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityLabel("Can't load this item. Swipe to skip.")
    }
    
    // MARK: - Trashed Overlay

    @ViewBuilder
    private var trashedOverlay: some View {
        if isTrashed, let onUndoTrash {
            VStack(spacing: Spacing.md) {
                Image(systemName: "trash")
                    .font(.system(size: 24, weight: .medium))

                VStack(spacing: Spacing.xs) {
                    Text("Marked for deletion")
                        .font(Typography.headline)

                    Text("This item will be removed when you empty the Trash.")
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    withAnimation(.easeOut(duration: AnimationDuration.fast)) {
                        onUndoTrash()
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Undo")
                            .font(Typography.headline)
                    }
                    .padding(.vertical, Spacing.sm)
                    .padding(.horizontal, Spacing.lg)
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 280)
            .scControlSurface()
        }
    }
    
    // MARK: - Image Loading
    
    private func loadImage() {
        guard image == nil else { return }
        
        isLoading = true
        hasError = false
        
        loadTask = Task {
            let loaded = await FullImageLoader.shared.loadFullImage(for: asset.id)
            
            if !Task.isCancelled {
                if let loaded {
                    withAnimation(.easeIn(duration: AnimationDuration.fast)) {
                        image = loaded
                        isLoading = false
                    }
                } else {
                    hasError = true
                    isLoading = false
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
    MediaPageView(
        asset: YearAsset(id: "test", creationDate: Date(), mediaType: .photo),
        isCurrentPage: true
    )
}
