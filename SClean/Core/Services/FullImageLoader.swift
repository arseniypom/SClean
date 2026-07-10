//
//  FullImageLoader.swift
//  SClean
//
//  Loads full-resolution images for the viewer with progressive delivery
//

import Photos
import UIKit

@MainActor
final class FullImageLoader {

    static let shared = FullImageLoader()

    /// Progressive update from a load request.
    /// Called with (degradedImage, isFinal: false) as soon as a low-quality
    /// representation is available, then (finalImage, isFinal: true) once the
    /// full-quality image is decoded. On failure or cancellation the handler
    /// receives (nil, isFinal: true) so callers can always terminate.
    typealias ImageUpdateHandler = @MainActor (UIImage?, _ isFinal: Bool) -> Void

    private let imageManager = PHCachingImageManager()
    private let requestOptions: PHImageRequestOptions
    private let targetSize: CGSize

    // In-memory LRU cache of final (full-quality, display-prepared) images.
    // 14 ≈ the ±2 prefetch window plus fast-swipe headroom; higher caps risk
    // jetsam on low-RAM devices (each entry is a decoded full-screen bitmap).
    private var cache: [String: UIImage] = [:]
    private let maxCacheSize = 14
    private var cacheOrder: [String] = []

    // Small cache of degraded (fast preview) images, used to avoid spinner
    // flashes and to snapshot the fly-out card before the final image lands
    private var degradedCache: [String: UIImage] = [:]
    private var degradedOrder: [String] = []
    private let maxDegradedCacheSize = 8

    /// One in-flight PhotoKit request per asset, fanned out to all interested callers
    private struct PendingRequest {
        var requestID: PHImageRequestID?
        var callbacks: [UUID: ImageUpdateHandler] = [:]
        var isFinishing = false
    }
    private var pending: [String: PendingRequest] = [:]

    // Assets currently preheated via PHCachingImageManager
    private var cachingWindowIDs: Set<String> = []

    private var memoryWarningObserver: NSObjectProtocol?

    private init() {
        requestOptions = PHImageRequestOptions()
        // Opportunistic: PhotoKit delivers a degraded image immediately (if one
        // is available) followed by the full-quality image. This is what removes
        // the "spinner for seconds" experience on iCloud-offloaded assets.
        requestOptions.deliveryMode = .opportunistic
        requestOptions.resizeMode = .fast
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.version = .current

        let screenSize = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        targetSize = CGSize(
            width: screenSize.width * scale,
            height: screenSize.height * scale
        )

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                FullImageLoader.shared.clearCache()
            }
        }
    }

    // MARK: - Public Methods

    /// Synchronous cache check - returns immediately if the final image is cached.
    /// Use this for instant display of prefetched images without async delay.
    func getCachedImage(for assetID: String) -> UIImage? {
        cache[assetID]
    }

    /// Best synchronously-available representation: final if cached, else degraded.
    /// Used for the fly-out card snapshot and to avoid loading flashes.
    func getDisplayableImage(for assetID: String) -> UIImage? {
        cache[assetID] ?? degradedCache[assetID]
    }

    /// Progressive load. The handler may be called multiple times (degraded then
    /// final); it is always called at least once with isFinal == true.
    /// Returns a token to cancel this caller's interest, or nil if the result
    /// was delivered synchronously from cache.
    @discardableResult
    func loadImage(for assetID: String, onUpdate: @escaping ImageUpdateHandler) -> UUID? {
        if let cached = cache[assetID] {
            onUpdate(cached, true)
            return nil
        }

        let token = UUID()

        // Join an in-flight request if one exists
        if pending[assetID] != nil {
            pending[assetID]?.callbacks[token] = onUpdate
            if let degraded = degradedCache[assetID] {
                onUpdate(degraded, false)
            }
            return token
        }

        pending[assetID] = PendingRequest(callbacks: [token: onUpdate])
        if let degraded = degradedCache[assetID] {
            onUpdate(degraded, false)
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetchResult.firstObject else {
            finish(assetID: assetID, image: nil)
            return nil
        }

        let requestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: requestOptions
        ) { image, info in
            // Asynchronous image requests deliver on the main thread
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false

            Task { @MainActor in
                let loader = FullImageLoader.shared
                if isCancelled { return }

                if isDegraded {
                    if let image {
                        loader.addToDegradedCache(assetID: assetID, image: image)
                        loader.deliverUpdate(assetID: assetID, image: image, isFinal: false)
                    }
                    return
                }

                guard let image else {
                    loader.finish(assetID: assetID, image: nil)
                    return
                }

                // Force-decode off the main thread before delivering, so the
                // first draw during a drag doesn't hitch on lazy decoding.
                loader.pending[assetID]?.isFinishing = true
                let prepared = await image.byPreparingForDisplay() ?? image
                loader.finish(assetID: assetID, image: prepared)
            }
        }

        // The request can complete synchronously (local, already-decoded asset);
        // only store the ID if the request is still pending.
        if pending[assetID] != nil {
            pending[assetID]?.requestID = requestID
        }
        return pending[assetID] != nil ? token : nil
    }

    /// Cancel one caller's interest in a load. The underlying PhotoKit request
    /// is cancelled only when no other callers remain.
    func cancelLoad(for assetID: String, token: UUID) {
        guard var request = pending[assetID] else { return }
        guard let callback = request.callbacks.removeValue(forKey: token) else { return }
        pending[assetID] = request

        // Resolve the removed caller so awaiting wrappers always terminate
        callback(nil, true)

        // Keep the request alive while the final image is being prepared —
        // it is about to land in the cache anyway.
        if request.callbacks.isEmpty && !request.isFinishing {
            if let requestID = request.requestID {
                imageManager.cancelImageRequest(requestID)
            }
            pending[assetID] = nil
        }
    }

    /// Awaits the final full-quality image. Cancelling the surrounding Task
    /// cancels the underlying PhotoKit request (if no other caller needs it).
    func loadFullImage(for assetID: String) async -> UIImage? {
        if let cached = cache[assetID] {
            return cached
        }

        let tokenBox = TokenBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                var resumed = false
                let token = loadImage(for: assetID) { image, isFinal in
                    guard isFinal, !resumed else { return }
                    resumed = true
                    continuation.resume(returning: image)
                }
                tokenBox.token = token
            }
        } onCancel: {
            Task { @MainActor in
                if let token = tokenBox.token {
                    FullImageLoader.shared.cancelLoad(for: assetID, token: token)
                }
            }
        }
    }

    /// Preheat PhotoKit's own pipeline for a window of assets. Pass the full
    /// desired window; previously-cached assets outside it stop being cached.
    func updateCachingWindow(assetIDs: [String]) {
        let newSet = Set(assetIDs)
        guard newSet != cachingWindowIDs else { return }

        let toStart = newSet.subtracting(cachingWindowIDs)
        let toStop = cachingWindowIDs.subtracting(newSet)
        cachingWindowIDs = newSet

        if !toStart.isEmpty {
            imageManager.startCachingImages(
                for: fetchAssets(Array(toStart)),
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: requestOptions
            )
        }
        if !toStop.isEmpty {
            imageManager.stopCachingImages(
                for: fetchAssets(Array(toStop)),
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: requestOptions
            )
        }
    }

    /// Clears the image caches (called on memory warnings)
    func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
        degradedCache.removeAll()
        degradedOrder.removeAll()
    }

    // MARK: - Private Helpers

    /// Mutable box so the cancellation handler can reach a token assigned
    /// after the continuation is set up.
    private final class TokenBox: @unchecked Sendable {
        var token: UUID?
    }

    private func fetchAssets(_ ids: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    private func deliverUpdate(assetID: String, image: UIImage?, isFinal: Bool) {
        guard let request = pending[assetID] else { return }
        for callback in request.callbacks.values {
            callback(image, isFinal)
        }
    }

    private func finish(assetID: String, image: UIImage?) {
        if let image {
            addToCache(assetID: assetID, image: image)
            degradedCache.removeValue(forKey: assetID)
            degradedOrder.removeAll { $0 == assetID }
        }
        deliverUpdate(assetID: assetID, image: image, isFinal: true)
        pending[assetID] = nil
    }

    // MARK: - Cache Management

    private func addToCache(assetID: String, image: UIImage) {
        if let existingIndex = cacheOrder.firstIndex(of: assetID) {
            cacheOrder.remove(at: existingIndex)
        }

        cache[assetID] = image
        cacheOrder.append(assetID)

        while cacheOrder.count > maxCacheSize {
            let oldest = cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    private func addToDegradedCache(assetID: String, image: UIImage) {
        if let existingIndex = degradedOrder.firstIndex(of: assetID) {
            degradedOrder.remove(at: existingIndex)
        }

        degradedCache[assetID] = image
        degradedOrder.append(assetID)

        while degradedOrder.count > maxDegradedCacheSize {
            let oldest = degradedOrder.removeFirst()
            degradedCache.removeValue(forKey: oldest)
        }
    }
}
