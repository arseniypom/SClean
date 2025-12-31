//
//  SortOrder.swift
//  SClean
//
//  Photo sort order preference (Newest / Oldest first)
//

import SwiftUI

enum SortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: return "Newest First"
        case .oldestFirst: return "Oldest First"
        }
    }

    var isAscending: Bool {
        self == .oldestFirst
    }

    var iconName: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        }
    }
}

extension SortOrder {
    static let storageKey = "SlideClean.sortOrder"

    static func from(raw: String) -> SortOrder {
        SortOrder(rawValue: raw) ?? .newestFirst
    }
}
