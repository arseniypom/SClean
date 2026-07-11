//
//  DeckPagerView.swift
//  SClean
//
//  Custom pager for the media viewer with a single unified gesture space:
//  horizontal pan pages between assets, upward pan trashes the current one
//  with an interactive card-stack reveal of the next asset behind it.
//
//  Replaces the previous TabView + simultaneous-gesture approach. On a trash
//  commit the deck mutates synchronously and the card that was behind IS the
//  real current page (identity-stable by asset.id) — there is no handoff
//  between two systems, which is what eliminated the old "jump" bugs.
//

import SwiftUI

struct DeckPagerView: View {
    @ObservedObject var deckModel: ViewerDeckModel

    /// Called after a trash commit with the removed asset, for the undo toast.
    var onTrashCommitted: ((YearAsset) -> Void)?

    // MARK: - Animation Tuning

    private enum PagerAnimation {
        /// Horizontal page settle — fast, essentially no overshoot (~0.3s)
        static func pageSettle(initialVelocity: CGFloat) -> Animation {
            .interpolatingSpring(mass: 1, stiffness: 380, damping: 38, initialVelocity: initialVelocity)
        }
        /// Cancelled trash drag springs back
        static let trashCancel: Animation = .spring(response: 0.32, dampingFraction: 0.86)
        /// Behind card scales up to full size after a commit
        static let reveal: Animation = .spring(response: 0.42, dampingFraction: 0.85)
        /// The trashed card flies off the top of the screen
        static func flyOut(initialVelocity: CGFloat) -> Animation {
            .interpolatingSpring(stiffness: 200, damping: 26, initialVelocity: initialVelocity)
        }
    }

    /// Photos-style visual separator between pages
    private static let pageGap: CGFloat = 30
    /// Maximum tap duration for edge-tap navigation
    private static let tapMaxDuration: TimeInterval = 0.25
    /// Haptic hysteresis around the trash threshold (points)
    private static let thresholdHysteresis: CGFloat = 3
    /// Reused for all per-frame and compensation writes that must not animate
    private static let noAnimation: Transaction = {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }()

    // MARK: - Hot-Path Gesture State
    // All per-frame values are local @State so the toolbar/counter in the
    // parent never re-render mid-drag; ViewerDeckModel publishes only on
    // settle/commit.

    @State private var gesture = PagerGestureState()
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var trashProgress: CGFloat = 0
    @State private var pagingBaseX: CGFloat = 0
    @State private var trashTopID: String?
    @State private var trashBehindID: String?
    @State private var flyingCards: [FlyingCard] = []
    @State private var hasCrossedThreshold = false
    /// Frames left of eased writes after re-grabbing a card mid-cancel-spring,
    /// so the card catches up to the finger instead of teleporting
    @State private var trashRegrabBlendFrames = 0
    @State private var impactGenerator: UIImpactFeedbackGenerator?
    @State private var touchStartDate: Date?
    @State private var presentedOffset = PresentedOffset()

    /// Snapshot of a trashed card while it flies off-screen. Pure decoration:
    /// the deck has already been mutated when this exists.
    private struct FlyingCard: Identifiable, Equatable {
        let id: String
        let image: UIImage?
        let startOffsetY: CGFloat
        let startScale: CGFloat
        let startRotation: Double
        let startOpacity: Double
        var progress: CGFloat
    }

    /// Mirrors the presented (mid-animation) horizontal offset without
    /// invalidating the view, so a grab during a settle animation can
    /// continue from where the strip visually is.
    private final class PresentedOffset {
        var value: CGFloat = 0
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                pagesContainer(size: size)

                if gesture.axis == .trashing && dragY < -24 {
                    trashIndicator
                        .zIndex(5)
                }

                ForEach(flyingCards) { card in
                    flyingCardView(card, size: size)
                        .zIndex(10)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        handleDragChanged(value, size: size)
                    }
                    .onEnded { value in
                        handleDragEnded(value, size: size)
                    }
            )
        }
        .coordinateSpace(name: "deckPagerSpace")
        .onDisappear {
            // A drag can be cancelled without onEnded (navigation push,
            // system interruption) — never leave the pager mid-gesture.
            resetGestureState()
        }
    }

    /// Snap all gesture-driven state back to rest without animation.
    private func resetGestureState() {
        gesture.reset()
        touchStartDate = nil
        pagingBaseX = 0
        hasCrossedThreshold = false
        impactGenerator = nil
        withTransaction(Self.noAnimation) {
            dragX = 0
            dragY = 0
            trashProgress = 0
            trashTopID = nil
            trashBehindID = nil
            flyingCards.removeAll()
        }
    }

    // MARK: - Pages

    private func pagesContainer(size: CGSize) -> some View {
        let currentIndex = deckModel.currentIndex
        let window = visibleWindow(around: currentIndex)

        return ZStack {
            ForEach(window, id: \.asset.id) { entry in
                pageCard(index: entry.index, asset: entry.asset, size: size)
            }
        }
        // background is attached before .offset so the mirror moves with the
        // strip and reads the presented (animated) offset
        .background(offsetMirror)
        .offset(x: dragX)
    }

    private func visibleWindow(around currentIndex: Int) -> [(index: Int, asset: YearAsset)] {
        let deck = deckModel.deck
        guard !deck.isEmpty else { return [] }
        let lower = max(0, currentIndex - 1)
        let upper = min(deck.count - 1, currentIndex + 1)
        return (lower...upper).map { (index: $0, asset: deck[$0]) }
    }

    @ViewBuilder
    private func pageCard(index: Int, asset: YearAsset, size: CGSize) -> some View {
        let currentIndex = deckModel.currentIndex
        let isCurrent = index == currentIndex
        let isTopCard = asset.id == trashTopID
        let isBehindCard = asset.id == trashBehindID
        // During a trash interaction or reveal, side neighbors are never
        // legitimately visible (they sit 30pt offscreen at best) — hide them
        // so no residual strip offset can ever expose a sliver of them.
        let isHiddenSideCard = (trashTopID != nil || trashBehindID != nil) && !isTopCard && !isBehindCard
        let baseX = CGFloat(index - currentIndex) * (size.width + Self.pageGap)

        MediaPageView(asset: asset, isCurrentPage: isCurrent)
            .frame(width: size.width, height: size.height)
            .overlay {
                // Dim veil on the behind card; lifts as the reveal progresses
                if isBehindCard {
                    Color.black
                        .opacity(PagerGestureState.behindCardDim(progress: trashProgress))
                }
            }
            .scaleEffect(cardScale(isTopCard: isTopCard, isBehindCard: isBehindCard))
            .rotationEffect(.degrees(isTopCard ? PagerGestureState.topCardRotationDegrees(progress: trashProgress) : 0))
            .opacity(isHiddenSideCard ? 0 : (isTopCard ? PagerGestureState.topCardOpacity(progress: trashProgress) : 1))
            .offset(
                x: isBehindCard || isTopCard ? 0 : baseX,
                y: isTopCard ? dragY : 0
            )
            .zIndex(isTopCard ? 2 : (isBehindCard ? 1 : 0))
            .allowsHitTesting(isCurrent)
            .accessibilityIdentifier(isCurrent ? "currentPhotoView" : "photoView_\(index)")
    }

    private func cardScale(isTopCard: Bool, isBehindCard: Bool) -> CGFloat {
        if isTopCard {
            return PagerGestureState.topCardScale(progress: trashProgress)
        }
        if isBehindCard {
            return PagerGestureState.behindCardScale(progress: trashProgress)
        }
        return 1
    }

    /// Reads the presented (animated) offset of the page strip into a plain
    /// box — no view invalidation — so a new touch mid-settle can pick up
    /// exactly where the animation currently is.
    private var offsetMirror: some View {
        GeometryReader { proxy -> Color in
            presentedOffset.value = proxy.frame(in: .named("deckPagerSpace")).minX
            return Color.clear
        }
    }

    // MARK: - Trash Indicator

    private var trashIndicator: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 72, height: 72)
                    .scaleEffect(0.8 + trashProgress * 0.2)

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
        .opacity(trashProgress)
        .allowsHitTesting(false)
    }

    // MARK: - Flying Card

    private func flyingCardView(_ card: FlyingCard, size: CGSize) -> some View {
        Group {
            if let image = card.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(lerp(card.startScale, 0.3, card.progress))
        .rotationEffect(.degrees(lerp(card.startRotation, 20, Double(card.progress))))
        .offset(y: lerp(card.startOffsetY, -(size.height * 0.9), card.progress))
        .opacity(lerp(card.startOpacity, 0.4, Double(card.progress)))
        .allowsHitTesting(false)
    }

    private func lerp(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    private func lerp(_ from: Double, _ to: Double, _ progress: Double) -> Double {
        from + (to - from) * progress
    }

    // MARK: - Gesture Handling

    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
        if touchStartDate == nil {
            touchStartDate = value.time
            // A previous drag that was cancelled by the system never got
            // onEnded — recover before treating this as a fresh gesture.
            if gesture.axis != .undecided {
                resetGestureState()
                touchStartDate = value.time
            }
        }

        let previousAxis = gesture.axis
        let axis = gesture.update(translation: value.translation)
        if axis != previousAxis {
            axisDidLock(axis, size: size)
        }

        // Per-frame writes must never pick up implicit animations — nothing
        // is allowed to fight the finger.
        let transaction = Self.noAnimation

        switch axis {
        case .undecided:
            break

        case .paging:
            let pageSpan = size.width + Self.pageGap
            let effective = pagingBaseX + value.translation.width
            let clamped = min(max(effective, -pageSpan), pageSpan)
            let offset = PagerGestureState.horizontalOffset(
                translationX: clamped,
                pageWidth: size.width,
                isAtFirst: deckModel.currentIndex == 0,
                isAtLast: deckModel.currentIndex >= deckModel.deck.count - 1
            )
            withTransaction(transaction) {
                dragX = offset
            }

        case .trashing:
            let upward = -value.translation.height
            let newDragY = PagerGestureState.trashOffset(forUpwardTranslation: upward)
            let newProgress = PagerGestureState.trashProgress(forUpwardTranslation: upward)
            if trashRegrabBlendFrames > 0 {
                // Card was caught mid-cancel-spring: ease toward the finger
                // for a few frames instead of snapping to the new translation
                trashRegrabBlendFrames -= 1
                withAnimation(.easeOut(duration: 0.12)) {
                    dragY = newDragY
                    trashProgress = newProgress
                }
            } else {
                withTransaction(transaction) {
                    dragY = newDragY
                    trashProgress = newProgress
                }
            }
            updateThresholdHaptics(upward: upward)
        }
    }

    private func axisDidLock(_ axis: PagerGestureState.Axis, size: CGSize) {
        switch axis {
        case .undecided:
            break

        case .paging:
            // Continue from the presented position if a settle is in flight.
            // Clamped: a stale mirror value must never displace the strip
            // beyond one page span.
            let pageSpan = size.width + Self.pageGap
            pagingBaseX = min(max(presentedOffset.value, -pageSpan), pageSpan)
            clearRevealResidue()

        case .trashing:
            guard let current = deckModel.currentAsset else {
                gesture.reset()
                return
            }

            // A page-settle spring may still be moving the strip; bring it
            // home fast so the stack is centered for the whole trash
            // interaction (residual dragX < -30 exposed the next-next card
            // as a sliver on the right edge).
            if dragX != 0 {
                withAnimation(.easeOut(duration: 0.15)) {
                    dragX = 0
                }
            }

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            impactGenerator = generator
            hasCrossedThreshold = false

            // Re-grabbing the same card mid-cancel-spring: blend to the finger
            trashRegrabBlendFrames = trashTopID == current.id ? 6 : 0

            trashTopID = current.id
            trashBehindID = deckModel.predictedTrashSuccessor?.id
        }
    }

    /// After a commit, the reveal animation may still be running when the user
    /// starts paging. The revealed card must stop being pinned to center
    /// (stale trashBehindID would render it OVER the newly navigated page).
    private func clearRevealResidue() {
        guard trashTopID == nil, trashBehindID != nil else { return }
        trashBehindID = nil
        withTransaction(Self.noAnimation) {
            trashProgress = 0
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, size: CGSize) {
        let axis = gesture.axis
        gesture.reset()
        let startDate = touchStartDate
        touchStartDate = nil

        switch axis {
        case .undecided:
            handleTap(value, size: size, startDate: startDate)

        case .paging:
            endPaging(value, size: size)

        case .trashing:
            endTrashing(value, size: size)
        }
    }

    // MARK: - Paging End

    private func endPaging(_ value: DragGesture.Value, size: CGSize) {
        let effective = pagingBaseX + value.translation.width
        let velocityX = value.velocity.width
        let pageSpan = size.width + Self.pageGap
        pagingBaseX = 0

        let action = PagerGestureState.horizontalEndAction(
            translationX: effective,
            velocityX: velocityX,
            pageWidth: size.width,
            isAtFirst: deckModel.currentIndex == 0,
            isAtLast: deckModel.currentIndex >= deckModel.deck.count - 1
        )

        // The index change and the dragX compensation cancel out visually, so
        // ALL motion lives in the animated dragX → 0. This keeps the presented
        // offset in one property, which makes mid-settle grabs seamless.
        withTransaction(Self.noAnimation) {
            switch action {
            case .advance:
                deckModel.goNext()
                dragX += pageSpan
            case .retreat:
                deckModel.goPrevious()
                dragX -= pageSpan
            case .settle:
                break
            }
        }

        // Normalized initial velocity for the spring: the finger's velocity
        // over the remaining travel, signed relative to the return motion
        let remaining = dragX == 0 ? 1 : -dragX
        let initialVelocity = min(max(velocityX / remaining, -25), 25)

        withAnimation(PagerAnimation.pageSettle(initialVelocity: initialVelocity)) {
            dragX = 0
        }
    }

    // MARK: - Trash End

    private func endTrashing(_ value: DragGesture.Value, size: CGSize) {
        let upward = -value.translation.height
        let action = PagerGestureState.trashEndAction(
            upwardTranslation: upward,
            velocityY: value.velocity.height
        )

        switch action {
        case .commit:
            commitTrash(velocityY: value.velocity.height, size: size)

        case .cancel:
            hasCrossedThreshold = false
            impactGenerator = nil
            withAnimation(PagerAnimation.trashCancel, completionCriteria: .logicallyComplete) {
                dragY = 0
                trashProgress = 0
            } completion: {
                // Skip cleanup if a new trash drag took over mid-spring
                if gesture.axis != .trashing {
                    trashTopID = nil
                    trashBehindID = nil
                }
            }
        }
    }

    /// The core commit sequence — everything happens in one main-actor turn:
    /// snapshot the flying card, mutate the deck synchronously (the behind
    /// card IS the current page from this moment), then run the reveal and
    /// fly-out animations as pure decoration on top of final state.
    private func commitTrash(velocityY: CGFloat, size: CGSize) {
        guard let current = deckModel.currentAsset else { return }

        impactGenerator?.impactOccurred()
        impactGenerator = nil
        hasCrossedThreshold = false

        // 1. Snapshot the flying card. Videos get their poster from the same
        //    image pipeline (prefetch warms it for the whole window), so this
        //    is media-type agnostic.
        let snapshotImage = FullImageLoader.shared.getDisplayableImage(for: current.id)
        let commitProgress = trashProgress
        let startOffsetY = dragY
        let card = FlyingCard(
            id: current.id,
            image: snapshotImage,
            startOffsetY: startOffsetY,
            startScale: PagerGestureState.topCardScale(progress: commitProgress),
            startRotation: PagerGestureState.topCardRotationDegrees(progress: commitProgress),
            startOpacity: PagerGestureState.topCardOpacity(progress: commitProgress),
            progress: 0
        )

        // 2. Mutate state synchronously — counter, badge and deck update now
        guard let removed = deckModel.trashCurrent() else { return }
        trashTopID = nil

        withTransaction(Self.noAnimation) {
            dragY = 0
            flyingCards.append(card)
        }

        // 3. Reveal: the behind card (now the real current page) scales to
        //    full size and its dim lifts, spring-settled. Any residual strip
        //    offset (e.g. trash started mid page-settle) resolves with it.
        withAnimation(PagerAnimation.reveal, completionCriteria: .logicallyComplete) {
            trashProgress = 1
            dragX = 0
        } completion: {
            // Skip cleanup if a new trash drag took over mid-reveal
            if gesture.axis != .trashing {
                trashBehindID = nil
                withTransaction(Self.noAnimation) {
                    trashProgress = 0
                }
            }
        }

        // 4. Fly-out, concurrently, with the gesture's velocity carried in
        let flyDistance = max(size.height * 0.9 + startOffsetY, 100)
        let initialVelocity = min(abs(velocityY) / flyDistance, 25)
        let cardID = card.id
        withAnimation(PagerAnimation.flyOut(initialVelocity: initialVelocity), completionCriteria: .logicallyComplete) {
            if let index = flyingCards.firstIndex(where: { $0.id == cardID }) {
                flyingCards[index].progress = 1
            }
        } completion: {
            flyingCards.removeAll { $0.id == cardID }
        }

        // 5. Hand the removed asset to the parent for the undo toast
        onTrashCommitted?(removed)
    }

    // MARK: - Tap Navigation

    private func handleTap(_ value: DragGesture.Value, size: CGSize, startDate: Date?) {
        let travel = (value.translation.width * value.translation.width
            + value.translation.height * value.translation.height).squareRoot()
        guard travel < PagerGestureState.axisLockDistance else { return }
        if let startDate, value.time.timeIntervalSince(startDate) > Self.tapMaxDuration {
            return
        }

        let edgeZone = size.width * 0.2
        let pageSpan = size.width + Self.pageGap
        clearRevealResidue()

        if value.startLocation.x < edgeZone {
            guard deckModel.currentIndex > 0 else { return }
            withTransaction(Self.noAnimation) {
                deckModel.goPrevious()
                dragX -= pageSpan
            }
        } else if value.startLocation.x > size.width - edgeZone {
            guard deckModel.currentIndex < deckModel.deck.count - 1 else { return }
            withTransaction(Self.noAnimation) {
                deckModel.goNext()
                dragX += pageSpan
            }
        } else {
            // Center taps are left to the page content (video play/pause)
            return
        }

        withAnimation(PagerAnimation.pageSettle(initialVelocity: 0)) {
            dragX = 0
        }
    }

    // MARK: - Haptics

    private func updateThresholdHaptics(upward: CGFloat) {
        if !hasCrossedThreshold && upward >= PagerGestureState.trashThreshold {
            hasCrossedThreshold = true
            impactGenerator?.impactOccurred(intensity: 0.7)
            impactGenerator?.prepare()
        } else if hasCrossedThreshold
                    && upward < PagerGestureState.trashThreshold - Self.thresholdHysteresis {
            hasCrossedThreshold = false
            impactGenerator?.impactOccurred(intensity: 0.4)
            impactGenerator?.prepare()
        }
    }

}

// MARK: - Preview

#Preview {
    let assets = [
        YearAsset(id: "1", creationDate: Date(), mediaType: .photo),
        YearAsset(id: "2", creationDate: Date(), mediaType: .photo),
        YearAsset(id: "3", creationDate: Date(), mediaType: .video, duration: 12),
    ]

    return ZStack {
        Color.black.ignoresSafeArea()
        DeckPagerView(
            deckModel: ViewerDeckModel(assets: assets, startIndex: 0)
        )
    }
}
