//
//  TrashGridCell.swift
//  SClean
//
//  Grid cell for trash items with selection overlay
//

import SwiftUI
import Photos

struct TrashGridCell: View {
    let assetID: String
    let duration: TimeInterval
    let isVideo: Bool
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    
    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var isUnavailable = false
    
    var body: some View {
        Button(action: onTap) {
            GeometryReader { geometry in
                ZStack {
                    // Thumbnail or placeholder
                    thumbnailContent(size: geometry.size)
                    
                    // Video duration badge
                    if isVideo && !isUnavailable {
                        videoDurationBadge
                    }
                    
                    // Selection overlay
                    if isSelectionMode {
                        selectionOverlay
                    }
                    
                    // Unavailable overlay
                    if isUnavailable {
                        unavailableOverlay
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .onAppear {
            loadThumbnail()
        }
        .onDisappear {
            cancelLoad()
        }
    }
    
    // MARK: - Thumbnail Content
    
    @ViewBuilder
    private func thumbnailContent(size: CGSize) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.scBorder.opacity(0.3))
        }
    }
    
    // MARK: - Video Badge
    
    private var videoDurationBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(formatDuration(duration))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(4)
            }
        }
    }
    
    // MARK: - Selection Overlay
    
    private var selectionOverlay: some View {
        ZStack {
            // Dim overlay when selected
            if isSelected {
                Color.black.opacity(0.3)
            }
            
            // Selection indicator
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.scPrimary : Color.white.opacity(0.9))
                            .frame(width: 24, height: 24)
                        
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle()
                                .strokeBorder(Color.scBorder, lineWidth: 2)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .padding(6)
                }
                Spacer()
            }
        }
    }
    
    // MARK: - Unavailable Overlay
    
    private var unavailableOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
            
            VStack(spacing: Spacing.xxs) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                
                Text("Unavailable")
                    .font(Typography.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
    
    // MARK: - Loading
    
    private func loadThumbnail() {
        loadTask = Task {
            // Check if asset exists
            let fetchResult = PHAsset.fetchAssets(
                withLocalIdentifiers: [assetID],
                options: nil
            )
            
            guard fetchResult.firstObject != nil else {
                // Asset no longer available
                if !Task.isCancelled {
                    isUnavailable = true
                }
                return
            }
            
            // Load thumbnail
            let loaded = await ThumbnailLoader.shared.loadThumbnail(for: assetID)
            
            if !Task.isCancelled {
                if let loaded {
                    withAnimation(.easeIn(duration: AnimationDuration.fast)) {
                        image = loaded
                    }
                } else {
                    isUnavailable = true
                }
            }
        }
    }
    
    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 2) {
        TrashGridCell(
            assetID: "test1",
            duration: 0,
            isVideo: false,
            isSelected: false,
            isSelectionMode: false,
            onTap: {}
        )
        .frame(width: 120, height: 120)
        
        TrashGridCell(
            assetID: "test2",
            duration: 125,
            isVideo: true,
            isSelected: true,
            isSelectionMode: true,
            onTap: {}
        )
        .frame(width: 120, height: 120)
    }
    .padding()
    .background(Color.scBackground)
}



