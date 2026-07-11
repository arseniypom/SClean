//
//  VideoPlayerView.swift
//  SClean
//
//  Video playback: autoplays muted when the page settles (like Photos),
//  tap unmutes, tap again pauses.
//

import SwiftUI
import AVKit
import Combine

struct VideoPlayerView: View {
    let assetID: String

    @State private var player: AVPlayer?
    @State private var isReadyToPlay = false
    @State private var isPlaying = false
    @State private var isMuted = true
    @State private var isLoading: Bool
    @State private var hasError = false
    @State private var posterImage: UIImage?
    @State private var posterLoadToken: UUID?
    @State private var loadTask: Task<Void, Never>?
    @State private var loopObserver: NSObjectProtocol?
    @State private var statusCancellable: AnyCancellable?

    init(assetID: String) {
        self.assetID = assetID
        // The shared image pipeline returns the video's poster frame at its
        // real aspect ratio (prefetch usually has it warm), so the poster and
        // the first playback frame are the same shape — no resize jump.
        let poster = FullImageLoader.shared.getDisplayableImage(for: assetID)
        _posterImage = State(initialValue: poster)
        _isLoading = State(initialValue: poster == nil)
    }

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
                if let posterImage {
                    Image(uiImage: posterImage)
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
        .overlay {
            // Tap area covers only the central 60% of the page — the outer
            // edges stay free for the pager's edge-tap navigation, keeping
            // taps consistent between photo and video pages.
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleTap()
                    }
                    .frame(width: proxy.size.width * 0.6, height: proxy.size.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
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
        // Poster via the shared image pipeline if the cache was cold —
        // progressive, aspect-correct, cancellable
        if posterImage == nil && posterLoadToken == nil {
            posterLoadToken = FullImageLoader.shared.loadImage(for: assetID) { loaded, isFinal in
                if isFinal {
                    posterLoadToken = nil
                }
                if let loaded, !isReadyToPlay {
                    posterImage = loaded
                    isLoading = false
                }
            }
        }

        loadTask = Task {
            // Preheated item (instant) or on-demand request — one shared path.
            // requestPlayerItem handles slow-mo and edited videos that
            // requestAVAsset returned as AVComposition (previously a false
            // "Unable to load video" error).
            let playerItem = await VideoPreheater.shared.playerItem(for: assetID)

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
        if let token = posterLoadToken {
            posterLoadToken = nil
            FullImageLoader.shared.cancelLoad(for: assetID, token: token)
        }
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
}

// MARK: - Preview

#Preview {
    VideoPlayerView(assetID: "test-video-id")
}
