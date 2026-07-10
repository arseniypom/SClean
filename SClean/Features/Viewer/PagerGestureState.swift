//
//  PagerGestureState.swift
//  SClean
//
//  Pure gesture math for the viewer's deck pager: axis locking,
//  rubber-band curves, and end-of-gesture decisions. No SwiftUI —
//  fully unit-testable and gesture-source-agnostic.
//

import Foundation

nonisolated struct PagerGestureState: Equatable, Sendable {

    // MARK: - Types

    enum Axis: Equatable, Sendable {
        /// Touch is down but travel is under the lock distance — nothing moves yet
        case undecided
        /// Locked to horizontal paging for the rest of the gesture
        case paging
        /// Locked to the vertical swipe-up-to-trash for the rest of the gesture
        case trashing
    }

    enum HorizontalEnd: Equatable, Sendable {
        case advance
        case retreat
        case settle
    }

    enum TrashEnd: Equatable, Sendable {
        case commit
        case cancel
    }

    // MARK: - Tuning Constants

    /// Travel before the gesture locks to an axis (Photos-style slop)
    static let axisLockDistance: CGFloat = 10
    /// Upward distance at which release commits the trash
    static let trashThreshold: CGFloat = 90
    /// Hard cap on the visual upward offset
    static let trashMaxOffset: CGFloat = 220
    /// Resistance factor past the trash threshold
    static let trashRubberBandFactor: CGFloat = 0.3
    /// Fraction of page width to commit a page change by distance
    static let pagingDistanceFraction: CGFloat = 1.0 / 3.0
    /// Horizontal velocity (pt/s) to commit a page change by flick
    static let pagingFlickVelocity: CGFloat = 250
    /// Upward velocity (pt/s) to commit a trash by flick
    static let trashFlickVelocity: CGFloat = 600
    /// Minimum upward travel for a flick commit (prevents accidental micro-flicks)
    static let trashFlickMinDistance: CGFloat = 40
    /// Horizontal rubber-band range at deck ends, as a fraction of page width
    static let edgeRubberBandFraction: CGFloat = 0.35

    // MARK: - Axis Locking

    private(set) var axis: Axis = .undecided

    /// Feed the current translation; locks the axis once travel exceeds the
    /// slop distance. The axis stays locked until reset().
    @discardableResult
    mutating func update(translation: CGSize) -> Axis {
        guard axis == .undecided else { return axis }

        let dx = translation.width
        let dy = translation.height
        guard (dx * dx + dy * dy).squareRoot() >= Self.axisLockDistance else {
            return .undecided
        }

        // Upward-dominant → trash; horizontal or downward-dominant → paging
        // (downward maps to paging so it stays a harmless wiggle).
        if dy < 0 && -dy > abs(dx) {
            axis = .trashing
        } else {
            axis = .paging
        }
        return axis
    }

    mutating func reset() {
        axis = .undecided
    }

    // MARK: - Horizontal Paging Math

    /// Asymptotic rubber band (UIScrollView-style) for dragging past deck ends.
    /// Monotonic in `distance`, approaches `limit` but never reaches it.
    static func rubberBand(_ distance: CGFloat, limit: CGFloat) -> CGFloat {
        guard distance > 0, limit > 0 else { return 0 }
        return limit * (1 - 1 / (distance * 0.55 / limit + 1))
    }

    /// Visual horizontal offset for a raw drag translation, applying the
    /// rubber band when pulling past the first or last page.
    static func horizontalOffset(
        translationX: CGFloat,
        pageWidth: CGFloat,
        isAtFirst: Bool,
        isAtLast: Bool
    ) -> CGFloat {
        let limit = pageWidth * edgeRubberBandFraction
        if translationX > 0 && isAtFirst {
            return rubberBand(translationX, limit: limit)
        }
        if translationX < 0 && isAtLast {
            return -rubberBand(-translationX, limit: limit)
        }
        return translationX
    }

    /// Decide what a released horizontal drag does. A fast flick wins over
    /// distance; a flick against the drag direction settles back.
    static func horizontalEndAction(
        translationX: CGFloat,
        velocityX: CGFloat,
        pageWidth: CGFloat,
        isAtFirst: Bool,
        isAtLast: Bool
    ) -> HorizontalEnd {
        let direction: CGFloat
        if abs(velocityX) >= pagingFlickVelocity {
            // Flick decides — but only in the direction the content was dragged
            guard velocityX.sign == translationX.sign, translationX != 0 else {
                return .settle
            }
            direction = velocityX < 0 ? -1 : 1
        } else if abs(translationX) > pageWidth * pagingDistanceFraction {
            direction = translationX < 0 ? -1 : 1
        } else {
            return .settle
        }

        if direction < 0 {
            return isAtLast ? .settle : .advance
        } else {
            return isAtFirst ? .settle : .retreat
        }
    }

    // MARK: - Trash Drag Math

    /// Visual (negative) vertical offset for an upward translation:
    /// 1:1 to the threshold, then rubber-banded, hard-capped.
    static func trashOffset(forUpwardTranslation translation: CGFloat) -> CGFloat {
        guard translation > 0 else { return 0 }
        if translation < trashThreshold {
            return -translation
        }
        let overflow = translation - trashThreshold
        return max(-(trashThreshold + overflow * trashRubberBandFactor), -trashMaxOffset)
    }

    /// 0...1 progress toward the trash threshold
    static func trashProgress(forUpwardTranslation translation: CGFloat) -> CGFloat {
        guard translation > 0 else { return 0 }
        return min(1, translation / trashThreshold)
    }

    /// Decide what a released trash drag does. Commit on distance, or on a
    /// fast upward flick past the minimum travel floor.
    static func trashEndAction(
        upwardTranslation: CGFloat,
        velocityY: CGFloat
    ) -> TrashEnd {
        if upwardTranslation >= trashThreshold {
            return .commit
        }
        if velocityY < -trashFlickVelocity && upwardTranslation >= trashFlickMinDistance {
            return .commit
        }
        return .cancel
    }

    // MARK: - Stack Reveal Mapping

    /// Scale of the card behind the current one while trash-dragging:
    /// 0.90 at rest, easing to 1.0 as progress reaches 1.
    static func behindCardScale(progress: CGFloat) -> CGFloat {
        0.90 + 0.10 * easeOutCubic(min(max(progress, 0), 1))
    }

    /// Dim overlay opacity on the behind card: fully hidden (1.0) at rest so
    /// entering/leaving the trash drag is seamless, brightening quickly with
    /// progress as the card is revealed.
    static func behindCardDim(progress: CGFloat) -> CGFloat {
        1 - easeOutCubic(min(max(progress, 0), 1))
    }

    static func easeOutCubic(_ x: CGFloat) -> CGFloat {
        let inverted = 1 - x
        return 1 - inverted * inverted * inverted
    }
}
