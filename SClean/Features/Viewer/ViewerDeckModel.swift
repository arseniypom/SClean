//
//  ViewerDeckModel.swift
//  SClean
//
//  Mutable deck of visible assets backing the viewer's custom pager.
//  Trash removes from the deck immediately; undo re-inserts at the
//  original relative position. TrashService stays the source of truth
//  for persistence — the deck is a view-local projection.
//

import Foundation
import Combine

@MainActor
final class ViewerDeckModel: ObservableObject {

    /// Visible (non-trashed, non-deleted) assets in original order
    @Published private(set) var deck: [YearAsset]

    /// Index of the current page within the deck
    @Published private(set) var currentIndex: Int

    private let trashService: TrashService

    /// The full asset list as passed by the grid, in original order
    private let allAssets: [YearAsset]

    /// Original position of each asset, for stable undo re-insertion
    private let originalIndexByID: [String: Int]

    init(assets: [YearAsset], startIndex: Int, trashService: TrashService = .shared) {
        self.trashService = trashService
        self.allAssets = assets

        var indexByID: [String: Int] = [:]
        indexByID.reserveCapacity(assets.count)
        for (index, asset) in assets.enumerated() {
            indexByID[asset.id] = index
        }
        self.originalIndexByID = indexByID

        let excluded = trashService.excludedIDs
        let visibleDeck = assets.filter { !excluded.contains($0.id) }
        self.deck = visibleDeck
        self.currentIndex = Self.deckIndex(
            forOriginalIndex: startIndex,
            allAssets: assets,
            deck: visibleDeck
        )
    }

    // MARK: - Accessors

    var isEmpty: Bool { deck.isEmpty }

    var currentAsset: YearAsset? {
        asset(at: currentIndex)
    }

    func asset(at index: Int) -> YearAsset? {
        guard deck.indices.contains(index) else { return nil }
        return deck[index]
    }

    // MARK: - Navigation

    func goNext() {
        guard currentIndex < deck.count - 1 else { return }
        currentIndex += 1
    }

    func goPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    /// Set the current page directly (used by the pager on settle), clamped.
    func setCurrentIndex(_ index: Int) {
        guard !deck.isEmpty else {
            currentIndex = 0
            return
        }
        currentIndex = min(max(index, 0), deck.count - 1)
    }

    // MARK: - Trash / Restore

    /// Trash the current asset: persists via TrashService and removes it
    /// from the deck. The next asset naturally takes the current index
    /// (or the previous one when the last item was trashed).
    /// Returns the removed asset for undo, or nil if the deck is empty.
    @discardableResult
    func trashCurrent() -> YearAsset? {
        guard let asset = currentAsset else { return nil }

        trashService.trash(asset.id)
        deck.remove(at: currentIndex)
        if currentIndex >= deck.count {
            currentIndex = max(0, deck.count - 1)
        }
        return asset
    }

    /// Restore a trashed asset: persists via TrashService and re-inserts it
    /// at its original relative position, moving the current page to it.
    func restore(_ asset: YearAsset) {
        trashService.restore(asset.id)

        guard !deck.contains(where: { $0.id == asset.id }),
              let originalIndex = originalIndexByID[asset.id] else { return }

        let insertionIndex = deck.firstIndex { candidate in
            guard let candidateOriginal = originalIndexByID[candidate.id] else { return false }
            return candidateOriginal > originalIndex
        } ?? deck.count

        deck.insert(asset, at: insertionIndex)
        currentIndex = insertionIndex
    }

    /// Re-sync the deck with TrashService after external changes
    /// (restores or permanent deletions made on the Trash screen).
    func reconcileWithTrashService() {
        let excluded = trashService.excludedIDs
        let newDeck = allAssets.filter { !excluded.contains($0.id) }
        guard newDeck.map(\.id) != deck.map(\.id) else { return }

        let currentID = currentAsset?.id
        let originalAnchor = currentID.flatMap { originalIndexByID[$0] }

        deck = newDeck

        if let currentID, let index = deck.firstIndex(where: { $0.id == currentID }) {
            currentIndex = index
        } else if let originalAnchor {
            currentIndex = Self.deckIndex(
                forOriginalIndex: originalAnchor,
                allAssets: allAssets,
                deck: deck
            )
        } else {
            currentIndex = 0
        }
    }

    // MARK: - Index Mapping

    /// Map an index in the original (unfiltered) array to a deck index,
    /// falling back to the nearest visible asset when the target is hidden.
    private static func deckIndex(
        forOriginalIndex originalIndex: Int,
        allAssets: [YearAsset],
        deck: [YearAsset]
    ) -> Int {
        guard !deck.isEmpty else { return 0 }

        var deckIndexByID: [String: Int] = [:]
        deckIndexByID.reserveCapacity(deck.count)
        for (index, asset) in deck.enumerated() {
            deckIndexByID[asset.id] = index
        }

        // Search outward from the requested original index: exact match first,
        // then nearest visible neighbor (forward preferred on ties).
        let clamped = min(max(originalIndex, 0), max(allAssets.count - 1, 0))
        for offset in 0...max(allAssets.count, 1) {
            let forward = clamped + offset
            if forward < allAssets.count, let deckIndex = deckIndexByID[allAssets[forward].id] {
                return deckIndex
            }
            let backward = clamped - offset
            if backward >= 0, let deckIndex = deckIndexByID[allAssets[backward].id] {
                return deckIndex
            }
        }
        return 0
    }
}
