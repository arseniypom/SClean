//
//  Theme.swift
//  SClean
//
//  Minimal bold design foundation (Ink / Paper / Blade)
//

import SwiftUI
import UIKit

// MARK: - Brand (Minimal)

extension Color {

    /// Ink — brand near-black
    static let scInk = Color(hex: "0A0A0C")

    /// Paper — brand off-white (not pure white, softer)
    static let scPaper = Color(hex: "F7F7FA")

    /// Blade — single cool accent for interactive states
    static let scBlade = Color(hex: "6D7CFF")

    // Prefer system semantic colors for status (native + accessible)
    static let scSuccess = Color(uiColor: .systemGreen)
    static let scError   = Color(uiColor: .systemRed)
    static let scWarning = Color(uiColor: .systemOrange)
    static let scInfo    = Color(uiColor: .systemBlue)
}

// MARK: - Semantic (Adaptive)

extension Color {

    // Background planes
    static let scBackground = Color(light: "F7F7FA", dark: "0A0A0C")

    /// Primary surface (lists, sheets). Slightly separated from background.
    static let scSurface = Color(light: "FFFFFF", dark: "111114")

    /// Elevated surface (modals, floating controls) — tiny lift via tone shift.
    static let scSurfaceElevated = Color(light: "FFFFFF", dark: "15151B")

    /// Hairlines / dividers (must be visible but quiet)
    static let scBorder = Color(light: "D9D9E0", dark: "2A2A30")

    // Text
    static let scTextPrimary = Color(light: "0A0A0C", dark: "F7F7FA")
    static let scTextSecondary = Color(light: "5A5C67", dark: "A9ABB6")
    static let scTextDisabled = Color(light: "A5A7B2", dark: "5E606B")

    /// Text/icon on Blade or other filled controls
    static let scTextInverse = Color(light: "FFFFFF", dark: "0A0A0C")

    // Interactive
    static let scTint = scBlade
    static let scDestructive = Color(uiColor: .systemRed)
}

// MARK: - Hex helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
            ? UIColor(Color(hex: dark))
            : UIColor(Color(hex: light))
        })
    }
}

// MARK: - Spacing (keep, but tighten the system)

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 40   // was 48; tighter feels more “mechanical”
}

// MARK: - Corner Radius (sharper)

enum CornerRadius {
    static let sm: CGFloat = 10     // buttons, small cards
    static let md: CGFloat = 14     // sheets, cards
    static let lg: CGFloat = 16     // large containers only
}

// MARK: - Typography (precise, not rounded)

enum Typography {

    // Use default design (sharp), and let the system feel native.
    static let largeTitle = Font.system(.largeTitle, design: .default).weight(.bold)
    static let title1     = Font.system(.title, design: .default).weight(.bold)
    static let title2     = Font.system(.title2, design: .default).weight(.semibold)
    static let title3     = Font.system(.title3, design: .default).weight(.semibold)

    static let headline   = Font.system(.headline, design: .default)
    static let subheadline = Font.system(.subheadline, design: .default).weight(.medium)

    static let body       = Font.system(.body, design: .default)
    static let bodyMedium = Font.system(.body, design: .default).weight(.medium)

    static let callout    = Font.system(.callout, design: .default)
    static let caption1   = Font.system(.caption, design: .default)
    static let caption2   = Font.system(.caption2, design: .default)
}

// MARK: - Motion (snappier)

enum AnimationDuration {
    static let fast: Double = 0.12
    static let normal: Double = 0.20
    static let slow: Double = 0.32
}

// MARK: - Hairlines + subtle shadows (minimal depth)

enum StrokeWidth {
    static let hairline: CGFloat = 1
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    /// Extremely subtle; avoid “floaty cards”
    static let subtle = ShadowStyle(
        color: Color(light: "000000", dark: "000000").opacity(0.08),
        radius: 10,
        x: 0,
        y: 6
    )

    /// Often you can skip shadows entirely in dark mode via surface tone separation
    static let none = ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
}

extension View {
    func scShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
