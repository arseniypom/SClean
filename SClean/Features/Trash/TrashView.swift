//
//  TrashView.swift
//  SClean
//
//  Trash review screen - review and restore trashed items
//

import SwiftUI
import Photos

struct TrashView: View {
    @ObservedObject var permissionService: PhotoPermissionService
    
    @StateObject private var trashService = TrashService.shared
    @State private var isSelectionMode = false
    @State private var selectedIDs: Set<String> = []
    @State private var unavailableIDs: Set<String> = []
    @State private var hasCheckedAvailability = false
    
    // Grid layout: 3 columns
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ZStack {
            Color.scBackground
                .ignoresSafeArea()

            if !permissionService.status.canAccessPhotos {
                // Access changed state with single clear action
                EmptyStateView(
                    icon: "lock.fill",
                    title: "Access Changed",
                    message: "Photo access was changed. Re-enable it in Settings to manage Trash.",
                    actionTitle: "Open Settings"
                ) {
                    permissionService.openSettings()
                }
            } else if trashService.trashCount == 0 {
                emptyState
            } else {
                content
            }
            
            // Selection mode action bar
            if isSelectionMode && !selectedIDs.isEmpty {
                selectionActionBar
            }
        }
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if trashService.trashCount > 0 {
                    Button(isSelectionMode ? "Done" : "Select") {
                        toggleSelectionMode()
                    }
                    .font(Typography.subheadline)
                    .foregroundStyle(Color.scTextPrimary)
                }
            }
        }
        .onAppear {
            if !hasCheckedAvailability {
                hasCheckedAvailability = true
                checkAndCleanupUnavailable()
            }
        }
    }
    
    // MARK: - Content
    
    private var content: some View {
        VStack(spacing: 0) {
            // Trust message header
            trustHeader
            
            // Grid of trashed items
            ScrollView {
                VStack(spacing: 0) {
                    // Limited Access banner
                    if permissionService.status.isLimited {
                        InfoBanner(
                            icon: "photo.badge.plus",
                            message: "Showing selected photos only",
                            style: .info
                        ) {
                            permissionService.presentLimitedLibraryPicker()
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                    }
                    
                    // Trash grid
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(Array(trashService.trashedItems.enumerated()), id: \.element.assetID) { index, item in
                            TrashGridCell(
                                assetID: item.assetID,
                                duration: 0, // We don't store duration in TrashedItem
                                isVideo: false, // TODO: Could store media type if needed
                                isSelected: selectedIDs.contains(item.assetID),
                                isSelectionMode: isSelectionMode
                            ) {
                                handleCellTap(item: item, index: index)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    
                    // Bottom spacing for action bar
                    if isSelectionMode {
                        Color.clear.frame(height: 100)
                    }
                }
            }
            
            // Empty Trash button (only in non-selection mode)
            if !isSelectionMode {
                emptyTrashButton
            }
        }
    }
    
    // MARK: - Trust Header
    
    private var trustHeader: some View {
        VStack(spacing: Spacing.xxs) {
            Text("Nothing is deleted until you Empty Trash")
                .font(Typography.caption1)
                .foregroundStyle(Color.scTextSecondary)

            Text("\(trashService.trashCount) \(trashService.trashCount == 1 ? "item" : "items")")
                .font(Typography.caption2)
                .foregroundStyle(Color.scTextDisabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(Color.scSurface.opacity(0.5))
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "trash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.scTextDisabled)
            
            VStack(spacing: Spacing.xs) {
                Text("Trash is Empty")
                    .font(Typography.title3)
                    .foregroundStyle(Color.scTextPrimary)
                
                Text("Items you swipe away will appear here for review before deletion.")
                    .font(Typography.body)
                    .foregroundStyle(Color.scTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Spacing.xl)
    }
    
    // MARK: - Empty Trash Button
    
    private var emptyTrashButton: some View {
        VStack(spacing: Spacing.xs) {
            SCButton("Empty Trash", icon: "trash", style: .primary) {
                // This will trigger Step 6 confirmation
                // For now, just a placeholder action
            }
            .padding(.horizontal, Spacing.md)
            
            Text("Moves items to Photos → Recently Deleted")
                .font(Typography.caption2)
                .foregroundStyle(Color.scTextDisabled)
        }
        .padding(.vertical, Spacing.md)
        .background(Color.scBackground)
    }
    
    // MARK: - Selection Action Bar
    
    private var selectionActionBar: some View {
        VStack {
            Spacer()
            
            HStack {
                Text("\(selectedIDs.count) selected")
                    .font(Typography.subheadline)
                    .foregroundStyle(Color.scTextSecondary)
                
                Spacer()
                
                Button {
                    restoreSelected()
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Restore (\(selectedIDs.count))")
                            .font(Typography.headline)
                    }
                    .foregroundStyle(Color.scTint)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .scControlSurface()
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background {
                if #available(iOS 26.0, *) {
                    Rectangle()
                        .fill(.regularMaterial)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Rectangle()
                        .fill(Color.scSurface)
                        .ignoresSafeArea(edges: .bottom)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleSelectionMode() {
        withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
            isSelectionMode.toggle()
            if !isSelectionMode {
                selectedIDs.removeAll()
            }
        }
    }
    
    private func handleCellTap(item: TrashedItem, index: Int) {
        if isSelectionMode {
            // Toggle selection
            if selectedIDs.contains(item.assetID) {
                selectedIDs.remove(item.assetID)
            } else {
                selectedIDs.insert(item.assetID)
            }
        } else {
            // Open viewer - will be handled by NavigationLink
            // For now, we wrap this in a NavigationLink in the cell
        }
    }
    
    private func restoreSelected() {
        guard !selectedIDs.isEmpty else { return }
        
        // Light haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // Restore all selected items
        trashService.restoreMultiple(selectedIDs)
        
        // Exit selection mode
        withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
            selectedIDs.removeAll()
            isSelectionMode = false
        }
    }
    
    private func checkAndCleanupUnavailable() {
        Task {
            // Check which assets still exist
            var toRemove: Set<String> = []
            
            for item in trashService.trashedItems {
                let fetchResult = PHAsset.fetchAssets(
                    withLocalIdentifiers: [item.assetID],
                    options: nil
                )
                if fetchResult.count == 0 {
                    toRemove.insert(item.assetID)
                }
            }
            
            // Silently remove unavailable items
            if !toRemove.isEmpty {
                trashService.remove(toRemove)
            }
        }
    }
}

// MARK: - Trash View with Navigation

struct TrashViewWithNavigation: View {
    @ObservedObject var permissionService: PhotoPermissionService
    @StateObject private var trashService = TrashService.shared
    @StateObject private var deletionService = DeletionService.shared
    
    @State private var isSelectionMode = false
    @State private var selectedIDs: Set<String> = []
    @State private var hasCheckedAvailability = false
    
    // Deletion flow state
    @State private var showConfirmation = false
    @State private var isDeleting = false
    @State private var deletionResult: DeletionResult?
    @State private var showResult = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ZStack {
            Color.scBackground
                .ignoresSafeArea()
            
            if trashService.trashCount == 0 && !isDeleting {
                emptyState
            } else {
                mainContent
            }
            
            // Selection action bar
            if isSelectionMode && !selectedIDs.isEmpty {
                selectionActionBar
            }
            
            // Deletion progress overlay
            if isDeleting {
                DeletionProgressView(
                    progress: deletionService.progress,
                    totalItems: trashService.trashCount
                )
            }
        }
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if trashService.trashCount > 0 && !isDeleting {
                    Button(isSelectionMode ? "Done" : "Select") {
                        toggleSelectionMode()
                    }
                    .font(Typography.subheadline)
                    .foregroundStyle(Color.scTextPrimary)
                }
            }
        }
        .sheet(isPresented: $showConfirmation) {
            EmptyTrashConfirmationView(
                itemCount: trashService.trashCount,
                isLimitedAccess: permissionService.status.isLimited,
                onConfirm: {
                    showConfirmation = false
                    performDeletion()
                },
                onCancel: {
                    showConfirmation = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showResult) {
            if let result = deletionResult {
                DeletionResultView(
                    result: result,
                    onDone: {
                        showResult = false
                        deletionResult = nil
                    },
                    onRetry: {
                        showResult = false
                        deletionResult = nil
                        // Small delay before retrying
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            performDeletion()
                        }
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            if !hasCheckedAvailability {
                hasCheckedAvailability = true
                checkAndCleanupUnavailable()
            }
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            trustHeader
            
            ScrollView {
                VStack(spacing: 0) {
                    if permissionService.status.isLimited {
                        InfoBanner(
                            icon: "photo.badge.plus",
                            message: "Showing selected photos only",
                            style: .info
                        ) {
                            permissionService.presentLimitedLibraryPicker()
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                    }
                    
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(Array(trashService.trashedItems.enumerated()), id: \.element.assetID) { index, item in
                            if isSelectionMode {
                                // Selection mode: just tap to select
                                TrashGridCell(
                                    assetID: item.assetID,
                                    duration: 0,
                                    isVideo: false,
                                    isSelected: selectedIDs.contains(item.assetID),
                                    isSelectionMode: true
                                ) {
                                    toggleSelection(item.assetID)
                                }
                            } else {
                                // Normal mode: tap opens viewer
                                NavigationLink {
                                    TrashViewerView(
                                        trashedItems: trashService.trashedItems,
                                        startIndex: index
                                    )
                                } label: {
                                    TrashGridCell(
                                        assetID: item.assetID,
                                        duration: 0,
                                        isVideo: false,
                                        isSelected: false,
                                        isSelectionMode: false
                                    ) {
                                        // Navigation handled by NavigationLink
                                    }
                                    .allowsHitTesting(false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    
                    if isSelectionMode {
                        Color.clear.frame(height: 100)
                    }
                }
            }
            
            if !isSelectionMode {
                emptyTrashButton
            }
        }
    }
    
    // MARK: - Trust Header
    
    private var trustHeader: some View {
        VStack(spacing: Spacing.xxs) {
            Text("Nothing is deleted until you Empty Trash")
                .font(Typography.caption1)
                .foregroundStyle(Color.scTextSecondary)
            
            Text("\(trashService.trashCount) \(trashService.trashCount == 1 ? "item" : "items")")
                .font(Typography.caption2)
                .foregroundStyle(Color.scTextDisabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(Color.scSurface.opacity(0.5))
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "trash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.scTextDisabled)
            
            VStack(spacing: Spacing.xs) {
                Text("Trash is Empty")
                    .font(Typography.title3)
                    .foregroundStyle(Color.scTextPrimary)
                
                Text("Items you swipe away will appear here for review before deletion.")
                    .font(Typography.body)
                    .foregroundStyle(Color.scTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Spacing.xl)
    }
    
    // MARK: - Empty Trash Button
    
    private var emptyTrashButton: some View {
        VStack(spacing: Spacing.xs) {
            SCButton("Empty Trash", icon: "trash", style: .primary) {
                showConfirmation = true
            }
            .padding(.horizontal, Spacing.md)
            .disabled(trashService.trashCount == 0 || isDeleting)
            
            Text("Moves items to Photos → Recently Deleted")
                .font(Typography.caption2)
                .foregroundStyle(Color.scTextDisabled)
        }
        .padding(.vertical, Spacing.md)
        .background(Color.scBackground)
    }
    
    // MARK: - Selection Action Bar
    
    private var selectionActionBar: some View {
        VStack {
            Spacer()
            
            HStack {
                Text("\(selectedIDs.count) selected")
                    .font(Typography.subheadline)
                    .foregroundStyle(Color.scTextSecondary)
                
                Spacer()
                
                Button {
                    restoreSelected()
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Restore (\(selectedIDs.count))")
                            .font(Typography.headline)
                    }
                    .foregroundStyle(Color.scTint)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .scControlSurface()
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background {
                if #available(iOS 26.0, *) {
                    Rectangle()
                        .fill(.regularMaterial)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Rectangle()
                        .fill(Color.scSurface)
                        .ignoresSafeArea(edges: .bottom)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleSelectionMode() {
        withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
            isSelectionMode.toggle()
            if !isSelectionMode {
                selectedIDs.removeAll()
            }
        }
    }
    
    private func toggleSelection(_ assetID: String) {
        if selectedIDs.contains(assetID) {
            selectedIDs.remove(assetID)
        } else {
            selectedIDs.insert(assetID)
        }
    }
    
    private func restoreSelected() {
        guard !selectedIDs.isEmpty else { return }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        trashService.restoreMultiple(selectedIDs)
        
        withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
            selectedIDs.removeAll()
            isSelectionMode = false
        }
    }
    
    private func checkAndCleanupUnavailable() {
        Task {
            var toRemove: Set<String> = []
            
            for item in trashService.trashedItems {
                let fetchResult = PHAsset.fetchAssets(
                    withLocalIdentifiers: [item.assetID],
                    options: nil
                )
                if fetchResult.count == 0 {
                    toRemove.insert(item.assetID)
                }
            }
            
            if !toRemove.isEmpty {
                trashService.remove(toRemove)
            }
        }
    }
    
    // MARK: - Deletion Flow
    
    private func performDeletion() {
        // Get all asset IDs to delete
        let assetIDsToDelete = trashService.orderedTrashedIDs
        
        guard !assetIDsToDelete.isEmpty else { return }
        
        isDeleting = true
        
        Task {
            // Perform the deletion
            let result = await deletionService.deleteAssets(assetIDsToDelete)
            
            // Update trash service with successfully deleted items
            if result.deletedCount > 0 {
                // Calculate which IDs were deleted (all except failed)
                let failedSet = Set(result.failedIDs)
                let deletedIDs = assetIDsToDelete.filter { !failedSet.contains($0) }
                trashService.markDeleted(deletedIDs)
            }
            
            isDeleting = false
            
            // Show result (unless user cancelled and nothing happened)
            if result.error != .userCancelled || result.deletedCount > 0 {
                deletionResult = result
                showResult = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TrashViewWithNavigation(permissionService: PhotoPermissionService())
    }
}
