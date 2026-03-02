//
//  SwipeToTrashAnimationState.swift
//  SClean
//
//  Testable state machine for swipe-to-trash animation
//  Ensures correct ordering of state transitions to prevent visual artifacts
//

import SwiftUI
import Combine
import Foundation

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
    /// Current page index. Settable for TabView binding and direct navigation.
    @Published var currentIndex: Int

    /// Drag progress from 0.0 (start) to 1.0 (threshold reached).
    /// Used by preview layer to sync reveal with drag gesture.
    @Published private(set) var dragProgress: CGFloat = 0

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
        debugLog("startAnimation nextAssetID=\(nextAssetID) currentIndex=\(currentIndex)")
        previewAssetID = nextAssetID
        isAnimating = true

        if recordTransitions {
            transitionLog.append(("startAnimation", Date()))
            transitionLog.append(("previewAssetID=\(nextAssetID)", Date()))
            transitionLog.append(("isAnimating=true", Date()))
        }
    }

    /// Called continuously during drag to update progress.
    /// Progress is clamped to 0.0...1.0 range.
    func updateDragProgress(_ progress: CGFloat) {
        dragProgress = min(1.0, max(0.0, progress))

        if recordTransitions {
            transitionLog.append(("dragProgress=\(dragProgress)", Date()))
        }
    }

    /// Called when drag is cancelled (released before threshold).
    /// Resets animation state without changing index.
    func cancelAnimation() {
        debugLog("cancelAnimation currentIndex=\(currentIndex) previewAssetID=\(previewAssetID ?? "nil")")
        if recordTransitions {
            transitionLog.append(("cancelAnimation", Date()))
        }

        dragProgress = 0
        isAnimating = false
        previewAssetID = nil
    }

    /// Called when swipe animation completes.
    ///
    /// CRITICAL: This method ensures `isAnimating` becomes `false` BEFORE
    /// `currentIndex` changes. This ordering prevents the preview from
    /// briefly showing the wrong photo (which causes visual "shift" artifacts).
    func completeAnimation(nextIndex: Int) {
        debugLog("completeAnimation nextIndex=\(nextIndex) currentIndex(before)=\(currentIndex) previewAssetID=\(previewAssetID ?? "nil")")
        // Step 1: Hide preview FIRST (instant, no animation)
        if recordTransitions {
            transitionLog.append(("isAnimating=false", Date()))
        }
        dragProgress = 0
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
        debugLog("completeAnimation finished currentIndex(after)=\(currentIndex)")
    }

    /// Reset state without changing index (e.g., when all items are trashed)
    func reset() {
        debugLog("reset currentIndex=\(currentIndex)")
        if recordTransitions {
            transitionLog.append(("reset", Date()))
        }
        dragProgress = 0
        isAnimating = false
        previewAssetID = nil
    }

    /// Clear transition log (for testing)
    func clearTransitionLog() {
        transitionLog.removeAll()
    }

    private func debugLog(_ message: String) {
#if DEBUG
        print("[SwipeDebug][AnimationState] \(message)")
#endif
    }
}
