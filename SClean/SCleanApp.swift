//
//  SCleanApp.swift
//  SClean
//
//  Created by Арсений Помазков on 19.12.2025.
//

import SwiftUI

@main
struct SCleanApp: App {
    @AppStorage(AppearanceMode.storageKey) private var storedAppearance: String = AppearanceMode.system.rawValue
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(AppearanceMode.from(raw: storedAppearance).colorScheme)
        }
    }
}
