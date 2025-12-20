//
//  SettingsView.swift
//  SClean
//
//  Settings screen (placeholder)
//
//  Note: Per Liquid Glass rules, full-screen backgrounds should NOT use glass.
//  Glass is for controls/overlays, not destination screens.
//

import SwiftUI

private struct AppearancePicker: View {
    @AppStorage(AppearanceMode.storageKey) private var storedAppearance: String = AppearanceMode.system.rawValue
    
    private var selectionBinding: Binding<AppearanceMode> {
        Binding<AppearanceMode>(
            get: { AppearanceMode.from(raw: storedAppearance) },
            set: { storedAppearance = $0.rawValue }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Appearance")
                .font(Typography.subheadline)
                .foregroundStyle(Color.scTextSecondary)
            
            Picker("Appearance", selection: selectionBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(Spacing.md)
        .scCardStyle()
        .accessibilityLabel("Appearance")
    }
}

struct SettingsView: View {
    var body: some View {
        ZStack {
            Color.scBackground
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    // Appearance card
                    AppearancePicker()
                    
                    // Additional settings can go here
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        // Use system back button (prefer system components)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
