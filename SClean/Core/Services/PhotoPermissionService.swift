//
//  PhotoPermissionService.swift
//  SClean
//
//  Handles Photos library permission requests and status
//

import Photos
import PhotosUI
import SwiftUI
import Combine

// MARK: - Permission Status

enum PhotoPermissionStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted
    
    var canAccessPhotos: Bool {
        switch self {
        case .authorized, .limited:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        }
    }
    
    var isLimited: Bool {
        self == .limited
    }
}

// MARK: - Photo Permission Service

@MainActor
final class PhotoPermissionService: ObservableObject {
    
    @Published private(set) var status: PhotoPermissionStatus = .notDetermined
    
    init() {
        updateStatus()
    }
    
    // MARK: - Public Methods
    
    /// Requests photo library access. Returns the new status.
    func requestAccess() async -> PhotoPermissionStatus {
        let phStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        updateStatus(from: phStatus)
        return status
    }
    
    /// Refreshes the current permission status
    func refreshStatus() {
        updateStatus()
    }
    
    /// Opens the limited photo picker to add more photos
    func presentLimitedLibraryPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
            let rootViewController = windowScene.windows.first?.rootViewController else { return }
        
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController)
    }
    
    /// Opens system settings for the app
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    
    // MARK: - Private Methods
    
    private func updateStatus() {
        let phStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        updateStatus(from: phStatus)
    }
    
    private func updateStatus(from phStatus: PHAuthorizationStatus) {
        status = mapStatus(phStatus)
    }
    
    private func mapStatus(_ phStatus: PHAuthorizationStatus) -> PhotoPermissionStatus {
        switch phStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }
    
    /// Call this when the app becomes active to refresh permission status
    func handleAppBecameActive() {
        refreshStatus()
    }
}
