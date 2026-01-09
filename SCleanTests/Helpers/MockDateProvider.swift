//
//  MockDateProvider.swift
//  SCleanTests
//
//  Fixed/controllable date provider for testing
//

import Foundation
@testable import SClean

/// Controllable date provider for deterministic testing
final class MockDateProvider: DateProviding, @unchecked Sendable {
    private var currentDate: Date

    init(fixedDate: Date = Date(timeIntervalSince1970: 1000000)) {
        self.currentDate = fixedDate
    }

    var now: Date {
        currentDate
    }

    /// Advance time by specified interval
    func advance(by interval: TimeInterval) {
        currentDate = currentDate.addingTimeInterval(interval)
    }

    /// Set to a specific date
    func set(_ date: Date) {
        currentDate = date
    }
}
