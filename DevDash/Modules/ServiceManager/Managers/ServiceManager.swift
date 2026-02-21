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
    @Published private(set) var isLoading = false

    private weak var alertQueue: AlertQueue?
    private weak var toastQueue: ToastQueue?

    init(alertQueue: AlertQueue? = nil, toastQueue: ToastQueue? = nil) {
        self.alertQueue = alertQueue
        self.toastQueue = toastQueue
        loadServices()
    }

    func loadServices() {
        if let configs: [ServiceConfig] = StorageManager.shared.load(forKey: "services") {
            services = configs.map { ServiceRuntime(config: $0) }
        } else {
            services = []
        }
    }

    func saveServices() {
        let configs = services.map { $0.config }
        StorageManager.shared.save(configs, forKey: "services")
    }

    func addService(_ config: ServiceConfig) {
        let runtime = ServiceRuntime(config: config)
        services.append(runtime)
        saveServices()
        toastQueue?.enqueue(message: "'\(config.name)' added")
    }

    func updateService(_ service: ServiceRuntime, with newConfig: ServiceConfig) {
        if let index = services.firstIndex(where: { $0.id == service.id }) {
            let updatedRuntime = ServiceRuntime(config: newConfig)
            services[index] = updatedRuntime
            saveServices()
            toastQueue?.enqueue(message: "'\(newConfig.name)' updated")

            // Update selected service reference if this was the selected one
            if ServiceManagerState.shared.selectedService?.id == service.id {
                ServiceManagerState.shared.selectedService = updatedRuntime
            }
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
                    // Only check services that have a way to check status
                    if service.config.checkCommand != nil || service.config.port != nil {
                        group.addTask {
                            await service.checkStatus()
                        }
                    }
                }
            }
        }
    }

    func exportServices() {
        let configs = services.map { $0.config }
        ImportExportManager.shared.exportJSON(
            configs,
            defaultFileName: "services.json",
            title: "Export Services"
        ) { [weak self] result in
            switch result {
            case .success:
                self?.toastQueue?.enqueue(message: "Services exported successfully")
            case .failure(let error):
                if case .userCancelled = error {
                    return
                }
                self?.alertQueue?.enqueue(title: "Export Failed", message: error.localizedDescription)
            }
        }
    }

    func importServices() {
        isLoading = true

        ImportExportManager.shared.importJSON(
            ServiceConfig.self,
            title: "Import Services"
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let configs):
                var newCount = 0
                var updatedCount = 0

                // Import services - replace if name exists, add if new
                for config in configs {
                    if let index = self.services.firstIndex(where: { $0.config.name == config.name }) {
                        // Replace existing service
                        self.services[index] = ServiceRuntime(config: config)
                        updatedCount += 1
                    } else {
                        // Add new service
                        self.services.append(ServiceRuntime(config: config))
                        newCount += 1
                    }
                }
                self.saveServices()
                self.isLoading = false

                // Show success toast
                let message: String
                if newCount > 0 && updatedCount > 0 {
                    message = "Imported \(newCount) new, updated \(updatedCount) existing"
                } else if newCount > 0 {
                    message = "Imported \(newCount) new service\(newCount == 1 ? "" : "s")"
                } else if updatedCount > 0 {
                    message = "Updated \(updatedCount) service\(updatedCount == 1 ? "" : "s")"
                } else {
                    message = "No services imported"
                }
                self.toastQueue?.enqueue(message: message)

            case .failure(let error):
                self.isLoading = false

                // Only show error alerts, not cancellation
                if case .userCancelled = error {
                    return
                }
                self.alertQueue?.enqueue(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }
}
