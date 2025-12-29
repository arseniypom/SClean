//
//  StatsService.swift
//  SClean
//
//  Tracks and persists lifetime deletion statistics
//

import SwiftUI
import Combine

// MARK: - Deletion Stats

/// Persisted stats about media cleanup
struct DeletionStats: Codable, Equatable {
    var totalMediaDeleted: Int
    var totalBytesSaved: Int64
    
    static let zero = DeletionStats(totalMediaDeleted: 0, totalBytesSaved: 0)
    
    mutating func add(count: Int, bytes: Int64) {
        totalMediaDeleted += count
        totalBytesSaved += bytes
    }
}

// MARK: - Stats Service

/// Tracks lifetime stats for media deletion
@MainActor
final class StatsService: ObservableObject {
    
    /// Shared instance
    static let shared = StatsService()
    
    /// Current stats
    @Published private(set) var stats: DeletionStats = .zero
    
    private let userDefaultsKey = "SlideClean.deletionStats"
    
    private init() {
        loadFromStorage()
    }
    
    // MARK: - Public Methods
    
    /// Record a successful deletion
    func recordDeletion(count: Int, bytes: Int64) {
        stats.add(count: count, bytes: bytes)
        saveToStorage()
    }
    
    /// Check if any deletions have been made
    var hasStats: Bool {
        stats.totalMediaDeleted > 0
    }
    
    // MARK: - Formatted Values
    
    var formattedMediaCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: stats.totalMediaDeleted)) ?? "\(stats.totalMediaDeleted)"
    }
    
    var formattedBytesSaved: String {
        let bytes = Double(stats.totalBytesSaved)
        let gb = bytes / 1_073_741_824 // 1024^3
        let mb = bytes / 1_048_576 // 1024^2
        
        if gb >= 1.0 {
            return String(format: "%.1f", gb)
        } else if mb >= 100 {
            return String(format: "%.0f", mb)
        } else if mb >= 1.0 {
            return String(format: "%.1f", mb)
        } else {
            return "0"
        }
    }
    
    var bytesSavedUnit: String {
        let bytes = Double(stats.totalBytesSaved)
        let gb = bytes / 1_073_741_824
        
        if gb >= 1.0 {
            return "GB"
        } else {
            return "MB"
        }
    }
    
    // MARK: - Persistence
    
    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(DeletionStats.self, from: data) {
            stats = decoded
        }
    }
    
    private func saveToStorage() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}


