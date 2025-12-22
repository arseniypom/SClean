//
//  VideoPlayerView.swift
//  SClean
//
//  Video playback component with tap-to-play
//

import SwiftUI
import AVKit
import Photos

struct VideoPlayerView: View {
    let assetID: String
    
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isLoading = true
    @State private var hasError = false
    @State private var thumbnailImage: UIImage?
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player, isPlaying {
                VideoPlayer(player: player)
                    .disabled(true) // Disable default controls, we use tap gesture
            } else if let thumbnailImage {
                // Show thumbnail with play button
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                
                // Play button overlay
                playButton
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
        .contentShape(Rectangle())
        .onTapGesture {
            togglePlayback()
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
            // First load thumbnail
            if let thumb = await loadThumbnail() {
                thumbnailImage = thumb
                isLoading = false
            }
            
            // Then prepare player
            if let url = await getVideoURL() {
                let playerItem = AVPlayerItem(url: url)
                player = AVPlayer(playerItem: playerItem)
                player?.isMuted = false
                
                // Loop video
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: playerItem,
                    queue: .main
                ) { _ in
                    player?.seek(to: .zero)
                    isPlaying = false
                }
            } else {
                hasError = true
                isLoading = false
            }
        }
    }
    
    private func togglePlayback() {
        guard player != nil else { return }
        
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true
        }
    }
    
    private func stopAndCleanup() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        player = nil
        isPlaying = false
    }
    
    // MARK: - Asset Loading
    
    private func loadThumbnail() async -> UIImage? {
        await ThumbnailLoader.shared.loadThumbnail(
            for: assetID,
            targetSize: CGSize(width: 400, height: 400)
        )
    }
    
    private func getVideoURL() async -> URL? {
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
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VideoPlayerView(assetID: "test-video-id")
}

