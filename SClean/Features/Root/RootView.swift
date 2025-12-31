//
//  RootView.swift
//  SClean
//
//  Main app coordinator - handles permission flow and navigation
//

import SwiftUI

struct RootView: View {
    @StateObject private var permissionService = PhotoPermissionService()
    
    @State private var hasRequestedPermission = false
    
    var body: some View {
        Group {
            if permissionService.status.canAccessPhotos {
                HomeView(permissionService: permissionService)
            } else {
                PermissionView(permissionService: permissionService) {
                    // Permission granted callback
                    hasRequestedPermission = true
                }
            }
        }
        .animation(.easeInOut(duration: AnimationDuration.normal), value: permissionService.status)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            permissionService.handleAppBecameActive()
        }
    }
}

// MARK: - Preview

#Preview {
    RootView()
}







