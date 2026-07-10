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

    @State private var image: UIImage?
    @State private var isFinalImage: Bool
    @State private var isLoading: Bool
    @State private var hasError = false
    @State private var loadToken: UUID?

    init(
        asset: YearAsset,
        isCurrentPage: Bool
    ) {
        self.asset = asset
        self.isCurrentPage = isCurrentPage

        // Pre-populate from cache to avoid loading state flash (blink/shift bug fix)
        // Each page is a fresh view identity with new @State, so without this the
        // view briefly shows ProgressView before the cached image loads. A degraded
        // (fast preview) image is good enough to start with — the final image
        // sharpens in place once loaded.
        if asset.mediaType != .video,
           let cached = FullImageLoader.shared.getCachedImage(for: asset.id) {
            _image = State(initialValue: cached)
            _isFinalImage = State(initialValue: true)
            _isLoading = State(initialValue: false)
        } else if asset.mediaType != .video,
                  let preview = FullImageLoader.shared.getDisplayableImage(for: asset.id) {
            _image = State(initialValue: preview)
            _isFinalImage = State(initialValue: false)
            _isLoading = State(initialValue: false)
        } else {
            _image = State(initialValue: nil)
            _isFinalImage = State(initialValue: false)
            _isLoading = State(initialValue: asset.mediaType != .video)
        }
    }
    
    var body: some View {
        ZStack {
            // Transparent background - black is provided by parent (MediaViewerView)
            // This allows swipe-to-trash animation to show only the photo, not letterboxing
            Color.clear

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
            // Reload if becoming current without a full-quality image yet
            if isCurrent && !isFinalImage && asset.mediaType != .video {
                loadImage()
            }
        }
    }
    
    // MARK: - Photo View
    
    @ViewBuilder
    private var photoView: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityIdentifier("photoImage")
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
    
    // MARK: - Image Loading
    
    private func loadImage() {
        guard !isFinalImage, loadToken == nil else { return }

        // Synchronous cache check - instant display for prefetched images
        if let cached = FullImageLoader.shared.getCachedImage(for: asset.id) {
            image = cached
            isFinalImage = true
            isLoading = false
            return
        }

        hasError = false
        if image == nil {
            isLoading = true
        }

        // Progressive load: degraded preview lands immediately (no spinner),
        // the full-quality image then sharpens in place.
        loadToken = FullImageLoader.shared.loadImage(for: asset.id) { loaded, isFinal in
            if let loaded {
                if isFinal {
                    loadToken = nil
                    isFinalImage = true
                    isLoading = false
                    withAnimation(.easeIn(duration: AnimationDuration.fast)) {
                        image = loaded
                    }
                } else if !isFinalImage {
                    image = loaded
                    isLoading = false
                }
            } else if isFinal {
                loadToken = nil
                if image == nil {
                    hasError = true
                    isLoading = false
                }
            }
        }
    }

    private func cancelLoad() {
        if let token = loadToken {
            loadToken = nil
            FullImageLoader.shared.cancelLoad(for: asset.id, token: token)
        }
    }
}

// MARK: - Preview

#Preview {
    MediaPageView(
        asset: YearAsset(id: "test", creationDate: Date(), mediaType: .photo),
        isCurrentPage: true
    )
}
