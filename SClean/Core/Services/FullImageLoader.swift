//
//  FullImageLoader.swift
//  SClean
//
//  Loads full-resolution images for the viewer
//

import Photos
import UIKit

@MainActor
final class FullImageLoader {
    
    static let shared = FullImageLoader()
    
    private let imageManager = PHCachingImageManager()
    private let requestOptions: PHImageRequestOptions
    
    // Simple in-memory cache for recently loaded images
    private var cache: [String: UIImage] = [:]
    private let maxCacheSize = 9
    private var cacheOrder: [String] = []
    
    private init() {
        requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .fast
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.version = .current
    }
    
    // MARK: - Public Methods
    
    func loadFullImage(for assetID: String) async -> UIImage? {
        // Check cache first
        if let cached = cache[assetID] {
            return cached
        }
        
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetID],
            options: nil
        )
        
        guard let asset = fetchResult.firstObject else {
            return nil
        }
        
        // Target size based on screen
        let screenSize = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: screenSize.width * scale,
            height: screenSize.height * scale
        )
        
        let image = await withCheckedContinuation { continuation in
            var hasResumed = false
            
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: requestOptions
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                
                if !isDegraded && !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: image)
                }
            }
        }
        
        // Cache the result
        if let image {
            addToCache(assetID: assetID, image: image)
        }
        
        return image
    }
    
    /// Clears the image cache
    func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }
    
    // MARK: - Cache Management
    
    private func addToCache(assetID: String, image: UIImage) {
        // Remove if already exists (to update order)
        if let existingIndex = cacheOrder.firstIndex(of: assetID) {
            cacheOrder.remove(at: existingIndex)
        }
        
        // Add to cache
        cache[assetID] = image
        cacheOrder.append(assetID)
        
        // Evict oldest if over limit
        while cacheOrder.count > maxCacheSize {
            let oldest = cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}






