//
//  Theme.swift
//  SClean
//
//  Design system foundation
//

import SwiftUI

// MARK: - Color Definitions

extension Color {
    
    // MARK: Brand Colors
    
    /// Deep Petrol - Primary CTAs, key icons, active states
    static let scPrimary = Color(hex: "0B3B3A")
    
    /// Smoked Plum - Secondary emphasis, highlights, selection accents
    static let scSecondary = Color(hex: "3B2B4F")
    
    /// Frosted Apricot - Undo, subtle highlights, progress chips, badges
    static let scAccent = Color(hex: "F4B28B")
    
    // MARK: Status Colors
    
    /// Jade - Success states
    static let scSuccess = Color(hex: "2E9E7A")
    
    /// Cranberry - Error states
    static let scError = Color(hex: "D14B5A")
    
    /// Ochre - Warning states
    static let scWarning = Color(hex: "D2A316")
    
    /// Steel - Info states
    static let scInfo = Color(hex: "3E7DA6")
}

// MARK: - Semantic Colors (Adaptive)

extension Color {
    
    // MARK: Backgrounds
    
    /// Main app background
    static let scBackground = Color("Background")
    
    /// Card/surface background
    static let scSurface = Color("Surface")
    
    /// Elevated surface (layered sections)
    static let scSurfaceElevated = Color("SurfaceElevated")
    
    /// Hairline borders/dividers
    static let scBorder = Color("Border")
    
    // MARK: Text Colors
    
    /// Primary text
    static let scTextPrimary = Color("TextPrimary")
    
    /// Secondary text
    static let scTextSecondary = Color("TextSecondary")
    
    /// Disabled text
    static let scTextDisabled = Color("TextDisabled")
    
    /// Inverse text (on Primary button)
    static let scTextInverse = Color("TextInverse")
}

// MARK: - Hex Color Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

// MARK: - Spacing System

enum Spacing {
    /// 4pt
    static let xxs: CGFloat = 4
    /// 8pt
    static let xs: CGFloat = 8
    /// 12pt
    static let sm: CGFloat = 12
    /// 16pt
    static let md: CGFloat = 16
    /// 24pt
    static let lg: CGFloat = 24
    /// 32pt
    static let xl: CGFloat = 32
    /// 48pt
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius

enum CornerRadius {
    /// 4pt
    static let xs: CGFloat = 4
    /// 8pt
    static let sm: CGFloat = 8
    /// 12pt
    static let md: CGFloat = 12
    /// 16pt
    static let lg: CGFloat = 16
    /// 24pt
    static let xl: CGFloat = 24
}

// MARK: - Typography

enum Typography {
    
    // MARK: Large Titles
    
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    
    // MARK: Titles
    
    static let title1 = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title2 = Font.system(size: 22, weight: .bold, design: .rounded)
    static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
    
    // MARK: Headlines
    
    static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let subheadline = Font.system(size: 15, weight: .medium, design: .rounded)
    
    // MARK: Body
    
    static let body = Font.system(size: 17, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 17, weight: .medium, design: .default)
    
    // MARK: Callout & Caption
    
    static let callout = Font.system(size: 16, weight: .regular, design: .default)
    static let caption1 = Font.system(size: 12, weight: .regular, design: .default)
    static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
}

// MARK: - Animation Durations

enum AnimationDuration {
    static let fast: Double = 0.15
    static let normal: Double = 0.25
    static let slow: Double = 0.4
}

// MARK: - Shadow Styles

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    
    static let card = ShadowStyle(
        color: Color.black.opacity(0.06),
        radius: 8,
        x: 0,
        y: 2
    )
    
    static let elevated = ShadowStyle(
        color: Color.black.opacity(0.1),
        radius: 16,
        x: 0,
        y: 4
    )
}

extension View {
    func scShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}


