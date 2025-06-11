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
    }
}
