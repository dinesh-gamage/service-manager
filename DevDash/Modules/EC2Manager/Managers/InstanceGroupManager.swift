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
    @Published var importMessage: String?
    @Published var showImportAlert = false

    init() {
        loadGroups()
    }

    func loadGroups() {
        if let data = UserDefaults.standard.data(forKey: "instanceGroups"),
           let decoded = try? JSONDecoder().decode([InstanceGroup].self, from: data) {
            groups = decoded
        } else {
            // Initialize with default groups from scripts
            groups = createDefaultGroups()
            saveGroups()
        }
    }

    func saveGroups() {
        if let encoded = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(encoded, forKey: "instanceGroups")
        }
    }

    func updateInstance(_ groupId: UUID, instanceId: UUID, ip: String?, fetchedDate: Date, error: String?) {
        if let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
           let instanceIndex = groups[groupIndex].instances.firstIndex(where: { $0.id == instanceId }) {
            groups[groupIndex].instances[instanceIndex].lastKnownIP = ip
            groups[groupIndex].instances[instanceIndex].lastFetched = fetchedDate
            groups[groupIndex].instances[instanceIndex].fetchError = error
            saveGroups()
        }
    }

    func fetchInstanceIP(group: InstanceGroup, instance: EC2Instance) {
        isFetching[instance.id] = true

        Task.detached(priority: .userInitiated) {
            let command = "aws-vault exec \(group.awsProfile) -- aws ec2 describe-instances --instance-ids \(instance.instanceId) --region \(group.region) --query 'Reservations[0].Instances[0].PublicIpAddress' --output text"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", command] // -l flag loads user's profile

            // Set environment to include common binary paths
            var environment = ProcessInfo.processInfo.environment
            let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
            if let existingPath = environment["PATH"] {
                environment["PATH"] = extraPaths.joined(separator: ":") + ":" + existingPath
            } else {
                environment["PATH"] = extraPaths.joined(separator: ":")
            }
            process.environment = environment

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

                await MainActor.run {
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
                await MainActor.run {
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
    }

    func updateGroup(groupId: UUID, newGroup: InstanceGroup) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index] = newGroup
            saveGroups()
            objectWillChange.send()
        }
    }

    func deleteGroup(at offsets: IndexSet) {
        groups.remove(atOffsets: offsets)
        saveGroups()
    }

    // MARK: - Instance CRUD

    func addInstance(groupId: UUID, instance: EC2Instance) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].instances.append(instance)
            saveGroups()
        }
    }

    func updateInstanceData(groupId: UUID, instanceId: UUID, newInstance: EC2Instance) {
        if let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
           let instanceIndex = groups[groupIndex].instances.firstIndex(where: { $0.id == instanceId }) {
            groups[groupIndex].instances[instanceIndex] = newInstance
            saveGroups()
        }
    }

    func deleteInstance(groupId: UUID, instanceId: UUID) {
        if let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
           let instanceIndex = groups[groupIndex].instances.firstIndex(where: { $0.id == instanceId }) {
            groups[groupIndex].instances.remove(at: instanceIndex)
            saveGroups()
        }
    }

    // MARK: - Import/Export

    func exportGroups() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let jsonData = try? encoder.encode(groups),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "ec2-groups.json"
        savePanel.title = "Export EC2 Groups"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? jsonString.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    func importGroups() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import EC2 Groups"

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url,
               let jsonData = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([InstanceGroup].self, from: jsonData) {

                var newCount = 0
                var updatedCount = 0

                // Import groups - replace if name exists, add if new
                for group in decoded {
                    // Check if group with same name exists
                    if let index = self.groups.firstIndex(where: { $0.name == group.name }) {
                        // Replace existing group with same name
                        self.groups[index] = group
                        updatedCount += 1
                    } else {
                        // Add new group
                        self.groups.append(group)
                        newCount += 1
                    }
                }
                self.saveGroups()

                // Show confirmation
                DispatchQueue.main.async {
                    if newCount > 0 && updatedCount > 0 {
                        self.importMessage = "Imported \(newCount) new group(s) and updated \(updatedCount) existing group(s)."
                    } else if newCount > 0 {
                        self.importMessage = "Imported \(newCount) new group(s)."
                    } else if updatedCount > 0 {
                        self.importMessage = "Updated \(updatedCount) existing group(s)."
                    } else {
                        self.importMessage = "No changes made."
                    }
                    self.showImportAlert = true
                }
            }
        }
    }

    private func createDefaultGroups() -> [InstanceGroup] {
        [
            InstanceGroup(
                name: "Lucy",
                region: "ap-southeast-1",
                awsProfile: "lucy-saas",
                instances: [
                    EC2Instance(name: "Web 1", instanceId: "i-0edf0988b5fb37d0e"),
                    EC2Instance(name: "Web 2", instanceId: "i-09881dd5fc0add898"),
                    EC2Instance(name: "Worker", instanceId: "i-0314f5ee633b387aa")
                ]
            ),
            InstanceGroup(
                name: "Sydney",
                region: "ap-southeast-2",
                awsProfile: "lucy-saas",
                instances: [
                    EC2Instance(name: "Web", instanceId: "i-09eee6ce3517cbf37"),
                    EC2Instance(name: "Worker", instanceId: "i-091a50f0fd4710385"),
                    EC2Instance(name: "DB", instanceId: "i-0c4619bfbc09067c6"),
                    EC2Instance(name: "Data Store", instanceId: "i-0cf272c5285040864")
                ]
            ),
            InstanceGroup(
                name: "Canvas",
                region: "ap-southeast-1",
                awsProfile: "lucy-saas",
                instances: [
                    EC2Instance(name: "Web 1", instanceId: "i-049df269560b96012"),
                    EC2Instance(name: "Web 2", instanceId: "i-0bfc23ce6ea6070fa"),
                    EC2Instance(name: "Worker", instanceId: "i-08e462a4548874297"),
                    EC2Instance(name: "DB", instanceId: "i-02ac691d49e45fe31")
                ]
            )
        ]
    }
}
