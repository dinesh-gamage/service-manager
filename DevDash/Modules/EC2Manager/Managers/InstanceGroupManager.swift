//
//  InstanceGroupManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
class InstanceGroupManager: ObservableObject {
    @Published var groups: [InstanceGroup] = []
    @Published var isFetching: [UUID: Bool] = [:]
    @Published var instanceOutputs: [UUID: CommandOutputViewModel] = [:]
    @Published var listRefreshTrigger = UUID()

    private weak var alertQueue: AlertQueue?
    private weak var toastQueue: ToastQueue?

    init(alertQueue: AlertQueue? = nil, toastQueue: ToastQueue? = nil) {
        self.alertQueue = alertQueue
        self.toastQueue = toastQueue
        loadGroups()
    }

    func loadGroups() {
        groups = StorageManager.shared.load(forKey: "instanceGroups") ?? []
    }

    func saveGroups() {
        StorageManager.shared.save(groups, forKey: "instanceGroups")
    }

    func updateInstance(_ groupId: UUID, instanceId: UUID, ip: String?, fetchedDate: Date, error: String?) {
        if let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
           let instanceIndex = groups[groupIndex].instances.firstIndex(where: { $0.id == instanceId }) {
            groups[groupIndex].instances[instanceIndex].lastKnownIP = ip
            groups[groupIndex].instances[instanceIndex].lastFetched = fetchedDate
            groups[groupIndex].instances[instanceIndex].fetchError = error
            saveGroups()

            // Update selected group reference if this group is selected
            if EC2ManagerState.shared.selectedGroup?.id == groupId {
                EC2ManagerState.shared.selectedGroup = groups[groupIndex]
            }

            listRefreshTrigger = UUID()
            objectWillChange.send()
        }
    }

    func fetchInstanceIP(group: InstanceGroup, instance: EC2Instance) {
        // Clear previous error immediately
        if let groupIndex = groups.firstIndex(where: { $0.id == group.id }),
           let instanceIndex = groups[groupIndex].instances.firstIndex(where: { $0.id == instance.id }) {
            groups[groupIndex].instances[instanceIndex].fetchError = nil
            objectWillChange.send()
        }

        isFetching[instance.id] = true

        // Create or get output view model for this instance
        let outputViewModel = instanceOutputs[instance.id] ?? CommandOutputViewModel()
        if instanceOutputs[instance.id] == nil {
            instanceOutputs[instance.id] = outputViewModel
        }

        Task.detached(priority: .userInitiated) {
            let command = "aws-vault exec \(group.awsProfile) -- aws ec2 describe-instances --instance-ids \(instance.instanceId) --region \(group.region) --query 'Reservations[0].Instances[0].PublicIpAddress' --output text"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.environment = ProcessEnvironment.shared.getEnvironment()

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let exitCode = process.terminationStatus

                // Build full output log
                var fullLog = "[Command] \(command)\n\n"
                fullLog += "[Exit Code] \(exitCode)\n\n"
                if !output.isEmpty {
                    fullLog += "[STDOUT]\n\(output)\n\n"
                }
                if !errorOutput.isEmpty {
                    fullLog += "[STDERR]\n\(errorOutput)\n"
                }

                await MainActor.run {
                    // Update output view model with full log
                    outputViewModel.setLogs(fullLog)

                    if exitCode == 0 && !output.isEmpty && output != "None" {
                        // Success - got valid IP
                        self.updateInstance(group.id, instanceId: instance.id, ip: output, fetchedDate: Date(), error: nil)
                    } else if !errorOutput.isEmpty {
                        // Error occurred
                        self.updateInstance(group.id, instanceId: instance.id, ip: nil, fetchedDate: Date(), error: errorOutput)
                    } else if output == "None" || output.isEmpty {
                        // No IP available but command succeeded
                        self.updateInstance(group.id, instanceId: instance.id, ip: nil, fetchedDate: Date(), error: "No public IP assigned")
                    } else {
                        // Unknown error
                        self.updateInstance(group.id, instanceId: instance.id, ip: nil, fetchedDate: Date(), error: "Failed to fetch IP")
                    }
                    self.isFetching[instance.id] = false
                }
            } catch {
                let errorLog = "[Command] \(command)\n\n[Error] \(error.localizedDescription)\n"
                await MainActor.run {
                    outputViewModel.setLogs(errorLog)
                    self.updateInstance(group.id, instanceId: instance.id, ip: nil, fetchedDate: Date(), error: "Process error: \(error.localizedDescription)")
                    self.isFetching[instance.id] = false
                }
            }
        }
    }

    // MARK: - Group CRUD

    func addGroup(_ group: InstanceGroup) {
        groups.append(group)
        saveGroups()
        toastQueue?.enqueue(message: "'\(group.name)' added")
        listRefreshTrigger = UUID()
    }

    func updateGroup(groupId: UUID, newGroup: InstanceGroup) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index] = newGroup
            saveGroups()
            toastQueue?.enqueue(message: "'\(newGroup.name)' updated")

            // Update selected group reference if this was the selected one
            if EC2ManagerState.shared.selectedGroup?.id == groupId {
                EC2ManagerState.shared.selectedGroup = newGroup
            }

            listRefreshTrigger = UUID()
            objectWillChange.send()
        }
    }

    func deleteGroup(at offsets: IndexSet) {
        groups.remove(atOffsets: offsets)
        saveGroups()
        listRefreshTrigger = UUID()
    }

    // MARK: - Instance CRUD

    func addInstance(groupId: UUID, instance: EC2Instance) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].instances.append(instance)
            saveGroups()
            listRefreshTrigger = UUID()
        }
    }

    func updateInstanceData(groupId: UUID, instanceId: UUID, newInstance: EC2Instance) {
        if let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
           let instanceIndex = groups[groupIndex].instances.firstIndex(where: { $0.id == instanceId }) {
            groups[groupIndex].instances[instanceIndex] = newInstance
            saveGroups()
            listRefreshTrigger = UUID()
        }
    }

    func deleteInstance(groupId: UUID, instanceId: UUID) {
        if let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
           let instanceIndex = groups[groupIndex].instances.firstIndex(where: { $0.id == instanceId }) {
            groups[groupIndex].instances.remove(at: instanceIndex)
            saveGroups()
            listRefreshTrigger = UUID()
        }
    }

    // MARK: - Import/Export

    func exportGroups() {
        ImportExportManager.shared.exportJSON(
            groups,
            defaultFileName: "ec2-groups.json",
            title: "Export EC2 Groups"
        ) { [weak self] result in
            switch result {
            case .success:
                self?.toastQueue?.enqueue(message: "Groups exported successfully")
            case .failure(let error):
                if case .userCancelled = error {
                    return
                }
                self?.alertQueue?.enqueue(title: "Export Failed", message: error.localizedDescription)
            }
        }
    }

    func importGroups() {
        ImportExportManager.shared.importJSON(
            InstanceGroup.self,
            title: "Import EC2 Groups"
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let importedGroups):
                var newCount = 0
                var updatedCount = 0

                // Import groups - replace if name exists, add if new
                for group in importedGroups {
                    if let index = self.groups.firstIndex(where: { $0.name == group.name }) {
                        // Replace existing group
                        self.groups[index] = group
                        updatedCount += 1
                    } else {
                        // Add new group
                        self.groups.append(group)
                        newCount += 1
                    }
                }
                self.saveGroups()

                // Show success toast
                let message: String
                if newCount > 0 && updatedCount > 0 {
                    message = "Imported \(newCount) new, updated \(updatedCount) existing"
                } else if newCount > 0 {
                    message = "Imported \(newCount) new group\(newCount == 1 ? "" : "s")"
                } else if updatedCount > 0 {
                    message = "Updated \(updatedCount) group\(updatedCount == 1 ? "" : "s")"
                } else {
                    message = "No groups imported"
                }
                self.toastQueue?.enqueue(message: message)

            case .failure(let error):
                // Only show error alerts, not cancellation
                if case .userCancelled = error {
                    return
                }
                self.alertQueue?.enqueue(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }
}
