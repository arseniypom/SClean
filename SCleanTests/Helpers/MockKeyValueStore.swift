//
//  MockKeyValueStore.swift
//  SCleanTests
//
//  In-memory key-value store for testing
//

import Foundation
@testable import SClean

/// In-memory implementation of KeyValueStoring for tests
final class MockKeyValueStore: KeyValueStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        storage[key]
    }

    func set(_ data: Data?, forKey key: String) {
        if let data = data {
            storage[key] = data
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }

    /// Clear all stored data (for test isolation)
    func reset() {
        storage.removeAll()
    }

    /// Check if a key exists
    func hasKey(_ key: String) -> Bool {
        storage[key] != nil
    }
}
