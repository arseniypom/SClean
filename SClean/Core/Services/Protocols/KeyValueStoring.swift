//
//  KeyValueStoring.swift
//  SClean
//
//  Protocol for abstracting UserDefaults for testability
//

import Foundation

/// Protocol for key-value storage (abstracts UserDefaults)
protocol KeyValueStoring {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStoring {
    func set(_ data: Data?, forKey key: String) {
        set(data as Any?, forKey: key)
    }
}
