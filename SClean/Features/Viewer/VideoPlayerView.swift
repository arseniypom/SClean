//
//  VideoPlayerView.swift
//  SClean
//
//  Video playback: autoplays muted when the page settles (like Photos),
//  tap unmutes, tap again pauses.
//

import SwiftUI
import AVKit
import Photos
import Combine

struct VideoPlayerView: View {
    let assetID: String

    @State private var player: AVPlayer?
    @State private var isReadyToPlay = false
    @State private var isPlaying = false
    @State private var isMuted = true
    @State private var isLoading = true
    @State private var hasError = false
    @State private var thumbnailImage: UIImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var loopObserver: NSObjectProtocol?
    @State private var statusCancellable: AnyCancellable?

    var body: some View {
        ZStack {
            Color.black

            if let player, isReadyToPlay {
                VideoPlayer(player: player)
                    .disabled(true) // Disable default controls, we use tap gesture
            }

            // Poster stays on top until the player is actually ready,
            // so there is never a black flash between pages.
            if !isReadyToPlay {
                if let thumbnailImage {
                    Image(uiImage: thumbnailImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if isLoading {
                    VStack(spacing: Spacing.md) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                        Text("Loading…")
                            .font(Typography.caption1)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            if hasError {
                errorView
            }

            if isReadyToPlay && !isPlaying {
                playButton
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .overlay(alignment: .bottomTrailing) {
            if isPlaying && isMuted {
                mutedBadge
            }
        }
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            stopAndCleanup()
        }
    }

    // MARK: - Play Button

    private var playButton: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.5))
                .frame(width: 72, height: 72)

            Image(systemName: "play.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .offset(x: 2) // Optical centering
        }
        .allowsHitTesting(false)
    }

    // MARK: - Muted Badge

    private var mutedBadge: some View {
        Image(systemName: "speaker.slash.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(Spacing.xs)
            .background(.black.opacity(0.45))
            .clipShape(Circle())
            .padding(Spacing.lg)
            .allowsHitTesting(false)
            .accessibilityLabel("Muted. Tap to unmute.")
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "video.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.5))

            Text("Unable to load video")
                .font(Typography.body)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Actions

    private func loadVideo() {
        loadTask = Task {
            // Poster first — the page is presentable immediately
            if thumbnailImage == nil, let thumb = await loadThumbnail() {
                thumbnailImage = thumb
                isLoading = false
            }

            guard !Task.isCancelled else { return }

            // Preheated item (instant) or on-demand request.
            // requestPlayerItem handles slow-mo and edited videos that
            // requestAVAsset returned as AVComposition (previously a false
            // "Unable to load video" error).
            let playerItem: AVPlayerItem?
            if let preheated = VideoPreheater.shared.takePlayerItem(for: assetID) {
                playerItem = preheated
            } else {
                playerItem = await requestPlayerItem()
            }

            guard !Task.isCancelled else { return }

            guard let playerItem else {
                hasError = true
                isLoading = false
                return
            }

            attachPlayer(with: playerItem)
        }
    }

    private func attachPlayer(with playerItem: AVPlayerItem) {
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.isMuted = true
        isMuted = true
        player = newPlayer

        // Loop observer token is stored and removed in stopAndCleanup
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                newPlayer.seek(to: .zero)
                isPlaying = false
            }
        }

        // Keep the poster until the item can actually render frames,
        // then start playing muted (Photos-style autoplay).
        if playerItem.status == .readyToPlay {
            startAutoplay()
        } else {
            statusCancellable = playerItem.publisher(for: \.status)
                .receive(on: DispatchQueue.main)
                .sink { status in
                    switch status {
                    case .readyToPlay:
                        startAutoplay()
                    case .failed:
                        hasError = true
                        isLoading = false
                    default:
                        break
                    }
                }
        }
    }

    private func startAutoplay() {
        guard let player, !isReadyToPlay else { return }
        isReadyToPlay = true
        isLoading = false
        player.play()
        isPlaying = true
    }

    /// Tap cycles: playing muted → unmute; playing with sound → pause; paused → play.
    private func handleTap() {
        guard let player, isReadyToPlay else { return }

        if isPlaying && isMuted {
            player.isMuted = false
            isMuted = false
        } else if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func stopAndCleanup() {
        loadTask?.cancel()
        loadTask = nil
        statusCancellable?.cancel()
        statusCancellable = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
        isReadyToPlay = false
    }

    // MARK: - Asset Loading

    private func loadThumbnail() async -> UIImage? {
        await ThumbnailLoader.shared.loadThumbnail(
            for: assetID,
            targetSize: CGSize(width: 400, height: 400)
        )
    }

    private func requestPlayerItem() async -> AVPlayerItem? {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetID],
            options: nil
        )

        guard let asset = fetchResult.firstObject else {
            return nil
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        return await withCheckedContinuation { continuation in
            var hasResumed = false
            PHImageManager.default().requestPlayerItem(
                forVideo: asset,
                options: options
            ) { playerItem, _ in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: playerItem)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VideoPlayerView(assetID: "test-video-id")
}
