//
//  SlideCleanApp.swift
//  SlideClean
//
//  Created by Арсений Помазков on 19.12.2025.
//

import SwiftUI

@main
struct SlideCleanApp: App {
    @AppStorage(AppearanceMode.storageKey) private var storedAppearance: String = AppearanceMode.system.rawValue
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .transaction { txn in
                    // Reduce flicker on theme change
                    txn.disablesAnimations = true
                }
                .preferredColorScheme(AppearanceMode.from(raw: storedAppearance).colorScheme)
        }
    }
}
