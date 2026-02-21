//
//  Module.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI
import Combine

// MARK: - Module Protocol

protocol DevDashModule: Identifiable {
    var id: String { get }
    var name: String { get }
    var icon: String { get }  // SF Symbol name
    var description: String { get }
    var accentColor: Color { get }

    @ViewBuilder
    func makeSidebarView() -> AnyView  // Module's sidebar content (list, navigation, etc.)

    @ViewBuilder
    func makeDetailView() -> AnyView   // Module's detail/main content

    // MARK: - Backup Support

    /// Filename for this module's backup (e.g., "services.json")
    var backupFileName: String { get }

    /// Export full data for backup (including secrets)
    /// - Returns: JSON data ready for encryption and S3 upload
    func exportForBackup() async throws -> Data
}

// MARK: - Module Registry

@MainActor
class ModuleRegistry: ObservableObject {
    static let shared = ModuleRegistry()

    @Published var modules: [any DevDashModule] = []

    private init() {}

    func register(_ module: any DevDashModule) {
        if !modules.contains(where: { $0.id == module.id }) {
            modules.append(module)
        }
    }

    func getModule(byId id: String) -> (any DevDashModule)? {
        modules.first { $0.id == id }
    }
}
