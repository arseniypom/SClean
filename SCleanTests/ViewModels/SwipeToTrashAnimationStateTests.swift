//
//  SwipeToTrashAnimationStateTests.swift
//  SCleanTests
//
//  Tests for SwipeToTrashAnimationState
//  Verifies correct ordering of state transitions to prevent visual artifacts
//

import Testing
import Foundation
@testable import SClean

@MainActor
struct SwipeToTrashAnimationStateTests {

    // MARK: - Test Setup

    private func makeState(currentIndex: Int = 0) -> SwipeToTrashAnimationState {
        let state = SwipeToTrashAnimationState(currentIndex: currentIndex)
        state.recordTransitions = true
        return state
    }

    // MARK: - Start Animation Tests

    @Test func startAnimation_setsPreviewAssetID() async throws {
        let state = makeState()

        state.startAnimation(nextAssetID: "photo2")

        #expect(state.previewAssetID == "photo2")
    }

    @Test func startAnimation_setsIsAnimatingTrue() async throws {
        let state = makeState()

        state.startAnimation(nextAssetID: "photo2")

        #expect(state.isAnimating == true)
    }

    @Test func startAnimation_doesNotChangeCurrentIndex() async throws {
        let state = makeState(currentIndex: 0)

        state.startAnimation(nextAssetID: "photo2")

        #expect(state.currentIndex == 0)
    }

    // MARK: - Complete Animation Tests (Critical Ordering)

    @Test func completeAnimation_setsIsAnimatingFalse_beforeChangingIndex() async throws {
        let state = makeState(currentIndex: 0)
        state.startAnimation(nextAssetID: "photo2")
        state.clearTransitionLog() // Clear start transitions, focus on complete

        state.completeAnimation(nextIndex: 1)

        // Verify order: isAnimating=false comes BEFORE currentIndex change
        let animatingFalseIndex = state.transitionLog.firstIndex { $0.0 == "isAnimating=false" }
        let indexChangeIndex = state.transitionLog.firstIndex { $0.0.hasPrefix("currentIndex=") }

        #expect(animatingFalseIndex != nil, "isAnimating=false transition not found")
        #expect(indexChangeIndex != nil, "currentIndex change transition not found")
        #expect(animatingFalseIndex! < indexChangeIndex!, "isAnimating must become false BEFORE currentIndex changes")
    }

    @Test func completeAnimation_clearsPreviewAssetID_beforeChangingIndex() async throws {
        let state = makeState(currentIndex: 0)
        state.startAnimation(nextAssetID: "photo2")
        state.clearTransitionLog()

        state.completeAnimation(nextIndex: 1)

        // Verify order: previewAssetID=nil comes BEFORE currentIndex change
        let previewNilIndex = state.transitionLog.firstIndex { $0.0 == "previewAssetID=nil" }
        let indexChangeIndex = state.transitionLog.firstIndex { $0.0.hasPrefix("currentIndex=") }

        #expect(previewNilIndex != nil, "previewAssetID=nil transition not found")
        #expect(indexChangeIndex != nil, "currentIndex change transition not found")
        #expect(previewNilIndex! < indexChangeIndex!, "previewAssetID must become nil BEFORE currentIndex changes")
    }

    @Test func completeAnimation_finalState() async throws {
        let state = makeState(currentIndex: 0)
        state.startAnimation(nextAssetID: "photo2")

        state.completeAnimation(nextIndex: 1)

        #expect(state.isAnimating == false)
        #expect(state.previewAssetID == nil)
        #expect(state.currentIndex == 1)
    }

    // MARK: - Reset Tests

    @Test func reset_clearsAnimationState() async throws {
        let state = makeState(currentIndex: 0)
        state.startAnimation(nextAssetID: "photo2")

        state.reset()

        #expect(state.isAnimating == false)
        #expect(state.previewAssetID == nil)
        #expect(state.currentIndex == 0) // Index unchanged
    }

    // MARK: - Full Cycle Tests

    @Test func fullCycle_multipleSwipes() async throws {
        let state = makeState(currentIndex: 0)

        // First swipe
        state.startAnimation(nextAssetID: "photo2")
        #expect(state.isAnimating == true)
        #expect(state.previewAssetID == "photo2")

        state.completeAnimation(nextIndex: 1)
        #expect(state.isAnimating == false)
        #expect(state.currentIndex == 1)

        // Second swipe
        state.startAnimation(nextAssetID: "photo3")
        #expect(state.isAnimating == true)
        #expect(state.previewAssetID == "photo3")

        state.completeAnimation(nextIndex: 2)
        #expect(state.isAnimating == false)
        #expect(state.currentIndex == 2)
    }

    @Test func transitionOrder_fullCycle() async throws {
        let state = makeState(currentIndex: 0)

        state.startAnimation(nextAssetID: "photo2")
        state.completeAnimation(nextIndex: 1)

        // Verify complete transition log order
        let transitionNames = state.transitionLog.map { $0.0 }

        // Expected order:
        // 1. startAnimation
        // 2. previewAssetID=photo2
        // 3. isAnimating=true
        // 4. isAnimating=false
        // 5. previewAssetID=nil
        // 6. currentIndex=1

        let isAnimatingFalseIdx = transitionNames.firstIndex(of: "isAnimating=false")!
        let previewNilIdx = transitionNames.firstIndex(of: "previewAssetID=nil")!
        let currentIndexIdx = transitionNames.firstIndex(of: "currentIndex=1")!

        // Key ordering: both isAnimating=false and previewAssetID=nil must come BEFORE currentIndex
        #expect(isAnimatingFalseIdx < currentIndexIdx)
        #expect(previewNilIdx < currentIndexIdx)
    }
}
