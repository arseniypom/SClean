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
    @StateObject private var trashService = TrashService.shared
    @StateObject private var statsService = StatsService.shared
    
    @State private var hasAppeared = false
    @State private var cachedYears: [YearBucket] = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.scBackground
                    .ignoresSafeArea()
                
                content
            }
            .overlay(alignment: .bottomLeading) {
                // Floating trash button (bottom-left)
                if trashService.trashCount > 0 {
                    floatingTrashButton
                        .padding(.leading, Spacing.md)
                        .padding(.bottom, Spacing.lg)
                }
            }
            .navigationTitle("SClean")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(libraryService: libraryService)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.scTextPrimary)
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
                LoadingStateView(
                    message: "Indexing years…",
                    detail: "Runs in the background and may take a moment the first time.",
                    showsProgressBar: true,
                    progress: libraryService.indexingProgress
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Spacing.xl)
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
                // Stats card (always visible)
                StatsCardView(statsService: statsService)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
                
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
                }
                
                // Years section header
                HStack {
                    Text("Years")
                        .font(Typography.title2)
                        .foregroundStyle(Color.scTextPrimary)
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                
                // Year cards
                ForEach(years) { bucket in
                    NavigationLink {
                        YearGridView(
                            year: bucket.year,
                            itemCount: bucket.count,
                            permissionService: permissionService
                        )
                    } label: {
                        YearCardContent(year: bucket.year, count: bucket.count, totalBytes: bucket.totalBytes)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Spacing.md)
                }
                
                // Bottom spacer for floating button
                if trashService.trashCount > 0 {
                    Color.clear
                        .frame(height: 80)
                }
            }
            .padding(.vertical, Spacing.sm)
        }
    }
    
    // MARK: - Floating Trash Button
    
    private var floatingTrashButton: some View {
        NavigationLink {
            TrashViewWithNavigation(permissionService: permissionService)
        } label: {
            floatingTrashButtonContent
        }
    }
    
    private var floatingTrashButtonContent: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "trash")
                .font(.system(size: 18, weight: .semibold))
            
            Text("\(trashService.trashCount)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.scTextPrimary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .scFloatingButtonStyle()
    }
    
    private func loadData() {
        libraryService.startObservingChanges()
        Task {
            await libraryService.fetchYears()
        }
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
