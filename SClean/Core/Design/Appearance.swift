//
//  Appearance.swift
//  SClean
//
//  App appearance (Light / Dark / System)
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension AppearanceMode {
    static let storageKey = "SClean.appearance"

    static func from(raw: String) -> AppearanceMode {
        AppearanceMode(rawValue: raw) ?? .system
    }
}

