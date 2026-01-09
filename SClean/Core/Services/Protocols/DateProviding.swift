//
//  DateProviding.swift
//  SClean
//
//  Protocol for abstracting Date for testability
//

import Foundation

/// Protocol for providing current date (enables deterministic testing)
protocol DateProviding {
    var now: Date { get }
}

/// Default implementation using system date
struct SystemDateProvider: DateProviding {
    var now: Date { Date() }
}
