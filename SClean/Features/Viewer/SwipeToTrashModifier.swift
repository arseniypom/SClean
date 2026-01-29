//
//  SwipeToTrashModifier.swift
//  SClean
//
//  Swipe-up gesture to move items to trash
//

import SwiftUI

struct SwipeToTrashModifier: ViewModifier {
    let isEnabled: Bool
    let targetPosition: CGPoint
    let onAnimationStart: () -> Void
    let onTrash: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var opacity: Double = 1.0
    @State private var animationOffset: CGPoint = .zero
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Double = 0
    
    /// Threshold distance to commit trash action (balanced to avoid conflicts)
    private let trashThreshold: CGFloat = 90
    
    /// Maximum visual offset
    private let maxOffset: CGFloat = 200
    
    /// Progress toward trash (0 to 1)
    private var trashProgress: CGFloat {
        min(1.0, abs(dragOffset) / trashThreshold)
    }
    
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            // Use global coordinates to match targetPosition (trash icon position)
            let globalFrame = geometry.frame(in: .global)
            let viewCenter = CGPoint(
                x: globalFrame.midX,
                y: globalFrame.midY
            )

            ZStack {
                content
                    .scaleEffect(scale * (1 - (trashProgress * 0.05))) // Shrink during drag + animation
                    .rotationEffect(.degrees(rotation), anchor: .center)
                    .offset(x: animationOffset.x, y: dragOffset + animationOffset.y)
                    .opacity(opacity)

                // Trash indicator overlay
                if isDragging && abs(dragOffset) > 24 {
                    trashIndicator
                        .opacity(Double(trashProgress))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .simultaneousGesture(isEnabled ? trashGesture(viewCenter: viewCenter) : nil)
        }
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

    private func trashGesture(viewCenter: CGPoint) -> some Gesture {
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

                // Subtle tilt toward trash during drag (-5° max)
                rotation = -trashProgress * 5
            }
            .onEnded { _ in
                let shouldTrash = abs(dragOffset) >= trashThreshold

                if shouldTrash {
                    animateToTrash(from: viewCenter)
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
                        rotation = 0
                        isDragging = false
                    }
                }
            }
    }

    // MARK: - Fly to Trash Animation

    private func animateToTrash(from viewCenter: CGPoint) {
        // Signal animation start (shows next photo behind)
        onAnimationStart()

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Calculate offset to trash icon (top-right corner)
        let targetOffset = CGPoint(
            x: targetPosition.x - viewCenter.x,
            y: targetPosition.y - viewCenter.y - dragOffset // Account for current drag offset
        )

        // Animate photo shrinking, rotating, and flying to trash icon
        withAnimation(.easeOut(duration: 0.35)) {
            animationOffset = targetOffset
            scale = 0.08
            rotation = -15 // Tilt toward trash (clockwise for top-right target)
            opacity = 0
            dragOffset = 0 // Clear drag offset as we animate to position
        }

        // Trigger trash after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            onTrash()
            isDragging = false

            // Delay state reset until after parent changes currentIndex
            // This prevents the old photo from flashing back before the switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                animationOffset = .zero
                scale = 1.0
                rotation = 0
                opacity = 1.0
            }
        }
    }
}

// MARK: - View Extension

extension View {
    func swipeToTrash(
        isEnabled: Bool = true,
        targetPosition: CGPoint = .zero,
        onAnimationStart: @escaping () -> Void = {},
        onTrash: @escaping () -> Void
    ) -> some View {
        modifier(SwipeToTrashModifier(
            isEnabled: isEnabled,
            targetPosition: targetPosition,
            onAnimationStart: onAnimationStart,
            onTrash: onTrash
        ))
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










