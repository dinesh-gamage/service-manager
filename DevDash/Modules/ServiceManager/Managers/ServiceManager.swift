//
//  ServiceManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation
import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
class ServiceManager: ObservableObject {
    @Published var services: [ServiceRuntime] = []
    @Published var importMessage: String?
    @Published var showImportAlert = false

    init() {
        loadServices()
    }

    func loadServices() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "services"),
           let decoded = try? JSONDecoder().decode([ServiceConfig].self, from: data) {
            services = decoded.map { ServiceRuntime(config: $0) }
        } else {
            // Start with empty service list
            services = []
        }
    }

    func saveServices() {
        let configs = services.map { $0.config }
        if let encoded = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(encoded, forKey: "services")
        }
    }

    func addService(_ config: ServiceConfig) {
        let runtime = ServiceRuntime(config: config)
        services.append(runtime)
        saveServices()
    }

    func updateService(_ service: ServiceRuntime, with newConfig: ServiceConfig) {
        if let index = services.firstIndex(where: { $0.id == service.id }) {
            let updatedRuntime = ServiceRuntime(config: newConfig)
            services[index] = updatedRuntime
            saveServices()
            objectWillChange.send()
        }
    }

    func deleteService(at offsets: IndexSet) {
        services.remove(atOffsets: offsets)
        saveServices()
    }

    func checkAllServices() {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for service in services {
                    group.addTask {
                        await service.checkStatus()
                    }
                }
            }
        }
    }

    func exportServices() {
        let configs = services.map { $0.config }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let jsonData = try? encoder.encode(configs),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "services.json"
        savePanel.title = "Export Services"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? jsonString.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    func importServices() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import Services"

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url,
               let jsonData = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([ServiceConfig].self, from: jsonData) {

                var newCount = 0
                var updatedCount = 0

                // Import services - replace if name exists, add if new
                for config in decoded {
                    // Check if service with same name exists
                    if let index = self.services.firstIndex(where: { $0.config.name == config.name }) {
                        // Replace existing service with same name
                        let newRuntime = ServiceRuntime(config: config)
                        self.services[index] = newRuntime
                        updatedCount += 1
                    } else {
                        // Add new service
                        let runtime = ServiceRuntime(config: config)
                        self.services.append(runtime)
                        newCount += 1
                    }
                }
                self.saveServices()

                // Show confirmation
                DispatchQueue.main.async {
                    if newCount > 0 && updatedCount > 0 {
                        self.importMessage = "Imported \(newCount) new service(s) and updated \(updatedCount) existing service(s)."
                    } else if newCount > 0 {
                        self.importMessage = "Imported \(newCount) new service(s)."
                    } else if updatedCount > 0 {
                        self.importMessage = "Updated \(updatedCount) existing service(s)."
                    } else {
                        self.importMessage = "No services imported."
                    }
                    self.showImportAlert = true
                }
            }
        }
    }
}
