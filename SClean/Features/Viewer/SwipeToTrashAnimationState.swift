//
//  SwipeToTrashAnimationState.swift
//  SClean
//
//  Testable state machine for swipe-to-trash animation
//  Ensures correct ordering of state transitions to prevent visual artifacts
//

import SwiftUI
import Combine

/// Manages the animation state for swipe-to-trash transitions.
///
/// Key invariant: When completing animation, `isAnimating` must become `false`
/// BEFORE `currentIndex` changes. This prevents the preview layer from showing
/// the wrong photo during the transition.
@MainActor
final class SwipeToTrashAnimationState: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isAnimating = false
    @Published private(set) var previewAssetID: String?
    @Published private(set) var currentIndex: Int

    // MARK: - Testing Support

    /// Log of state transitions for testing. Each entry is (transitionName, timestamp).
    /// Only populated when `recordTransitions` is true.
    private(set) var transitionLog: [(String, Date)] = []

    /// Enable to record state transitions for testing
    var recordTransitions = false

    // MARK: - Init

    init(currentIndex: Int) {
        self.currentIndex = currentIndex
    }

    // MARK: - Animation Lifecycle

    /// Called when swipe animation starts.
    /// Sets up the preview for the next photo.
    func startAnimation(nextAssetID: String) {
        previewAssetID = nextAssetID
        isAnimating = true

        if recordTransitions {
            transitionLog.append(("startAnimation", Date()))
            transitionLog.append(("previewAssetID=\(nextAssetID)", Date()))
            transitionLog.append(("isAnimating=true", Date()))
        }
    }

    /// Called when swipe animation completes.
    ///
    /// CRITICAL: This method ensures `isAnimating` becomes `false` BEFORE
    /// `currentIndex` changes. This ordering prevents the preview from
    /// briefly showing the wrong photo (which causes visual "shift" artifacts).
    func completeAnimation(nextIndex: Int) {
        // Step 1: Hide preview FIRST (instant, no animation)
        if recordTransitions {
            transitionLog.append(("isAnimating=false", Date()))
        }
        isAnimating = false
        previewAssetID = nil

        if recordTransitions {
            transitionLog.append(("previewAssetID=nil", Date()))
        }

        // Step 2: Change index AFTER preview is hidden
        if recordTransitions {
            transitionLog.append(("currentIndex=\(nextIndex)", Date()))
        }
        currentIndex = nextIndex
    }

    /// Reset state without changing index (e.g., when all items are trashed)
    func reset() {
        if recordTransitions {
            transitionLog.append(("reset", Date()))
        }
        isAnimating = false
        previewAssetID = nil
    }

    /// Clear transition log (for testing)
    func clearTransitionLog() {
        transitionLog.removeAll()
    }
}
