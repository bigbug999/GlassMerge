//
//  GlassMergeApp.swift
//  GlassMerge
//
//  Created by Loaner on 6/9/25.
//

import SwiftUI
#if os(iOS)
import CoreHaptics
import UIKit

// AppDelegate to lock orientation to portrait only
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}
#endif

@main
struct GlassMergeApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
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
