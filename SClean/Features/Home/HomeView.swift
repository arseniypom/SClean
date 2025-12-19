//
//  HomeView.swift
//  SClean
//
//  Years list home screen
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var permissionService: PhotoPermissionService
    @StateObject private var libraryService = PhotoLibraryService()
    
    @State private var hasAppeared = false
    @State private var cachedYears: [YearBucket] = []
    @State private var isRefreshing = false
    
    private var canRefresh: Bool {
        if case .loaded = libraryService.state { return true }
        if !cachedYears.isEmpty { return true }
        return false
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomLeading) {
                Color.scBackground
                    .ignoresSafeArea()
                
                content
                
                // Floating refresh button (bottom-left)
                if canRefresh {
                    refreshButton
                        .padding(.leading, Spacing.md)
                        .padding(.bottom, Spacing.lg)
                }
            }
            .navigationTitle("Years")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.scPrimary)
                    }
                }
            }
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    loadData()
                }
            }
            .onChange(of: libraryService.state) { _, newValue in
                if case .loaded(let years) = newValue {
                    cachedYears = years
                }
                if case .empty = newValue {
                    cachedYears = []
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                permissionService.refreshStatus()
                if hasAppeared && permissionService.status.canAccessPhotos {
                    Task { await libraryService.refresh() }
                }
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch libraryService.state {
        case .idle, .loading:
            if cachedYears.isEmpty {
                LoadingStateView(message: "Indexing years…")
            } else {
                yearsList(cachedYears)
            }
            
        case .loaded(let years):
            yearsList(years)
            
        case .empty:
            EmptyStateView(
                icon: "photo.on.rectangle.angled",
                title: "No Photos",
                message: "We couldn't find any photos in your library."
            )
            
        case .error(let message):
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Something went wrong",
                message: message,
                actionTitle: "Try Again"
            ) {
                loadData()
            }
        }
    }
    
    private func yearsList(_ years: [YearBucket]) -> some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                // Limited access banner
                if permissionService.status.isLimited {
                    InfoBanner(
                        icon: "photo.badge.plus",
                        message: "Showing selected photos only",
                        style: .info
                    ) {
                        permissionService.presentLimitedLibraryPicker()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
                }
                
                // Year cards
                ForEach(years) { bucket in
                    YearCard(year: bucket.year, count: bucket.count) {
                        // TODO: Navigate to year grid (Step 2)
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
            .padding(.vertical, Spacing.sm)
        }
    }
    
    private func loadData() {
        libraryService.startObservingChanges()
        Task {
            await libraryService.fetchYears()
        }
    }
    
    // MARK: - Refresh Button
    
    private var refreshButton: some View {
        Button {
            guard !isRefreshing else { return }
            isRefreshing = true
            Task {
                await libraryService.refresh()
                isRefreshing = false
            }
        } label: {
            refreshButtonContent
        }
        .disabled(isRefreshing)
    }
    
    @ViewBuilder
    private var refreshButtonContent: some View {
        Group {
            if isRefreshing {
                ProgressView()
                    .tint(.scPrimary)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.scPrimary)
            }
        }
        .frame(width: 56, height: 56)
        .scFloatingButtonStyle()
    }
}

// MARK: - Total Count

private extension HomeView {
    var totalCount: Int {
        libraryService.state.years.reduce(0) { $0 + $1.count }
    }
}

// MARK: - Preview

#Preview {
    let service = PhotoPermissionService()
    return HomeView(permissionService: service)
}

