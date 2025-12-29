//
//  EmptyTrashConfirmationView.swift
//  SClean
//
//  Confirmation sheet for emptying trash
//

import SwiftUI

struct EmptyTrashConfirmationView: View {
    let itemCount: Int
    let isLimitedAccess: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    /// Threshold for requiring hold-to-confirm
    private let holdToConfirmThreshold = 200
    
    /// Whether to use hold-to-confirm for large batches
    private var requiresHoldToConfirm: Bool {
        itemCount > holdToConfirmThreshold
    }
    
    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTimer: Timer?
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.scError.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "trash.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.scError)
            }
            
            // Title
            Text("Empty Trash?")
                .font(Typography.title2)
                .foregroundStyle(Color.scTextPrimary)
            
            // Body text
            VStack(spacing: Spacing.sm) {
                Text("This will delete \(itemCount) \(itemCount == 1 ? "item" : "items") from your Photos library.")
                    .font(Typography.body)
                    .foregroundStyle(Color.scTextPrimary)
                    .multilineTextAlignment(.center)
                
                Text("You may still be able to recover them in Photos → Recently Deleted for a limited time.")
                    .font(Typography.callout)
                    .foregroundStyle(Color.scTextSecondary)
                    .multilineTextAlignment(.center)
                
                // Limited access note
                if isLimitedAccess {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .medium))
                        Text("You can only delete items you've allowed access to.")
                            .font(Typography.caption1)
                    }
                    .foregroundStyle(Color.scInfo)
                    .padding(.top, Spacing.xs)
                }
            }
            .padding(.horizontal, Spacing.md)
            
            // Actions
            VStack(spacing: Spacing.sm) {
                // Delete button
                if requiresHoldToConfirm {
                    holdToConfirmButton
                } else {
                    deleteButton
                }
                
                // Cancel button
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(Typography.headline)
                        .foregroundStyle(Color.scTint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
        }
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.md)
    }
    
    // MARK: - Delete Button
    
    private var deleteButton: some View {
        Button {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            onConfirm()
        } label: {
            Text("Delete \(itemCount) \(itemCount == 1 ? "Item" : "Items")")
                .font(Typography.headline)
                .foregroundStyle(Color.scError)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .stroke(Color.scError.opacity(0.3), lineWidth: StrokeWidth.hairline)
                }
        }
    }
    
    // MARK: - Hold to Confirm Button
    
    private var holdToConfirmButton: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(Color.scError.opacity(0.2))
            
            // Progress fill
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color.scError)
                    .frame(width: geometry.size.width * holdProgress)
            }
            
            // Label
            Text(isHolding ? "Hold to Delete..." : "Hold to Delete \(itemCount) Items")
                .font(Typography.headline)
                .foregroundStyle(holdProgress > 0.5 ? .white : Color.scError)
        }
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isHolding {
                        startHold()
                    }
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
    }
    
    private func startHold() {
        isHolding = true
        holdProgress = 0
        
        // Start timer for hold progress
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            withAnimation(.linear(duration: 0.02)) {
                holdProgress += 0.02 // Complete in ~1 second
            }
            
            if holdProgress >= 1.0 {
                timer.invalidate()
                holdTimer = nil
                
                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                onConfirm()
            }
        }
    }
    
    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        
        withAnimation(.easeOut(duration: AnimationDuration.fast)) {
            isHolding = false
            holdProgress = 0
        }
    }
}

// MARK: - Preview

#Preview("Small Batch") {
    EmptyTrashConfirmationView(
        itemCount: 23,
        isLimitedAccess: false,
        onConfirm: {},
        onCancel: {}
    )
    .background(Color.scBackground)
}

#Preview("Large Batch") {
    EmptyTrashConfirmationView(
        itemCount: 350,
        isLimitedAccess: true,
        onConfirm: {},
        onCancel: {}
    )
    .background(Color.scBackground)
}



