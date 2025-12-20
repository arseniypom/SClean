//
//  Components.swift
//  SClean
//
//  Reusable UI components
//

import SwiftUI

// MARK: - Surface Styles
//
// Per Liquid Glass rules:
// - Glass is for CONTROLS (buttons, toolbars, FABs), NOT content
// - Content (cards, lists) uses solid surfaces
// - Single abstraction point for styling

extension View {
    /// Card/content surface - NO glass (cards are content, not controls)
    /// Use for: YearCard, content containers, list items
    func scCardStyle() -> some View {
        self
            .background(Color.scSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .scShadow(.card)
    }
    
    /// Control surface - Liquid Glass on iOS 26+, Material on older
    /// Use for: floating buttons, action controls, overlays
    @ViewBuilder
    func scControlSurface() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect()
        } else {
            self
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        }
    }
    
    /// Floating action button surface - Liquid Glass on iOS 26+, elevated surface on older
    /// Use for: FABs, floating controls
    @ViewBuilder
    func scFloatingButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect()
        } else {
            self
                .background(Color.scSurface)
                .clipShape(Circle())
                .scShadow(.elevated)
        }
    }
}

// MARK: - Primary Button

struct SCButton: View {
    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void
    
    @Environment(\.isEnabled) private var isEnabled
    
    enum Style {
        case primary
        case secondary
        case ghost
    }
    
    init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            buttonContent
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
    }
    
    @ViewBuilder
    private var buttonContent: some View {
        HStack(spacing: Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(title)
                .font(Typography.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .foregroundColor(foregroundColor)
        .modifier(ButtonBackgroundModifier(style: style))
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .scTextInverse
        case .secondary, .ghost:
            return .scPrimary
        }
    }
}

// MARK: - Button Background Modifier
//
// Per Liquid Glass rules:
// - Primary buttons: solid color (brand identity, legibility)
// - Secondary buttons: glass on iOS 26+ (they're controls), bordered on older
// - Ghost buttons: no background

private struct ButtonBackgroundModifier: ViewModifier {
    let style: SCButton.Style
    
    func body(content: Content) -> some View {
        switch style {
        case .primary:
            // Primary always solid for legibility + brand
            content
                .background(Color.scPrimary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            
        case .secondary:
            // Secondary: glass on iOS 26+, bordered on older
            if #available(iOS 26.0, *) {
                content
                    .glassEffect()
            } else {
                content
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .strokeBorder(Color.scPrimary.opacity(0.3), lineWidth: 1.5)
                    }
            }
            
        case .ghost:
            content
        }
    }
}

// MARK: - Year Card

/// Year card with button action
struct YearCard: View {
    let year: Int
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            YearCardContent(year: year, count: count)
        }
        .buttonStyle(.plain)
    }
}

/// Year card content (for use with NavigationLink or Button)
struct YearCardContent: View {
    let year: Int
    let count: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(String(year))
                    .font(Typography.title2)
                    .foregroundStyle(Color.scTextPrimary)
                
                Text(countText)
                    .font(Typography.subheadline)
                    .foregroundStyle(Color.scTextSecondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scTextDisabled)
        }
        .padding(Spacing.md)
        .scCardStyle()
    }
    
    private var countText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formattedCount = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(formattedCount) \(count == 1 ? "item" : "items")"
    }
}

// MARK: - Trash Card

/// Trash card content (for use with NavigationLink)
struct TrashCardContent: View {
    let count: Int
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Trash icon with accent background
            ZStack {
                Circle()
                    .fill(Color.scAccent.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.scAccent)
            }
            
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Trash")
                    .font(Typography.title3)
                    .foregroundStyle(Color.scTextPrimary)
                
                Text(countText)
                    .font(Typography.subheadline)
                    .foregroundStyle(Color.scTextSecondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scTextDisabled)
        }
        .padding(Spacing.md)
        .scCardStyle()
    }
    
    private var countText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formattedCount = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(formattedCount) \(count == 1 ? "item" : "items") to review"
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.scTextDisabled)
            
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.title3)
                    .foregroundStyle(Color.scTextPrimary)
                
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(Color.scTextSecondary)
                    .multilineTextAlignment(.center)
            }
            
            if let actionTitle, let action {
                SCButton(actionTitle, style: .secondary, action: action)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(Spacing.xl)
    }
}

// MARK: - Loading State

struct LoadingStateView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.scPrimary)
            
            Text(message)
                .font(Typography.subheadline)
                .foregroundStyle(Color.scTextSecondary)
        }
    }
}

// MARK: - Info Banner

struct InfoBanner: View {
    let icon: String
    let message: String
    let style: Style
    let action: (() -> Void)?
    
    enum Style {
        case info
        case warning
        case error
        
        var backgroundColor: Color {
            switch self {
            case .info: return Color.scInfo.opacity(0.1)
            case .warning: return Color.scWarning.opacity(0.1)
            case .error: return Color.scError.opacity(0.1)
            }
        }
        
        var iconColor: Color {
            switch self {
            case .info: return .scInfo
            case .warning: return .scWarning
            case .error: return .scError
            }
        }
    }
    
    init(
        icon: String,
        message: String,
        style: Style = .info,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.message = message
        self.style = style
        self.action = action
    }
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(style.iconColor)
            
            Text(message)
                .font(Typography.callout)
                .foregroundStyle(Color.scTextPrimary)
            
            Spacer()
            
            if action != nil {
                Button(action: { action?() }) {
                    Text("Fix")
                        .font(Typography.subheadline)
                        .foregroundStyle(style.iconColor)
                }
            }
        }
        .padding(Spacing.sm)
        .background(style.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Buttons") {
    VStack(spacing: 16) {
        SCButton("Continue", icon: "arrow.right", style: .primary) {}
        SCButton("Select Photos", style: .secondary) {}
        SCButton("Cancel", style: .ghost) {}
    }
    .padding()
    .background(Color.scBackground)
}

#Preview("Year Card") {
    YearCard(year: 2024, count: 1234) {}
        .padding()
        .background(Color.scBackground)
}

#Preview("Empty State") {
    EmptyStateView(
        icon: "photo.on.rectangle.angled",
        title: "No Photos",
        message: "We couldn't find any photos in your library.",
        actionTitle: "Grant Access"
    ) {}
    .background(Color.scBackground)
}

#Preview("Info Banner") {
    VStack(spacing: 12) {
        InfoBanner(icon: "info.circle", message: "Showing selected photos only", style: .info) {}
        InfoBanner(icon: "exclamationmark.triangle", message: "Limited access", style: .warning) {}
        InfoBanner(icon: "xmark.circle", message: "Access denied", style: .error)
    }
    .padding()
    .background(Color.scBackground)
}

