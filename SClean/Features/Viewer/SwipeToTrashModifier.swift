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

    // Deck-of-cards reveal callbacks
    let onDragStart: (() -> Void)?
    let onDragProgress: ((CGFloat) -> Void)?
    let onDragCancel: (() -> Void)?

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var hasNotifiedStart = false
    @State private var isCommitting = false
    @State private var commitTask: Task<Void, Never>?

    /// Threshold distance to commit trash action
    private let trashThreshold: CGFloat = 90

    /// Maximum visual offset
    private let maxOffset: CGFloat = 200

    /// Fly-away animation timing tuned for a smooth, premium feel
    private let commitDuration: Double = 0.28

    /// Progress toward trash (0 to 1)
    private var trashProgress: CGFloat {
        min(1.0, abs(dragOffset) / trashThreshold)
    }

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            ZStack {
                content
                    .offset(y: dragOffset)
                    .scaleEffect(CGFloat(1) - (trashProgress * 0.015))
                    .opacity(Double(1) - (Double(trashProgress) * 0.08))

                // Trash indicator overlay
                if isDragging && abs(dragOffset) > 24 {
                    trashIndicator
                        .opacity(Double(trashProgress))
                }
            }
            .simultaneousGesture(isEnabled && !isCommitting ? trashGesture(containerHeight: proxy.size.height) : nil)
            .onDisappear {
                commitTask?.cancel()
                commitTask = nil
            }
        }
    }

    // MARK: - Trash Indicator

    private var trashIndicator: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 72, height: 72)
                    .scaleEffect(CGFloat(0.8) + (trashProgress * 0.2))

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

    private func trashGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard !isCommitting else { return }

                // Only respond primarily to upward drags; allow small horizontal drift
                let dy = value.translation.height
                let dx = abs(value.translation.width)
                // Require clear vertical intent to avoid stealing horizontal swipes
                guard dy < -12, abs(dy) > (dx + 10) else {
                    // Cancel if we were dragging but gesture changed direction
                    if hasNotifiedStart {
                        onDragCancel?()
                        hasNotifiedStart = false
                    }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = 0
                        isDragging = false
                    }
                    return
                }

                // Notify drag start once
                if !hasNotifiedStart {
                    onDragStart?()
                    hasNotifiedStart = true
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

                // Notify progress for deck reveal effect
                onDragProgress?(trashProgress)
            }
            .onEnded { _ in
                guard !isCommitting else { return }
                let shouldTrash = abs(dragOffset) >= trashThreshold

                if shouldTrash {
                    // Haptic feedback
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()

                    // Complete with a smooth fly-away before committing the state change
                    isCommitting = true
                    onDragProgress?(1.0)
                    isDragging = false

                    let flyOutOffset = -max(maxOffset, containerHeight + 80)
                    withAnimation(.timingCurve(0.22, 0.95, 0.30, 1.0, duration: commitDuration)) {
                        dragOffset = flyOutOffset
                    }

                    commitTask?.cancel()
                    commitTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64(commitDuration * 1_000_000_000))
                        guard !Task.isCancelled else { return }

                        await MainActor.run {
                            onTrash()
                            dragOffset = 0
                            isDragging = false
                            hasNotifiedStart = false
                            isCommitting = false
                            commitTask = nil
                        }
                    }
                    return
                } else if hasNotifiedStart {
                    // Cancelled - notify parent to hide preview
                    onDragCancel?()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = 0
                        isDragging = false
                    }
                    hasNotifiedStart = false
                    return
                }

                // Reset state
                dragOffset = 0
                isDragging = false
                hasNotifiedStart = false
            }
    }
}

// MARK: - View Extension

extension View {
    func swipeToTrash(
        isEnabled: Bool = true,
        onDragStart: (() -> Void)? = nil,
        onDragProgress: ((CGFloat) -> Void)? = nil,
        onDragCancel: (() -> Void)? = nil,
        onTrash: @escaping () -> Void
    ) -> some View {
        modifier(SwipeToTrashModifier(
            isEnabled: isEnabled,
            onTrash: onTrash,
            onDragStart: onDragStart,
            onDragProgress: onDragProgress,
            onDragCancel: onDragCancel
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
