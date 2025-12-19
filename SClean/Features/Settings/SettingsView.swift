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

struct SettingsView: View {
    var body: some View {
        ZStack {
            Color.scBackground
                .ignoresSafeArea()
            
            Text("Settings coming soon")
                .font(Typography.body)
                .foregroundStyle(Color.scTextSecondary)
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

