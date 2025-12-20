//
//  ThumbnailLoader.swift
//  SClean
//
//  Efficiently loads photo thumbnails with cancellation support
//

import Photos
import SwiftUI
import Combine

// MARK: - Thumbnail Loader

/// Loads thumbnails for PHAssets efficiently.
/// - Uses PHCachingImageManager for performance
/// - Supports cancellation when cells scroll off-screen
/// - Requests small thumbnails only (never full-res)
/// Target size for grid thumbnails (3 columns on typical device)
nonisolated let gridThumbnailSize = CGSize(width: 150, height: 150)

@MainActor
final class ThumbnailLoader: ObservableObject {
    
    // Singleton for shared caching
    static let shared = ThumbnailLoader()
    
    private let imageManager = PHCachingImageManager()
    private let requestOptions: PHImageRequestOptions
    
    private init() {
        requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .opportunistic
        requestOptions.resizeMode = .fast
        requestOptions.isNetworkAccessAllowed = true // For iCloud photos
        requestOptions.version = .current
        
        // Configure caching
        imageManager.allowsCachingHighQualityImages = false
    }
    
    // MARK: - Public Methods
    
    /// Loads a thumbnail for the given asset ID.
    /// Returns nil if cancelled or failed.
    func loadThumbnail(
        for assetID: String,
        targetSize: CGSize = gridThumbnailSize
    ) async -> UIImage? {
        // Fetch the PHAsset
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetID],
            options: nil
        )
        
        guard let asset = fetchResult.firstObject else {
            return nil
        }
        
        return await loadThumbnail(for: asset, targetSize: targetSize) as UIImage?
    }
    
    /// Loads a thumbnail for a PHAsset directly
    func loadThumbnail(
        for asset: PHAsset,
        targetSize: CGSize = gridThumbnailSize
    ) async -> UIImage? {
        // Scale target size for screen
        let scale = UIScreen.main.scale
        let scaledSize = CGSize(
            width: targetSize.width * scale,
            height: targetSize.height * scale
        )
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            
            imageManager.requestImage(
                for: asset,
                targetSize: scaledSize,
                contentMode: .aspectFill,
                options: requestOptions
            ) { image, info in
                // Check if this is the final image (not degraded placeholder)
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                
                // Only resume once with the final (non-degraded) image
                if !isDegraded && !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    /// Cancels any pending requests (call when view disappears)
    func cancelAllRequests() {
        imageManager.stopCachingImagesForAllAssets()
    }
    
    /// Pre-caches thumbnails for a range of assets (call when scrolling)
    func startCaching(assetIDs: [String], targetSize: CGSize = gridThumbnailSize) {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: assetIDs,
            options: nil
        )
        
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        let scale = UIScreen.main.scale
        let scaledSize = CGSize(
            width: targetSize.width * scale,
            height: targetSize.height * scale
        )
        
        imageManager.startCachingImages(
            for: assets,
            targetSize: scaledSize,
            contentMode: .aspectFill,
            options: requestOptions
        )
    }
    
    /// Stops caching for assets no longer visible
    func stopCaching(assetIDs: [String], targetSize: CGSize = gridThumbnailSize) {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: assetIDs,
            options: nil
        )
        
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        let scale = UIScreen.main.scale
        let scaledSize = CGSize(
            width: targetSize.width * scale,
            height: targetSize.height * scale
        )
        
        imageManager.stopCachingImages(
            for: assets,
            targetSize: scaledSize,
            contentMode: .aspectFill,
            options: requestOptions
        )
    }
}

// MARK: - Thumbnail Image View

/// A view that loads and displays a thumbnail with placeholder and fade-in
struct ThumbnailImageView: View {
    let assetID: String
    
    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Placeholder
                Rectangle()
                    .fill(Color.scBorder.opacity(0.3))
                
                // Loaded image
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .transition(.opacity.animation(.easeIn(duration: AnimationDuration.fast)))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            loadThumbnail()
        }
        .onDisappear {
            cancelLoad()
        }
        .onChange(of: assetID) { _, newID in
            // Cell reuse: cancel old load, start new
            cancelLoad()
            image = nil
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        loadTask = Task {
            let loaded = await ThumbnailLoader.shared.loadThumbnail(for: assetID)
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

