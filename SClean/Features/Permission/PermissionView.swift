//
//  PermissionView.swift
//  SClean
//
//  Permission request and blocked state screens
//

import SwiftUI

struct PermissionView: View {
    @ObservedObject var permissionService: PhotoPermissionService
    let onGranted: () -> Void
    
    @State private var isRequesting = false
    
    var body: some View {
        ZStack {
            Color.scBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                content
                
                Spacer()
                
                footer
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch permissionService.status {
        case .notDetermined:
            requestContent
        case .denied, .restricted:
            blockedContent
        case .authorized, .limited:
            // Shouldn't show this view in these states
            EmptyView()
        }
    }
    
    // MARK: - Request Content
    
    private var requestContent: some View {
        VStack(spacing: Spacing.xl) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.scPrimary.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color.scPrimary)
            }
            
            // Text
            VStack(spacing: Spacing.sm) {
                Text("Access Your Photos")
                    .font(Typography.title1)
                    .foregroundStyle(Color.scTextPrimary)
                
                Text("We need access to your photo library to show your photos by year. Nothing is deleted until you explicitly empty the trash.")
                    .font(Typography.body)
                    .foregroundStyle(Color.scTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Trust indicators
            VStack(alignment: .leading, spacing: Spacing.sm) {
                trustItem(icon: "lock.shield", text: "Your photos stay on device")
                trustItem(icon: "trash.slash", text: "Nothing deleted without your action")
                trustItem(icon: "eye.slash", text: "We don't upload or share anything")
            }
            .padding(Spacing.md)
            .background(Color.scSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        }
    }
    
    private func trustItem(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.scPrimary)
                .frame(width: 24)
            
            Text(text)
                .font(Typography.callout)
                .foregroundStyle(Color.scTextPrimary)
        }
    }
    
    // MARK: - Blocked Content
    
    private var blockedContent: some View {
        VStack(spacing: Spacing.xl) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.scError.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color.scError)
            }
            
            // Text
            VStack(spacing: Spacing.sm) {
                Text("Access Required")
                    .font(Typography.title1)
                    .foregroundStyle(Color.scTextPrimary)
                
                Text("SlideClean needs access to your photos to help you organize and clean your library. Please enable access in Settings.")
                    .font(Typography.body)
                    .foregroundStyle(Color.scTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - Footer
    
    @ViewBuilder
    private var footer: some View {
        switch permissionService.status {
        case .notDetermined:
            SCButton("Continue", icon: "arrow.right") {
                requestPermission()
            }
            .disabled(isRequesting)
            
        case .denied, .restricted:
            SCButton("Open Settings", icon: "gear") {
                permissionService.openSettings()
            }
            
        case .authorized, .limited:
            EmptyView()
        }
    }
    
    // MARK: - Actions
    
    private func requestPermission() {
        isRequesting = true
        
        Task {
            let status = await permissionService.requestAccess()
            isRequesting = false
            
            if status.canAccessPhotos {
                onGranted()
            }
        }
    }
}

// MARK: - Preview

#Preview("Request") {
    let service = PhotoPermissionService()
    return PermissionView(permissionService: service, onGranted: {})
}


