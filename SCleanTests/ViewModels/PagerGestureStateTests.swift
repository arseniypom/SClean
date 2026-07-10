//
//  PagerGestureStateTests.swift
//  SCleanTests
//
//  Tests for the pager's pure gesture math: axis locking, rubber-band
//  curves, and end-of-gesture decisions.
//

import Testing
import Foundation
@testable import SClean

struct PagerGestureStateTests {

    private let pageWidth: CGFloat = 400

    // MARK: - Axis Locking

    @Test func axisLock_staysUndecidedUnderSlopDistance() async throws {
        var state = PagerGestureState()

        #expect(state.update(translation: CGSize(width: 5, height: -5)) == .undecided)
        #expect(state.axis == .undecided)
    }

    @Test func axisLock_pureHorizontalLocksPaging() async throws {
        var state = PagerGestureState()

        #expect(state.update(translation: CGSize(width: 20, height: 0)) == .paging)
    }

    @Test func axisLock_pureUpwardLocksTrashing() async throws {
        var state = PagerGestureState()

        #expect(state.update(translation: CGSize(width: 0, height: -20)) == .trashing)
    }

    @Test func axisLock_downwardDominantLocksPaging() async throws {
        var state = PagerGestureState()

        #expect(state.update(translation: CGSize(width: 2, height: 30)) == .paging)
    }

    @Test func axisLock_diagonalFavorsPagingAtExactly45Degrees() async throws {
        var state = PagerGestureState()

        // -dy == |dx| → not strictly upward-dominant → paging
        #expect(state.update(translation: CGSize(width: 12, height: -12)) == .paging)
    }

    @Test func axisLock_upwardDominantDiagonalLocksTrashing() async throws {
        var state = PagerGestureState()

        #expect(state.update(translation: CGSize(width: 8, height: -20)) == .trashing)
    }

    @Test func axisLock_staysLockedForRestOfGesture() async throws {
        var state = PagerGestureState()
        state.update(translation: CGSize(width: 0, height: -20))

        // Later horizontal movement does not re-decide the axis
        #expect(state.update(translation: CGSize(width: 100, height: -20)) == .trashing)

        state.reset()
        #expect(state.axis == .undecided)
    }

    // MARK: - Rubber Band

    @Test func rubberBand_isMonotonicAndBounded() async throws {
        let limit: CGFloat = 140
        var previous: CGFloat = -1
        for distance in stride(from: CGFloat(0), through: 2000, by: 50) {
            let value = PagerGestureState.rubberBand(distance, limit: limit)
            #expect(value >= previous)
            #expect(value < limit)
            previous = value
        }
    }

    @Test func rubberBand_zeroAtZeroDistance() async throws {
        #expect(PagerGestureState.rubberBand(0, limit: 140) == 0)
    }

    @Test func horizontalOffset_tracksOneToOneInsideDeck() async throws {
        let offset = PagerGestureState.horizontalOffset(
            translationX: -120, pageWidth: pageWidth, isAtFirst: false, isAtLast: false
        )
        #expect(offset == -120)
    }

    @Test func horizontalOffset_rubberBandsPastEnds() async throws {
        let pullingRightAtFirst = PagerGestureState.horizontalOffset(
            translationX: 200, pageWidth: pageWidth, isAtFirst: true, isAtLast: false
        )
        #expect(pullingRightAtFirst > 0)
        #expect(pullingRightAtFirst < 200)
        #expect(pullingRightAtFirst < pageWidth * PagerGestureState.edgeRubberBandFraction)

        let pullingLeftAtLast = PagerGestureState.horizontalOffset(
            translationX: -200, pageWidth: pageWidth, isAtFirst: false, isAtLast: true
        )
        #expect(pullingLeftAtLast < 0)
        #expect(pullingLeftAtLast > -200)
    }

    // MARK: - Horizontal End Decisions

    @Test func horizontalEnd_settlesUnderDistanceAndVelocity() async throws {
        let action = PagerGestureState.horizontalEndAction(
            translationX: -50, velocityX: -100,
            pageWidth: pageWidth, isAtFirst: false, isAtLast: false
        )
        #expect(action == .settle)
    }

    @Test func horizontalEnd_advancesOnDistance() async throws {
        let action = PagerGestureState.horizontalEndAction(
            translationX: -150, velocityX: 0,
            pageWidth: pageWidth, isAtFirst: false, isAtLast: false
        )
        #expect(action == .advance)
    }

    @Test func horizontalEnd_retreatsOnDistance() async throws {
        let action = PagerGestureState.horizontalEndAction(
            translationX: 150, velocityX: 0,
            pageWidth: pageWidth, isAtFirst: false, isAtLast: false
        )
        #expect(action == .retreat)
    }

    @Test func horizontalEnd_advancesOnFlickBelowDistanceThreshold() async throws {
        let action = PagerGestureState.horizontalEndAction(
            translationX: -40, velocityX: -800,
            pageWidth: pageWidth, isAtFirst: false, isAtLast: false
        )
        #expect(action == .advance)
    }

    @Test func horizontalEnd_flickAgainstDragDirectionSettles() async throws {
        // Dragged far left, then flicked right → user changed their mind
        let action = PagerGestureState.horizontalEndAction(
            translationX: -200, velocityX: 900,
            pageWidth: pageWidth, isAtFirst: false, isAtLast: false
        )
        #expect(action == .settle)
    }

    @Test func horizontalEnd_suppressedAtDeckEnds() async throws {
        let atLast = PagerGestureState.horizontalEndAction(
            translationX: -300, velocityX: -900,
            pageWidth: pageWidth, isAtFirst: false, isAtLast: true
        )
        #expect(atLast == .settle)

        let atFirst = PagerGestureState.horizontalEndAction(
            translationX: 300, velocityX: 900,
            pageWidth: pageWidth, isAtFirst: true, isAtLast: false
        )
        #expect(atFirst == .settle)
    }

    // MARK: - Trash Drag Math

    @Test func trashOffset_tracksOneToOneBelowThreshold() async throws {
        #expect(PagerGestureState.trashOffset(forUpwardTranslation: 60) == -60)
    }

    @Test func trashOffset_rubberBandsPastThresholdAndCaps() async throws {
        let justPast = PagerGestureState.trashOffset(forUpwardTranslation: 100)
        #expect(justPast == -(90 + 10 * 0.3))

        let extreme = PagerGestureState.trashOffset(forUpwardTranslation: 5000)
        #expect(extreme == -PagerGestureState.trashMaxOffset)
    }

    @Test func trashProgress_clampsToOne() async throws {
        #expect(PagerGestureState.trashProgress(forUpwardTranslation: 45) == 0.5)
        #expect(PagerGestureState.trashProgress(forUpwardTranslation: 90) == 1.0)
        #expect(PagerGestureState.trashProgress(forUpwardTranslation: 500) == 1.0)
        #expect(PagerGestureState.trashProgress(forUpwardTranslation: -20) == 0)
    }

    // MARK: - Trash End Decisions

    @Test func trashEnd_commitsAtThresholdDistance() async throws {
        #expect(PagerGestureState.trashEndAction(upwardTranslation: 90, velocityY: 0) == .commit)
    }

    @Test func trashEnd_cancelsBelowThresholdWithoutFlick() async throws {
        #expect(PagerGestureState.trashEndAction(upwardTranslation: 80, velocityY: -300) == .cancel)
    }

    @Test func trashEnd_commitsOnFastFlickPastMinimumTravel() async throws {
        #expect(PagerGestureState.trashEndAction(upwardTranslation: 50, velocityY: -900) == .commit)
    }

    @Test func trashEnd_microFlickBelowTravelFloorCancels() async throws {
        #expect(PagerGestureState.trashEndAction(upwardTranslation: 20, velocityY: -2000) == .cancel)
    }

    @Test func trashEnd_downwardVelocityNeverFlickCommits() async throws {
        #expect(PagerGestureState.trashEndAction(upwardTranslation: 60, velocityY: 900) == .cancel)
    }

    // MARK: - Stack Reveal Mapping

    @Test func behindCard_restingAndFullProgressValues() async throws {
        #expect(PagerGestureState.behindCardScale(progress: 0) == 0.90)
        #expect(abs(PagerGestureState.behindCardScale(progress: 1) - 1.0) < 0.0001)
        // Fully hidden at rest so the card can enter/leave the stack seamlessly
        #expect(PagerGestureState.behindCardDim(progress: 0) == 1)
        #expect(PagerGestureState.behindCardDim(progress: 1) == 0)
    }

    @Test func behindCardScale_isMonotonic() async throws {
        var previous: CGFloat = 0
        for step in stride(from: CGFloat(0), through: 1, by: 0.1) {
            let scale = PagerGestureState.behindCardScale(progress: step)
            #expect(scale >= previous)
            previous = scale
        }
    }
}
