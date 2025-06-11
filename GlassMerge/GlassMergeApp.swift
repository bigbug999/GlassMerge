//
//  GlassMergeApp.swift
//  GlassMerge
//
//  Created by Loaner on 6/9/25.
//

import SwiftUI
#if os(iOS)
import CoreHaptics
#endif

@main
struct GlassMergeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        #if os(iOS)
        // Initialize haptics engine at app launch
        _ = HapticManager.shared
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            #if os(iOS)
            switch newPhase {
            case .active:
                // Reinitialize haptics when app becomes active
                HapticManager.shared.prepareHaptics()
            default:
                break
            }
            #endif
        }
    }
}
