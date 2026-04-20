//
//  SwipeToTrashModifier.swift
//  SClean
//
//  Swipe-up gesture to move items to trash
//

import SwiftUI
import Foundation

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
    @State private var lastLoggedProgressBucket = -1
    @State private var dragSessionID = 0
    @State private var commitScale: CGFloat = 1.0
    @State private var commitRotation: Double = 0.0
    @State private var impactFeedback: UIImpactFeedbackGenerator?

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

    private var contentScale: CGFloat {
        if isCommitting { return commitScale }
        return max(0.94, CGFloat(1) - (trashProgress * 0.05))
    }

    private var contentRotation: Double {
        if isCommitting { return commitRotation }
        return Double(trashProgress) * 6.0
    }

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            ZStack {
                content
                    .offset(y: dragOffset)
                    .scaleEffect(contentScale)
                    .rotationEffect(.degrees(contentRotation))
                    .opacity(Double(1) - (Double(trashProgress) * 0.08))

                // Trash indicator overlay
                if isDragging && abs(dragOffset) > 24 {
                    trashIndicator
                        .opacity(Double(trashProgress))
                }
            }
            .simultaneousGesture(isEnabled && !isCommitting ? trashGesture(containerHeight: proxy.size.height) : nil)
            .onDisappear {
                if isCommitting {
                    gestureLog("onDisappear while committing, cancelling pending commit task")
                }
                commitTask?.cancel()
                commitTask = nil
                commitScale = 1.0
                commitRotation = 0.0
                impactFeedback = nil
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
                        commitScale = 1.0
                        commitRotation = 0.0
                    }
                    impactFeedback = nil
                    return
                }

                // Notify drag start once
                if !hasNotifiedStart {
                    dragSessionID = Int(Date().timeIntervalSince1970 * 1000) % 1_000_000
                    lastLoggedProgressBucket = -1
                    gestureLog("session=\(dragSessionID) start dy=\(f(dy)) dx=\(f(dx))")
                    let feedback = UIImpactFeedbackGenerator(style: .medium)
                    feedback.prepare()
                    impactFeedback = feedback
                    onDragStart?()
                    hasNotifiedStart = true
                }

                isDragging = true

                // Apply resistance after threshold
                let translation = -dy // positive magnitude for upward drag
                dragOffset = clampedOffset(for: translation)

                // Notify progress for deck reveal effect
                onDragProgress?(trashProgress)
                let progressBucket = Int((trashProgress * 10).rounded(.down))
                if progressBucket != lastLoggedProgressBucket {
                    lastLoggedProgressBucket = progressBucket
                    gestureLog("session=\(dragSessionID) progress=\(f(trashProgress)) dragOffset=\(f(dragOffset)) dy=\(f(dy))")
                }
            }
            .onEnded { value in
                guard !isCommitting else { return }
                let releaseTranslation = max(0, -value.translation.height)
                let predictedTranslation = max(releaseTranslation, -value.predictedEndTranslation.height)
                let projectedOffset = clampedOffset(for: min(predictedTranslation, maxOffset))
                let commitStartOffset = min(dragOffset, projectedOffset)
                let shouldTrash = abs(commitStartOffset) >= trashThreshold
                gestureLog("session=\(dragSessionID) end shouldTrash=\(shouldTrash) dragOffset=\(f(dragOffset)) threshold=\(f(trashThreshold))")

                if shouldTrash {
                    // Complete with a smooth fly-away before committing the state change
                    dragOffset = commitStartOffset
                    let commitProgress = min(1.0, abs(commitStartOffset) / trashThreshold)
                    let startScale = max(0.94, CGFloat(1) - (commitProgress * 0.05))
                    let startRotation = Double(commitProgress) * 6.0
                    isCommitting = true
                    commitScale = startScale
                    commitRotation = startRotation
                    isDragging = false

                    let flyOutOffset = -max(maxOffset, containerHeight + 80)
                    gestureLog("session=\(dragSessionID) commit start flyOutOffset=\(f(flyOutOffset)) containerHeight=\(f(containerHeight))")
                    withAnimation(.timingCurve(0.22, 0.95, 0.30, 1.0, duration: commitDuration)) {
                        dragOffset = flyOutOffset
                        commitScale = 0.02
                        commitRotation = 26.0
                    }
                    impactFeedback?.impactOccurred()
                    impactFeedback = nil
                    DispatchQueue.main.async {
                        onDragProgress?(1.0)
                    }

                    commitTask?.cancel()
                    commitTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64(commitDuration * 1_000_000_000))
                        guard !Task.isCancelled else { return }

                        await MainActor.run {
                            gestureLog("session=\(dragSessionID) commit finish -> onTrash()")
                            onTrash()
                            dragOffset = 0
                            isDragging = false
                            hasNotifiedStart = false
                            isCommitting = false
                            commitScale = 1.0
                            commitRotation = 0.0
                            impactFeedback = nil
                            lastLoggedProgressBucket = -1
                            commitTask = nil
                        }
                    }
                    return
                } else if hasNotifiedStart {
                    // Cancelled - notify parent to hide preview
                    gestureLog("session=\(dragSessionID) cancel")
                    onDragCancel?()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = 0
                        isDragging = false
                        commitScale = 1.0
                        commitRotation = 0.0
                    }
                    impactFeedback = nil
                    hasNotifiedStart = false
                    lastLoggedProgressBucket = -1
                    return
                }

                // Reset state
                dragOffset = 0
                isDragging = false
                hasNotifiedStart = false
                commitScale = 1.0
                commitRotation = 0.0
                impactFeedback = nil
                lastLoggedProgressBucket = -1
            }
    }

    private func clampedOffset(for upwardTranslation: CGFloat) -> CGFloat {
        if upwardTranslation < trashThreshold {
            return -upwardTranslation
        }

        // Rubber-band effect past threshold to keep finger tracking natural.
        let overflow = upwardTranslation - trashThreshold
        return max(-(trashThreshold + (overflow * 0.3)), -maxOffset)
    }

    private func gestureLog(_ message: String) {
#if DEBUG
        print("[SwipeDebug][Gesture] \(message)")
#endif
    }

    private func f(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
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
