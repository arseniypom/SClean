//
//  HomeView.swift
//  SClean
//
//  Years list home screen
//

import SwiftUI

// MARK: - Home Tab

private enum HomeTab: String, CaseIterable {
    case years
    case months
    case types
    case insights
}

struct HomeView: View {
    @ObservedObject var permissionService: PhotoPermissionService
    @StateObject private var libraryService = PhotoLibraryService()
    @StateObject private var trashService = TrashService.shared
    @StateObject private var statsService = StatsService.shared

    @State private var selectedTab: HomeTab = .years
    @State private var hasAppeared = false
    @State private var cachedYears: [YearBucket] = []
    @State private var cachedMonths: [MonthBucket] = []
    @State private var cachedTypes: [TypeBucket] = []
    @State private var cachedInsights: [InsightBucket] = []
    
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
                    cachedMonths = libraryService.monthBuckets
                    cachedTypes = libraryService.typeBuckets
                    cachedInsights = libraryService.insightBuckets
                }
                if case .empty = newValue {
                    cachedYears = []
                    cachedMonths = []
                    cachedTypes = []
                    cachedInsights = []
                }
            }
            .onChange(of: libraryService.insightBuckets) { _, newValue in
                cachedInsights = newValue
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
                IndexingProgressView(
                    progress: libraryService.indexingProgress,
                    detail: "May take a moment the first time"
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
        let months = cachedMonths.isEmpty ? libraryService.monthBuckets : cachedMonths
        let types = cachedTypes.isEmpty ? libraryService.typeBuckets : cachedTypes
        let insights = cachedInsights.isEmpty ? libraryService.insightBuckets : cachedInsights

        return ScrollView {
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

                // Tab toggle header
                HStack(spacing: Spacing.md) {
                    TabHeaderButton(
                        title: "Years",
                        isSelected: selectedTab == .years
                    ) {
                        selectedTab = .years
                    }

                    TabHeaderButton(
                        title: "Months",
                        isSelected: selectedTab == .months
                    ) {
                        selectedTab = .months
                    }

                    TabHeaderButton(
                        title: "Types",
                        isSelected: selectedTab == .types
                    ) {
                        selectedTab = .types
                    }

                    TabHeaderButton(
                        title: "Insights",
                        isSelected: selectedTab == .insights
                    ) {
                        selectedTab = .insights
                    }

                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

                // Content based on selected tab
                if selectedTab == .years {
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
                        .accessibilityIdentifier("yearCard_\(bucket.year)")
                        .padding(.horizontal, Spacing.md)
                    }
                } else if selectedTab == .months {
                    // Month cards
                    ForEach(months) { bucket in
                        NavigationLink {
                            MonthGridView(
                                bucket: bucket,
                                permissionService: permissionService
                            )
                        } label: {
                            MonthCardContent(bucket: bucket)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("monthCard_\(bucket.id)")
                        .padding(.horizontal, Spacing.md)
                    }
                } else if selectedTab == .types {
                    // Type cards
                    ForEach(types) { bucket in
                        NavigationLink {
                            TypeGridView(
                                bucket: bucket,
                                snapshot: libraryService.currentSnapshot,
                                permissionService: permissionService
                            )
                        } label: {
                            TypeCardContent(bucket: bucket)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("typeCard_\(bucket.id)")
                        .padding(.horizontal, Spacing.md)
                    }
                } else {
                    if !insights.isEmpty {
                        InsightsHeroCard(
                            reclaimableBytes: libraryService.reclaimableBytes,
                            candidateCount: libraryService.reclaimableCount,
                            isAnalyzing: libraryService.isAnalyzingInsights
                        )
                        .padding(.horizontal, Spacing.md)

                        ForEach(insights) { bucket in
                            NavigationLink {
                                InsightGridView(
                                    bucket: bucket,
                                    snapshot: libraryService.currentSnapshot,
                                    permissionService: permissionService
                                )
                            } label: {
                                InsightCardContent(bucket: bucket)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("insightCard_\(bucket.id)")
                            .padding(.horizontal, Spacing.md)
                        }
                    } else if libraryService.isAnalyzingInsights {
                        InsightAnalyzingCard()
                            .padding(.horizontal, Spacing.md)
                    } else {
                        InsightEmptyCard()
                            .padding(.horizontal, Spacing.md)
                    }
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
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: trashService.trashCount)
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

// MARK: - Insights Hero

/// Motivational summary above the insight cards: the de-duplicated total the
/// user could free, plus a subtle live indicator while content analysis runs.
private struct InsightsHeroCard: View {
    let reclaimableBytes: Int64
    let candidateCount: Int
    let isAnalyzing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Free up \(formattedBytes)")
                .font(Typography.title1)
                .foregroundStyle(Color.scTint)
                .contentTransition(.numericText())
                .animation(.snappy, value: reclaimableBytes)

            Text("\(candidateCount) items you likely don't need")
                .font(Typography.subheadline)
                .foregroundStyle(Color.scTextSecondary)

            if isAnalyzing {
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.scTextSecondary)
                    Text("Analyzing your library…")
                        .font(Typography.caption1)
                        .foregroundStyle(Color.scTextSecondary)
                }
                .padding(.top, Spacing.xxs)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .scCardStyle()
        .animation(.easeInOut(duration: 0.2), value: isAnalyzing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You can free up \(formattedBytes) across \(candidateCount) items")
    }

    private var formattedBytes: String {
        let gb = Double(reclaimableBytes) / 1_073_741_824
        let mb = Double(reclaimableBytes) / 1_048_576
        if gb >= 1.0 {
            return String(format: "~%.1f GB", gb)
        } else if mb >= 1.0 {
            return String(format: "~%.0f MB", mb)
        } else {
            return "< 1 MB"
        }
    }
}

/// Shown on the Insights tab while background analysis runs and no
/// insight has surfaced yet, so cards don't just silently appear.
private struct InsightAnalyzingCard: View {
    var body: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .tint(Color.scTextSecondary)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Analyzing your library…")
                    .font(Typography.title3)
                    .foregroundStyle(Color.scTextPrimary)

                Text("Cleanup insights will appear here shortly.")
                    .font(Typography.subheadline)
                    .foregroundStyle(Color.scTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .scCardStyle()
    }
}

private struct InsightEmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("No quick cleanups right now")
                .font(Typography.title3)
                .foregroundStyle(Color.scTextPrimary)

            Text("Insights will appear when SClean finds safe batch cleanup opportunities.")
                .font(Typography.subheadline)
                .foregroundStyle(Color.scTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .scCardStyle()
    }
}

// MARK: - Total Count

private extension HomeView {
    var totalCount: Int {
        libraryService.state.years.reduce(0) { $0 + $1.count }
    }
}

// MARK: - Tab Header Button

private struct TabHeaderButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.title2)
                .foregroundStyle(isSelected ? Color.scTextPrimary : Color.scTextDisabled)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    let service = PhotoPermissionService()
    return HomeView(permissionService: service)
}

#Preview("Insights Hero") {
    VStack(spacing: Spacing.sm) {
        InsightsHeroCard(
            reclaimableBytes: 2_040_109_465,
            candidateCount: 312,
            isAnalyzing: true
        )
        InsightAnalyzingCard()
        InsightEmptyCard()
    }
    .padding(Spacing.md)
    .background(Color.scBackground)
}
