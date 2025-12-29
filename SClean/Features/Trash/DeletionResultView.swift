//
//  DeletionResultView.swift
//  SClean
//
//  Result sheet after deletion completes
//

import SwiftUI

struct DeletionResultView: View {
    let result: DeletionResult
    let onDone: () -> Void
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Icon
            resultIcon
            
            // Title and message
            resultContent
            
            // Actions
            resultActions
        }
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.md)
        .onAppear {
            // Success haptic
            if result.isFullSuccess {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            } else if result.isPartialSuccess {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            } else {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }
    
    // MARK: - Icon
    
    @ViewBuilder
    private var resultIcon: some View {
        ZStack {
            Circle()
                .fill(iconBackgroundColor)
                .frame(width: 80, height: 80)
            
            Image(systemName: iconName)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(iconColor)
        }
    }
    
    private var iconName: String {
        if result.isFullSuccess {
            return "checkmark.circle.fill"
        } else if result.isPartialSuccess {
            return "exclamationmark.triangle.fill"
        } else {
            return "xmark.circle.fill"
        }
    }
    
    private var iconColor: Color {
        if result.isFullSuccess {
            return .scSuccess
        } else if result.isPartialSuccess {
            return .scWarning
        } else {
            return .scError
        }
    }
    
    private var iconBackgroundColor: Color {
        iconColor.opacity(0.1)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var resultContent: some View {
        VStack(spacing: Spacing.sm) {
            Text(title)
                .font(Typography.title2)
                .foregroundStyle(Color.scTextPrimary)
            
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Color.scTextSecondary)
                .multilineTextAlignment(.center)
            
            if let errorMessage = result.error?.localizedDescription, result.isFailure {
                Text(errorMessage)
                    .font(Typography.caption1)
                    .foregroundStyle(Color.scError)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.md)
    }
    
    private var title: String {
        if result.isFullSuccess {
            return "Trash Emptied"
        } else if result.isPartialSuccess {
            return "Partially Deleted"
        } else {
            return "Couldn't Delete Items"
        }
    }
    
    private var message: String {
        if result.isFullSuccess {
            return "Trash emptied. You can recover items in Photos → Recently Deleted for a limited time."
        } else if result.isPartialSuccess {
            return "Deleted \(result.deletedCount). \(result.failedIDs.count) couldn't be deleted. Review remaining items."
        } else if result.error == .userCancelled {
            return "You cancelled the deletion."
        } else {
            return "We couldn't delete the items. Please try again."
        }
    }
    
    // MARK: - Actions
    
    @ViewBuilder
    private var resultActions: some View {
        VStack(spacing: Spacing.sm) {
            if result.isFullSuccess {
                // Done button
                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .font(Typography.headline)
                        .foregroundStyle(Color.scTextPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background {
                            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                .stroke(Color.scBorder, lineWidth: StrokeWidth.hairline)
                        }
                }
                
            } else if result.isPartialSuccess {
                // Review remaining + Try again
                Button {
                    onDone()
                } label: {
                    Text("Review Remaining Items")
                        .font(Typography.headline)
                        .foregroundStyle(Color.scTextPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background {
                            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                .stroke(Color.scBorder, lineWidth: StrokeWidth.hairline)
                        }
                }
                
                Button {
                    onRetry()
                } label: {
                    Text("Try Again")
                        .font(Typography.headline)
                        .foregroundStyle(Color.scTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                }
                
            } else {
                // Failure - Try again + Cancel
                Button {
                    onRetry()
                } label: {
                    Text("Try Again")
                        .font(Typography.headline)
                        .foregroundStyle(Color.scTextPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background {
                            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                .stroke(Color.scBorder, lineWidth: StrokeWidth.hairline)
                        }
                }
                
                Button {
                    onDone()
                } label: {
                    Text("Cancel")
                        .font(Typography.headline)
                        .foregroundStyle(Color.scTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
    }
}

// MARK: - Previews

#Preview("Success") {
    DeletionResultView(
        result: DeletionResult(deletedCount: 132, failedIDs: [], error: nil),
        onDone: {},
        onRetry: {}
    )
    .background(Color.scBackground)
}

#Preview("Partial Success") {
    DeletionResultView(
        result: DeletionResult(deletedCount: 120, failedIDs: ["1", "2", "3"], error: nil),
        onDone: {},
        onRetry: {}
    )
    .background(Color.scBackground)
}

#Preview("Failure") {
    DeletionResultView(
        result: DeletionResult(deletedCount: 0, failedIDs: ["1", "2"], error: .permissionDenied),
        onDone: {},
        onRetry: {}
    )
    .background(Color.scBackground)
}

#Preview("Cancelled") {
    DeletionResultView(
        result: DeletionResult(deletedCount: 0, failedIDs: [], error: .userCancelled),
        onDone: {},
        onRetry: {}
    )
    .background(Color.scBackground)
}


