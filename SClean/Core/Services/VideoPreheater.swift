//
//  VideoPreheater.swift
//  SClean
//
//  Preheats AVPlayerItems for videos adjacent to the current viewer page
//  so playback starts instantly when the user swipes to them.
//

import Photos
import AVFoundation

@MainActor
final class VideoPreheater {

    static let shared = VideoPreheater()

    private struct Entry {
        var requestID: PHImageRequestID?
        var playerItem: AVPlayerItem?
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private let maxEntries = 2

    private init() {}

    // MARK: - Public Methods

    /// Start preparing a player item for the given video asset.
    /// No-op if it is already preheating or ready.
    func preheat(assetID: String) {
        guard entries[assetID] == nil else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetchResult.firstObject else { return }

        entries[assetID] = Entry()
        order.append(assetID)
        evictIfNeeded()
        guard entries[assetID] != nil else { return }

        let requestID = PHImageManager.default().requestPlayerItem(
            forVideo: asset,
            options: Self.makeRequestOptions()
        ) { playerItem, _ in
            Task { @MainActor in
                let preheater = VideoPreheater.shared
                guard preheater.entries[assetID] != nil else { return }
                preheater.entries[assetID]?.playerItem = playerItem
                preheater.entries[assetID]?.requestID = nil
            }
        }
        entries[assetID]?.requestID = requestID
    }

    /// Hand the preheated player item to a consumer (removes it from the pool).
    /// Returns nil if the item is not ready yet or was never preheated —
    /// the caller falls back to its own request.
    func takePlayerItem(for assetID: String) -> AVPlayerItem? {
        guard let entry = entries[assetID], let playerItem = entry.playerItem else {
            return nil
        }
        entries.removeValue(forKey: assetID)
        order.removeAll { $0 == assetID }
        return playerItem
    }

    /// The single request path for playback: the preheated item when ready,
    /// otherwise a fresh request with identical options — so both paths
    /// always produce the same video quality/configuration.
    func playerItem(for assetID: String) async -> AVPlayerItem? {
        // A preheated item can have died in the pool (network drop mid-preheat,
        // stale streaming URL) — fall back to a fresh request in that case.
        if let preheated = takePlayerItem(for: assetID), preheated.status != .failed {
            return preheated
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        return await withCheckedContinuation { continuation in
            var hasResumed = false
            PHImageManager.default().requestPlayerItem(
                forVideo: asset,
                options: Self.makeRequestOptions()
            ) { playerItem, _ in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: playerItem)
            }
        }
    }

    /// Cancel all pending preheat requests and drop prepared items.
    func cancelAll() {
        for entry in entries.values {
            if let requestID = entry.requestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
        entries.removeAll()
        order.removeAll()
    }

    // MARK: - Private

    private static func makeRequestOptions() -> PHVideoRequestOptions {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        return options
    }

    private func evictIfNeeded() {
        while order.count > maxEntries {
            let oldest = order.removeFirst()
            if let requestID = entries[oldest]?.requestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
            entries.removeValue(forKey: oldest)
        }
    }
}
