//
//  UndoToast.swift
//  SClean
//
//  Bottom snackbar with undo action
//

import SwiftUI

struct UndoToast: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    /// Auto-dismiss duration in seconds
    private let dismissDelay: TimeInterval = 4.0
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            // Trash icon
            Image(systemName: "trash")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            
            // Message
            Text(message)
                .font(Typography.callout)
                .foregroundStyle(.white)
            
            Spacer()
            
            // Undo button
            Button(action: {
                withAnimation(.easeOut(duration: AnimationDuration.fast)) {
                    isVisible = false
                }
                onUndo()
            }) {
                Text("Undo")
                    .font(Typography.headline)
                    .foregroundStyle(Color.scAccent)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .toastBackground()
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 50)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isVisible = true
            }
            
            // Schedule auto-dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
                dismiss()
            }
        }
    }
    
    private func dismiss() {
        withAnimation(.easeOut(duration: AnimationDuration.fast)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationDuration.fast) {
            onDismiss()
        }
    }
}

// MARK: - Toast Background Modifier

private extension View {
    @ViewBuilder
    func toastBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                .glassEffect()
        } else {
            self
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        }
    }
}

// MARK: - Toast Container Modifier

struct ToastContainerModifier: ViewModifier {
    @Binding var toast: ToastData?
    
    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            
            if let toast {
                UndoToast(
                    message: toast.message,
                    onUndo: {
                        toast.onUndo()
                        self.toast = nil
                    },
                    onDismiss: {
                        self.toast = nil
                    }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toast != nil)
    }
}

// MARK: - Toast Data

struct ToastData: Equatable {
    let id: UUID
    let message: String
    let onUndo: () -> Void
    
    init(message: String, onUndo: @escaping () -> Void) {
        self.id = UUID()
        self.message = message
        self.onUndo = onUndo
    }
    
    static func == (lhs: ToastData, rhs: ToastData) -> Bool {
        lhs.id == rhs.id
    }
}

extension View {
    func undoToast(_ toast: Binding<ToastData?>) -> some View {
        modifier(ToastContainerModifier(toast: toast))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            UndoToast(
                message: "Moved to Trash",
                onUndo: {},
                onDismiss: {}
            )
            .padding()
        }
    }
}


