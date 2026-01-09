//
//  StatsServiceTests.swift
//  SCleanTests
//
//  Tests for StatsService
//

import Testing
import Foundation
@testable import SClean

@MainActor
struct StatsServiceTests {

    // MARK: - Test Setup

    private func makeService(storage: MockKeyValueStore = MockKeyValueStore()) -> StatsService {
        StatsService(storage: storage)
    }

    // MARK: - Recording Tests

    @Test func recordDeletion_incrementsCount() async throws {
        let service = makeService()

        service.recordDeletion(count: 5, bytes: 1000)

        #expect(service.stats.totalMediaDeleted == 5)
    }

    @Test func recordDeletion_accumulatesBytes() async throws {
        let service = makeService()

        service.recordDeletion(count: 1, bytes: TestBytes.oneGB)
        service.recordDeletion(count: 1, bytes: TestBytes.halfGB)

        #expect(service.stats.totalBytesSaved == TestBytes.oneGB + TestBytes.halfGB)
    }

    @Test func recordDeletion_accumulatesCounts() async throws {
        let service = makeService()

        service.recordDeletion(count: 5, bytes: 1000)
        service.recordDeletion(count: 3, bytes: 1000)

        #expect(service.stats.totalMediaDeleted == 8)
    }

    // MARK: - Formatting Tests

    @Test func formattedBytesSaved_showsGBWhenOverThreshold() async throws {
        let service = makeService()

        service.recordDeletion(count: 1, bytes: TestBytes.twoGB)

        #expect(service.formattedBytesSaved == "2.0")
        #expect(service.bytesSavedUnit == "GB")
    }

    @Test func formattedBytesSaved_showsMBWhenUnderThreshold() async throws {
        let service = makeService()

        service.recordDeletion(count: 1, bytes: 500 * TestBytes.oneMB)

        #expect(service.bytesSavedUnit == "MB")
        #expect(service.formattedBytesSaved == "500")
    }

    @Test func formattedMediaCount_usesDecimalFormat() async throws {
        let service = makeService()

        service.recordDeletion(count: 1234, bytes: 1000)

        // Check format contains separator (locale-dependent: could be "1,234" or "1 234" etc.)
        let formatted = service.formattedMediaCount
        #expect(formatted.contains("1") && formatted.contains("234"))
        #expect(formatted.count >= 5) // "1,234" or "1 234" etc.
    }

    // MARK: - State Tests

    @Test func hasStats_returnsFalseWhenZero() async throws {
        let service = makeService()

        #expect(service.hasStats == false)
    }

    @Test func hasStats_returnsTrueAfterRecording() async throws {
        let service = makeService()

        service.recordDeletion(count: 1, bytes: 100)

        #expect(service.hasStats == true)
    }

    // MARK: - Persistence Tests

    @Test func persistence_survivesReload() async throws {
        let storage = MockKeyValueStore()

        // Create first service and record stats
        let service1 = StatsService(storage: storage)
        service1.recordDeletion(count: 10, bytes: TestBytes.oneGB)

        // Create second service with same storage (simulates app restart)
        let service2 = StatsService(storage: storage)

        #expect(service2.stats.totalMediaDeleted == 10)
        #expect(service2.stats.totalBytesSaved == TestBytes.oneGB)
    }
}
