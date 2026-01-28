//
//  ViewerOnboardingView.swift
//  SClean
//
//  Two-step onboarding for the media viewer
//

import SwiftUI
import UIKit

struct ViewerOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Step content with transition
            Group {
                if currentStep == 0 {
                    OnboardingStepContent(
                        icon: "arrow.left.and.right",
                        title: "Swipe to Browse",
                        subtitle: "Swipe left or right to navigate through your photos"
                    )
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                } else {
                    OnboardingStepContent(
                        icon: "arrow.up",
                        title: "Swipe to Trash",
                        subtitle: "Swipe up to mark a photo for deletion"
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .animation(.easeInOut(duration: AnimationDuration.normal), value: currentStep)

            Spacer()

            // Action button
            SCButton(currentStep == 0 ? "Next" : "Got it", style: .primary) {
                advanceStep()
            }
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xl)
        .background(Color.scBackground)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }

    private func advanceStep() {
        if currentStep == 0 {
            withAnimation(.easeInOut(duration: AnimationDuration.normal)) {
                currentStep = 1
            }
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Persist completion
        UserDefaults.standard.set(true, forKey: "SClean.hasCompletedViewerOnboarding")

        dismiss()
    }
}

// MARK: - Step Content

private struct OnboardingStepContent: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Big bold icon
            Image(systemName: icon)
                .font(.system(size: 80, weight: .bold))
                .foregroundStyle(Color.scTextPrimary)

            VStack(spacing: Spacing.sm) {
                // Title
                Text(title)
                    .font(Typography.title1)
                    .foregroundStyle(Color.scTextPrimary)
                    .multilineTextAlignment(.center)

                // Subtitle
                Text(subtitle)
                    .font(Typography.body)
                    .foregroundStyle(Color.scTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Preview

#Preview("Step 1 - Navigation") {
    ViewerOnboardingView()
}
