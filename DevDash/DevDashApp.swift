//
//  DevDashApp.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-14.
//

import SwiftUI

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running when window is closed
        return false
    }
}

// MARK: - App

@main
struct DevDashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager = BiometricAuthManager.shared

    init() {
        // Register all modules
        registerModules()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()

                // Authentication gate overlay
                if !authManager.isAuthenticated {
                    AuthenticationGateView()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }

    @MainActor
    private func registerModules() {
        let registry = ModuleRegistry.shared

        // Register Service Manager module
        registry.register(ServiceManagerModule())

        // Register EC2 Manager module
        registry.register(EC2ManagerModule())

        // Register Credentials Manager module
        registry.register(CredentialsManagerModule())

        // Register AWS Vault Manager module
        registry.register(AWSVaultManagerModule())

        // Register Settings module
        registry.register(SettingsModule())
    }
}
