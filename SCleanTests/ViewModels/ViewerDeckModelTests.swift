//
//  ViewerDeckModelTests.swift
//  SCleanTests
//
//  Tests for the viewer's deck model: filtering, index mapping,
//  trash/undo mutations, and reconciliation with TrashService.
//

import Testing
import Foundation
@testable import SClean

@MainActor
struct ViewerDeckModelTests {

    // MARK: - Test Setup

    private func makeTrashService() -> TrashService {
        TrashService(storage: MockKeyValueStore(), dateProvider: MockDateProvider())
    }

    private func makeModel(
        assetCount: Int = 5,
        startIndex: Int = 0,
        trashService: TrashService? = nil,
        preTrashed: [Int] = []
    ) -> (ViewerDeckModel, [YearAsset], TrashService) {
        let service = trashService ?? makeTrashService()
        let assets = TestFactory.yearAssets(count: assetCount)
        for index in preTrashed {
            service.trash(assets[index].id)
        }
        let model = ViewerDeckModel(assets: assets, startIndex: startIndex, trashService: service)
        return (model, assets, service)
    }

    // MARK: - Init

    @Test func init_filtersTrashedAssets() async throws {
        let (model, assets, _) = makeModel(assetCount: 5, preTrashed: [1, 3])

        #expect(model.deck.map(\.id) == [assets[0].id, assets[2].id, assets[4].id])
    }

    @Test func init_filtersPermanentlyDeletedAssets() async throws {
        let service = makeTrashService()
        let assets = TestFactory.yearAssets(count: 3)
        service.trash(assets[1].id)
        service.markDeleted([assets[1].id])

        let model = ViewerDeckModel(assets: assets, startIndex: 0, trashService: service)

        #expect(model.deck.map(\.id) == [assets[0].id, assets[2].id])
    }

    @Test func init_mapsStartIndexToDeckIndex() async throws {
        // Original index 4 with indices 1 and 3 trashed → deck index 2
        let (model, assets, _) = makeModel(assetCount: 5, startIndex: 4, preTrashed: [1, 3])

        #expect(model.currentIndex == 2)
        #expect(model.currentAsset?.id == assets[4].id)
    }

    @Test func init_startIndexOnTrashedAssetFallsBackToNearestVisible() async throws {
        // Index 2 trashed; nearest visible from 2 is 3 (forward preferred)
        let (model, assets, _) = makeModel(assetCount: 5, startIndex: 2, preTrashed: [2])

        #expect(model.currentAsset?.id == assets[3].id)
    }

    @Test func init_outOfBoundsStartIndexClamps() async throws {
        let (model, assets, _) = makeModel(assetCount: 3, startIndex: 99)

        #expect(model.currentAsset?.id == assets[2].id)
    }

    @Test func init_emptyAfterFilteringYieldsEmptyDeck() async throws {
        let (model, _, _) = makeModel(assetCount: 2, preTrashed: [0, 1])

        #expect(model.isEmpty)
        #expect(model.currentIndex == 0)
        #expect(model.currentAsset == nil)
    }

    // MARK: - Trash

    @Test func trashCurrent_removesAssetAndKeepsIndex() async throws {
        let (model, assets, service) = makeModel(assetCount: 5, startIndex: 1)

        let removed = model.trashCurrent()

        #expect(removed?.id == assets[1].id)
        #expect(service.isTrashed(assets[1].id))
        #expect(model.deck.count == 4)
        // Index unchanged: the next asset slides into the current slot
        #expect(model.currentIndex == 1)
        #expect(model.currentAsset?.id == assets[2].id)
    }

    @Test func trashCurrent_onLastItemClampsIndexBack() async throws {
        let (model, assets, _) = makeModel(assetCount: 3, startIndex: 2)

        model.trashCurrent()

        #expect(model.currentIndex == 1)
        #expect(model.currentAsset?.id == assets[1].id)
    }

    @Test func trashCurrent_onOnlyItemEmptiesDeck() async throws {
        let (model, _, _) = makeModel(assetCount: 1)

        let removed = model.trashCurrent()

        #expect(removed != nil)
        #expect(model.isEmpty)
        #expect(model.currentIndex == 0)
    }

    @Test func trashCurrent_onEmptyDeckReturnsNil() async throws {
        let (model, _, _) = makeModel(assetCount: 1)
        model.trashCurrent()

        #expect(model.trashCurrent() == nil)
    }

    // MARK: - Restore (Undo)

    @Test func restore_reinsertsAtOriginalRelativePosition() async throws {
        let (model, assets, service) = makeModel(assetCount: 5, startIndex: 2)

        let removed = try #require(model.trashCurrent()) // removes asset-2
        model.restore(removed)

        #expect(!service.isTrashed(assets[2].id))
        #expect(model.deck.map(\.id) == assets.map(\.id))
        #expect(model.currentIndex == 2)
        #expect(model.currentAsset?.id == assets[2].id)
    }

    @Test func restore_afterMultipleInterleavedTrashesKeepsOriginalOrder() async throws {
        let (model, assets, _) = makeModel(assetCount: 5, startIndex: 1)

        let first = try #require(model.trashCurrent())  // asset-1; current → asset-2
        let second = try #require(model.trashCurrent()) // asset-2; current → asset-3

        model.restore(first)  // asset-1 back at deck position 1
        #expect(model.deck.map(\.id) == [assets[0].id, assets[1].id, assets[3].id, assets[4].id])
        #expect(model.currentAsset?.id == assets[1].id)

        model.restore(second) // asset-2 back between asset-1 and asset-3
        #expect(model.deck.map(\.id) == assets.map(\.id))
        #expect(model.currentAsset?.id == assets[2].id)
    }

    @Test func restore_lastAssetOfDeckReappears() async throws {
        let (model, assets, _) = makeModel(assetCount: 1)
        let removed = try #require(model.trashCurrent())
        #expect(model.isEmpty)

        model.restore(removed)

        #expect(model.deck.map(\.id) == [assets[0].id])
        #expect(model.currentIndex == 0)
    }

    @Test func restore_ignoresAssetAlreadyInDeck() async throws {
        let (model, assets, _) = makeModel(assetCount: 3)

        model.restore(assets[1])

        #expect(model.deck.count == 3)
    }

    // MARK: - Navigation

    @Test func goNextAndPrevious_clampAtEnds() async throws {
        let (model, _, _) = makeModel(assetCount: 3, startIndex: 0)

        model.goPrevious()
        #expect(model.currentIndex == 0)

        model.goNext()
        model.goNext()
        #expect(model.currentIndex == 2)

        model.goNext()
        #expect(model.currentIndex == 2)
    }

    @Test func predictedTrashSuccessor_matchesWhatTrashCurrentReveals() async throws {
        let (model, assets, _) = makeModel(assetCount: 3, startIndex: 0)

        // Mid-deck: successor is the next asset
        #expect(model.predictedTrashSuccessor?.id == assets[1].id)
        model.trashCurrent()
        #expect(model.currentAsset?.id == assets[1].id)

        // Last item: successor falls back to the previous asset
        model.goNext()
        #expect(model.predictedTrashSuccessor?.id == assets[1].id)
        model.trashCurrent()
        #expect(model.currentAsset?.id == assets[1].id)

        // Only item: no successor
        #expect(model.predictedTrashSuccessor == nil)
    }

    // MARK: - Reconciliation

    @Test func reconcile_removesExternallyTrashedAssets() async throws {
        let (model, assets, service) = makeModel(assetCount: 5, startIndex: 2)

        // Simulates trashing from another screen while the viewer is off-screen
        service.trash(assets[2].id)
        model.reconcileWithTrashService()

        #expect(model.deck.count == 4)
        // Current asset was removed → nearest visible by original position
        #expect(model.currentAsset?.id == assets[3].id)
    }

    @Test func reconcile_reinsertsExternallyRestoredAssets() async throws {
        let (model, assets, service) = makeModel(assetCount: 5, startIndex: 0, preTrashed: [1])

        // Simulates restoring on the Trash screen
        service.restore(assets[1].id)
        model.reconcileWithTrashService()

        #expect(model.deck.map(\.id) == assets.map(\.id))
        #expect(model.currentAsset?.id == assets[0].id)
    }

    @Test func reconcile_removesPermanentlyDeletedAssetsAndKeepsCurrent() async throws {
        let (model, assets, service) = makeModel(assetCount: 5, startIndex: 3)

        service.trash(assets[0].id)
        service.markDeleted([assets[0].id])
        model.reconcileWithTrashService()

        #expect(model.deck.count == 4)
        #expect(model.currentAsset?.id == assets[3].id)
    }

    @Test func reconcile_noChangesKeepsDeckIdentical() async throws {
        let (model, assets, _) = makeModel(assetCount: 3, startIndex: 1)

        model.reconcileWithTrashService()

        #expect(model.deck.map(\.id) == assets.map(\.id))
        #expect(model.currentIndex == 1)
    }
}
