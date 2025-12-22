//
//  SwipeToTrashModifier.swift
//  SClean
//
//  Swipe-up gesture to move items to trash
//

import SwiftUI

struct SwipeToTrashModifier: ViewModifier {
    let isEnabled: Bool
    let onTrash: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    /// Threshold distance to commit trash action (balanced to avoid conflicts)
    private let trashThreshold: CGFloat = 90
    
    /// Maximum visual offset
    private let maxOffset: CGFloat = 200
    
    /// Progress toward trash (0 to 1)
    private var trashProgress: CGFloat {
        min(1.0, abs(dragOffset) / trashThreshold)
    }
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .offset(y: dragOffset)
                .scaleEffect(1 - (trashProgress * 0.05)) // Subtle shrink
            
            // Trash indicator overlay
            if isDragging && abs(dragOffset) > 24 {
                trashIndicator
                    .opacity(Double(trashProgress))
            }
        }
        .simultaneousGesture(isEnabled ? trashGesture : nil)
    }
    
    // MARK: - Trash Indicator
    
    private var trashIndicator: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 72, height: 72)
                    .scaleEffect(0.8 + (trashProgress * 0.2))
                
                Image(systemName: trashProgress >= 1.0 ? "trash.fill" : "trash")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
            
            Text(trashProgress >= 1.0 ? "Release to Trash" : "Swipe to Trash")
                .font(Typography.caption1)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.3))
    }
    
    // MARK: - Gesture
    
    private var trashGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                // Only respond primarily to upward drags; allow small horizontal drift
                let dy = value.translation.height
                let dx = abs(value.translation.width)
                // Require clear vertical intent to avoid stealing horizontal swipes
                guard dy < -12, abs(dy) > (dx + 10) else {
                    dragOffset = 0
                    isDragging = false
                    return
                }
                
                isDragging = true
                
                // Apply resistance after threshold
                let translation = -dy // positive magnitude for upward drag
                if translation < trashThreshold {
                    dragOffset = -translation
                } else {
                    // Rubber-band effect past threshold
                    let overflow = translation - trashThreshold
                    dragOffset = -(trashThreshold + (overflow * 0.3))
                }
                
                dragOffset = max(dragOffset, -maxOffset)
            }
            .onEnded { value in
                let shouldTrash = abs(dragOffset) >= trashThreshold
                
                if shouldTrash {
                    // Haptic feedback
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    
                    // Animate out
                    withAnimation(.easeOut(duration: AnimationDuration.fast)) {
                        dragOffset = -(maxOffset + 100)
                    }
                    
                    // Trigger trash after animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + AnimationDuration.fast) {
                        onTrash()
                        dragOffset = 0
                        isDragging = false
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
                        isDragging = false
                    }
                }
            }
    }
}

// MARK: - View Extension

extension View {
    func swipeToTrash(isEnabled: Bool = true, onTrash: @escaping () -> Void) -> some View {
        modifier(SwipeToTrashModifier(isEnabled: isEnabled, onTrash: onTrash))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        RoundedRectangle(cornerRadius: 12)
            .fill(.blue)
            .frame(width: 300, height: 400)
            .swipeToTrash {
                print("Trashed!")
            }
    }
}


