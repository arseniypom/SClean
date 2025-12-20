//
//  DeletionProgressView.swift
//  SClean
//
//  Blocking overlay shown during deletion
//

import SwiftUI

struct DeletionProgressView: View {
    let progress: DeletionProgress?
    let totalItems: Int
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            // Progress card
            VStack(spacing: Spacing.lg) {
                // Spinner
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.scPrimary)
                
                // Label
                VStack(spacing: Spacing.xs) {
                    Text("Deleting...")
                        .font(Typography.headline)
                        .foregroundStyle(Color.scTextPrimary)
                    
                    // Progress count
                    if let progress = progress {
                        Text("Deleting \(progress.current) of \(progress.total)...")
                            .font(Typography.caption1)
                            .foregroundStyle(Color.scTextSecondary)
                            .monospacedDigit()
                    } else {
                        Text("\(totalItems) \(totalItems == 1 ? "item" : "items")")
                            .font(Typography.caption1)
                            .foregroundStyle(Color.scTextSecondary)
                    }
                }
            }
            .padding(Spacing.xl)
            .scCardStyle()
        }
        .allowsHitTesting(true) // Block interaction with underlying content
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.scBackground
            .ignoresSafeArea()
        
        Text("Background Content")
        
        DeletionProgressView(
            progress: DeletionProgress(current: 34, total: 132),
            totalItems: 132
        )
    }
}

