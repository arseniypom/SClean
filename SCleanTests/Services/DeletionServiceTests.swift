//
//  DeletionServiceTests.swift
//  SCleanTests
//
//  Tests for DeletionService models (DeletionResult, DeletionProgress, DeletionError)
//

import Testing
import Foundation
@testable import SClean

struct DeletionServiceTests {

    // MARK: - DeletionResult Tests

    @Test func deletionResult_isFullSuccess_trueWhenAllDeleted() {
        let result = DeletionResult(deletedCount: 5, failedIDs: [], error: nil)

        #expect(result.isFullSuccess == true)
        #expect(result.isPartialSuccess == false)
        #expect(result.isFailure == false)
    }

    @Test func deletionResult_isPartialSuccess_trueWhenSomeFailures() {
        let result = DeletionResult(deletedCount: 3, failedIDs: ["a", "b"], error: nil)

        #expect(result.isFullSuccess == false)
        #expect(result.isPartialSuccess == true)
        #expect(result.isFailure == false)
    }

    @Test func deletionResult_isFailure_trueWhenNoneDeleted() {
        let result = DeletionResult(deletedCount: 0, failedIDs: ["a"], error: .userCancelled)

        #expect(result.isFullSuccess == false)
        #expect(result.isPartialSuccess == false)
        #expect(result.isFailure == true)
    }

    @Test func deletionResult_totalAttempted_sumOfDeletedAndFailed() {
        let result = DeletionResult(deletedCount: 3, failedIDs: ["a", "b"], error: nil)

        #expect(result.totalAttempted == 5)
    }

    @Test func deletionResult_empty_hasZeroCounts() {
        let result = DeletionResult.empty

        #expect(result.deletedCount == 0)
        #expect(result.failedIDs.isEmpty)
        #expect(result.error == nil)
    }

    // MARK: - DeletionProgress Tests

    @Test func deletionProgress_fractionCompleted_calculatedCorrectly() {
        let progress = DeletionProgress(current: 3, total: 10)

        #expect(progress.fractionCompleted == 0.3)
    }

    @Test func deletionProgress_fractionCompleted_zeroWhenTotalIsZero() {
        let progress = DeletionProgress(current: 0, total: 0)

        #expect(progress.fractionCompleted == 0)
    }

    @Test func deletionProgress_fractionCompleted_oneWhenComplete() {
        let progress = DeletionProgress(current: 5, total: 5)

        #expect(progress.fractionCompleted == 1.0)
    }

    // MARK: - DeletionError Tests

    @Test func deletionError_hasLocalizedDescriptions() {
        let errors: [DeletionError] = [
            .permissionDenied,
            .permissionRevoked,
            .noAssetsFound,
            .userCancelled,
            .unknown("Test error")
        ]

        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test func deletionError_unknownIncludesMessage() {
        let error = DeletionError.unknown("Custom message")

        #expect(error.localizedDescription == "Custom message")
    }

    @Test func deletionError_equatable() {
        #expect(DeletionError.permissionDenied == DeletionError.permissionDenied)
        #expect(DeletionError.userCancelled == DeletionError.userCancelled)
        #expect(DeletionError.unknown("a") == DeletionError.unknown("a"))
        #expect(DeletionError.unknown("a") != DeletionError.unknown("b"))
    }
}
