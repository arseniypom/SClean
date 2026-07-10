//
//  TrashServiceTests.swift
//  SCleanTests
//
//  Tests for TrashService
//

import Testing
import Foundation
@testable import SClean

@MainActor
struct TrashServiceTests {

    // MARK: - Test Setup

    private func makeService(
        storage: MockKeyValueStore = MockKeyValueStore(),
        dateProvider: MockDateProvider = MockDateProvider()
    ) -> TrashService {
        TrashService(storage: storage, dateProvider: dateProvider)
    }

    // MARK: - Trash Tests

    @Test func trash_addsItemToTrashedItems() async throws {
        let service = makeService()

        service.trash("asset1")

        #expect(service.trashedItems.count == 1)
        #expect(service.trashedItems.first?.assetID == "asset1")
    }

    @Test func trash_setsLastTrashedID() async throws {
        let service = makeService()

        service.trash("asset1")

        #expect(service.lastTrashedID == "asset1")
    }

    @Test func trash_doesNotAddDuplicates() async throws {
        let service = makeService()

        service.trash("asset1")
        service.trash("asset1")

        #expect(service.trashedItems.count == 1)
    }

    // MARK: - Restore Tests

    @Test func restore_removesItemFromTrash() async throws {
        let service = makeService()
        service.trash("asset1")

        service.restore("asset1")

        #expect(service.trashedItems.isEmpty)
    }

    @Test func restoreMultiple_removesAllSpecifiedItems() async throws {
        let service = makeService()
        service.trash("a")
        service.trash("b")
        service.trash("c")

        service.restoreMultiple(["a", "b"])

        #expect(service.trashedItems.count == 1)
        #expect(service.trashedItems.first?.assetID == "c")
    }

    // MARK: - Undo Tests

    @Test func undoLastTrash_restoresLastItem() async throws {
        let service = makeService()
        service.trash("a")
        service.trash("b")

        service.undoLastTrash()

        #expect(service.trashedItems.count == 1)
        #expect(service.trashedItems.first?.assetID == "a")
        #expect(!service.isTrashed("b"))
    }

    @Test func undoLastTrash_clearsLastTrashedID() async throws {
        let service = makeService()
        service.trash("a")

        service.undoLastTrash()

        #expect(service.lastTrashedID == nil)
    }

    // MARK: - Query Tests

    @Test func isTrashed_returnsTrueForTrashedItems() async throws {
        let service = makeService()
        service.trash("asset1")

        #expect(service.isTrashed("asset1") == true)
    }

    @Test func isTrashed_returnsFalseForNonTrashedItems() async throws {
        let service = makeService()

        #expect(service.isTrashed("unknown") == false)
    }

    @Test func filterVisible_excludesTrashedItems() async throws {
        let service = makeService()
        let assets = TestFactory.yearAssets(count: 5)

        service.trash(assets[1].id)
        service.trash(assets[3].id)

        let visible = service.filterVisible(assets)

        #expect(visible.count == 3)
        #expect(visible.map(\.id) == [assets[0].id, assets[2].id, assets[4].id])
    }

    // MARK: - Clear/Remove Tests

    @Test func clearAll_emptiesTrash() async throws {
        let service = makeService()
        service.trash("a")
        service.trash("b")
        service.trash("c")

        service.clearAll()

        #expect(service.trashedItems.isEmpty)
        #expect(service.lastTrashedID == nil)
    }

    @Test func remove_deletesSpecificIDs() async throws {
        let service = makeService()
        service.trash("a")
        service.trash("b")
        service.trash("c")

        service.remove(["a", "c"])

        #expect(service.trashedItems.count == 1)
        #expect(service.trashedItems.first?.assetID == "b")
    }

    // MARK: - Ordering Tests

    @Test func trashedItems_orderedByTrashedAtOldestFirst() async throws {
        let dateProvider = MockDateProvider(fixedDate: Date(timeIntervalSince1970: 1000))
        let service = makeService(dateProvider: dateProvider)

        service.trash("a")
        dateProvider.advance(by: 100)
        service.trash("b")
        dateProvider.advance(by: 100)
        service.trash("c")

        #expect(service.orderedTrashedIDs == ["a", "b", "c"])
        #expect(service.trashedItems[0].trashedAt < service.trashedItems[1].trashedAt)
        #expect(service.trashedItems[1].trashedAt < service.trashedItems[2].trashedAt)
    }

    // MARK: - Persistence Tests

    @Test func persistence_survivesReload() async throws {
        let storage = MockKeyValueStore()
        let dateProvider = MockDateProvider()

        // Create first service and trash items
        let service1 = TrashService(storage: storage, dateProvider: dateProvider)
        service1.trash("a")
        service1.trash("b")

        // Create second service with same storage (simulates app restart)
        let service2 = TrashService(storage: storage, dateProvider: dateProvider)

        #expect(service2.trashedItems.count == 2)
        #expect(service2.isTrashed("a"))
        #expect(service2.isTrashed("b"))
    }

    // MARK: - Fast Lookup Set Consistency

    @Test func trashedIDs_staysConsistentAcrossAllMutations() async throws {
        let service = makeService()

        service.trash("a")
        service.trash("b")
        service.trash("c")
        service.trash("d")
        #expect(service.trashedIDs == ["a", "b", "c", "d"])

        service.restore("a")
        #expect(service.trashedIDs == ["b", "c", "d"])
        #expect(!service.isTrashed("a"))

        service.restoreMultiple(["b"])
        #expect(service.trashedIDs == ["c", "d"])

        service.remove(["c"])
        #expect(service.trashedIDs == ["d"])

        service.markDeleted(["d"])
        #expect(service.trashedIDs.isEmpty)
        #expect(service.permanentlyDeletedIDs == ["d"])
        #expect(service.excludedIDs == ["d"])

        service.trash("e")
        service.clearAll()
        #expect(service.trashedIDs.isEmpty)
        #expect(!service.isTrashed("e"))
    }

    @Test func trashedIDs_populatedAfterReloadFromStorage() async throws {
        let storage = MockKeyValueStore()
        let dateProvider = MockDateProvider()

        let service1 = TrashService(storage: storage, dateProvider: dateProvider)
        service1.trash("a")
        service1.trash("b")

        let service2 = TrashService(storage: storage, dateProvider: dateProvider)

        #expect(service2.trashedIDs == ["a", "b"])
    }

    @Test func migration_convertsLegacySetFormat() async throws {
        let storage = MockKeyValueStore()
        let dateProvider = MockDateProvider()

        // Seed with legacy format (Set<String>)
        let legacyIDs: Set<String> = ["legacy1", "legacy2"]
        let legacyData = try JSONEncoder().encode(legacyIDs)
        storage.set(legacyData, forKey: "SClean.trashedAssetIDs")

        // Create service - should migrate
        let service = TrashService(storage: storage, dateProvider: dateProvider)

        #expect(service.trashedItems.count == 2)
        #expect(service.isTrashed("legacy1"))
        #expect(service.isTrashed("legacy2"))
        // Legacy key should be removed
        #expect(storage.hasKey("SClean.trashedAssetIDs") == false)
        // New format key should exist
        #expect(storage.hasKey("SlideClean.trashedItems") == true)
    }
}
