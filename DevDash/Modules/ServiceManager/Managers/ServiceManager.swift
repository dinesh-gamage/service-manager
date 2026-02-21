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
    // Public - lightweight list for consumers
    @Published var servicesList: [ServiceInfo] = []
    @Published private(set) var isLoading = false

    // Private - full runtimes with logs/processes
    private var runtimes: [UUID: ServiceRuntime] = [:]
    private var cancellables = Set<AnyCancellable>()

    private weak var alertQueue: AlertQueue?
    private weak var toastQueue: ToastQueue?

    init(alertQueue: AlertQueue? = nil, toastQueue: ToastQueue? = nil) {
        self.alertQueue = alertQueue
        self.toastQueue = toastQueue
        loadServices()
    }

    func loadServices() {
        if let configs: [ServiceConfig] = StorageManager.shared.load(forKey: "services") {
            runtimes = Dictionary(uniqueKeysWithValues: configs.map { config in
                let runtime = ServiceRuntime(config: config)
                subscribeToRuntime(runtime)
                return (config.id, runtime)
            })
        } else {
            runtimes = [:]
        }
        refreshServicesList()
    }

    func saveServices() {
        let configs = runtimes.values.map { $0.config }
        StorageManager.shared.save(configs, forKey: "services")
    }

    // MARK: - Runtime Access

    /// Get full runtime for detail view (on-demand)
    func getRuntime(id: UUID) -> ServiceRuntime? {
        return runtimes[id]
    }

    /// Get all runtimes (for compatibility during migration)
    var services: [ServiceRuntime] {
        return Array(runtimes.values)
    }

    // MARK: - List Refresh

    /// Refresh lightweight servicesList from runtimes
    func refreshServicesList() {
        servicesList = runtimes.values.map { runtime in
            ServiceInfo(
                id: runtime.id,
                name: runtime.config.name,
                isRunning: runtime.isRunning,
                isExternallyManaged: runtime.isExternallyManaged,
                hasPortConflict: runtime.hasPortConflict,
                processingAction: runtime.processingAction,
                port: runtime.config.port,
                workingDirectory: runtime.config.workingDirectory,
                command: runtime.config.command
            )
        }.sorted { $0.name < $1.name }
    }

    /// Subscribe to runtime changes to auto-refresh list
    private func subscribeToRuntime(_ runtime: ServiceRuntime) {
        runtime.objectWillChange
            .sink { [weak self] _ in
                self?.refreshServicesList()
            }
            .store(in: &cancellables)
    }

    // MARK: - CRUD Operations

    func addService(_ config: ServiceConfig) {
        let runtime = ServiceRuntime(config: config)
        subscribeToRuntime(runtime)
        runtimes[config.id] = runtime
        saveServices()
        refreshServicesList()
        toastQueue?.enqueue(message: "'\(config.name)' added")
    }

    func updateService(_ service: ServiceRuntime, with newConfig: ServiceConfig) {
        guard runtimes[service.id] != nil else { return }

        // Stop the old service before replacing to prevent memory leaks
        if service.isRunning {
            service.stop()
        }

        let updatedRuntime = ServiceRuntime(config: newConfig)
        subscribeToRuntime(updatedRuntime)
        runtimes[service.id] = updatedRuntime
        saveServices()
        refreshServicesList()
        toastQueue?.enqueue(message: "'\(newConfig.name)' updated")

        // Update selected service reference if this was the selected one
        if ServiceManagerState.shared.selectedService?.id == service.id {
            ServiceManagerState.shared.selectedService = updatedRuntime
        }
    }

    func deleteService(at offsets: IndexSet) {
        let sortedServices = runtimes.values.sorted { $0.config.name < $1.config.name }
        for index in offsets {
            let service = sortedServices[index]
            runtimes.removeValue(forKey: service.id)
        }
        saveServices()
        refreshServicesList()
    }

    func checkAllServices() {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for runtime in runtimes.values {
                    // Only check services that have a way to check status
                    if runtime.config.checkCommand != nil || runtime.config.port != nil {
                        group.addTask {
                            await runtime.checkStatus()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Import/Export

    func exportServices() {
        let configs = runtimes.values.map { $0.config }
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

            // Ensure all updates happen on MainActor for @Published to work
            Task { @MainActor in
                switch result {
                case .success(let configs):
                    var newCount = 0
                    var updatedCount = 0

                    // Import services - replace if name exists, add if new
                    for config in configs {
                        let trimmedName = config.name.trimmingCharacters(in: .whitespaces)
                        if let existing = self.runtimes.values.first(where: {
                            $0.config.name.trimmingCharacters(in: .whitespaces) == trimmedName
                        }) {
                            // Replace existing service
                            let runtime = ServiceRuntime(config: config)
                            self.subscribeToRuntime(runtime)
                            self.runtimes[existing.id] = runtime
                            updatedCount += 1
                        } else {
                            // Add new service
                            let runtime = ServiceRuntime(config: config)
                            self.subscribeToRuntime(runtime)
                            self.runtimes[config.id] = runtime
                            newCount += 1
                        }
                    }
                    self.saveServices()
                    self.refreshServicesList()
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
}
