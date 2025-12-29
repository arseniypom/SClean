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

private struct LibraryActionsCard: View {
    @ObservedObject var libraryService: PhotoLibraryService
    @State private var isRefreshing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Library")
                .font(Typography.subheadline)
                .foregroundStyle(Color.scTextSecondary)
            
            Text("Refresh the media index if something looks out of date.")
                .font(Typography.body)
                .foregroundStyle(Color.scTextSecondary)
            
            SCButton(buttonTitle, icon: buttonIcon, style: .secondary) {
                refreshLibrary()
            }
            .disabled(isRefreshing || libraryService.state.isLoading)
        }
        .padding(Spacing.md)
        .scCardStyle()
    }
    
    private var buttonTitle: String {
        (isRefreshing || libraryService.state.isLoading) ? "Refreshing…" : "Refresh Library"
    }
    
    private var buttonIcon: String? {
        (isRefreshing || libraryService.state.isLoading) ? nil : "arrow.clockwise"
    }
    
    private func refreshLibrary() {
        guard !isRefreshing, !libraryService.state.isLoading else { return }
        isRefreshing = true
        Task { @MainActor in
            await libraryService.refresh()
            isRefreshing = false
        }
    }
}

struct SettingsView: View {
    @ObservedObject var libraryService: PhotoLibraryService
    
    var body: some View {
        ZStack {
            Color.scBackground
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    // Appearance card
                    AppearancePicker()
                    
                    LibraryActionsCard(libraryService: libraryService)
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
        SettingsView(libraryService: PhotoLibraryService())
    }
}
