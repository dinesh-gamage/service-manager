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
    @Published var isRestarting: [UUID: Bool] = [:]
    @Published var isCheckingHealth: [UUID: Bool] = [:]
    @Published var instanceOutputs: [UUID: CommandOutputViewModel] = [:]
    @Published var listRefreshTrigger = UUID()
    @Published private(set) var isLoading = false

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

    func restartInstance(group: InstanceGroup, instance: EC2Instance) {
        // Clear previous error immediately
        if let groupIndex = groups.firstIndex(where: { $0.id == group.id }),
           let instanceIndex = groups[groupIndex].instances.firstIndex(where: { $0.id == instance.id }) {
            groups[groupIndex].instances[instanceIndex].fetchError = nil
            objectWillChange.send()
        }

        isRestarting[instance.id] = true

        // Create or get output view model for this instance
        let outputViewModel = instanceOutputs[instance.id] ?? CommandOutputViewModel()
        if instanceOutputs[instance.id] == nil {
            instanceOutputs[instance.id] = outputViewModel
        }

        Task.detached(priority: .userInitiated) {
            let instanceId = instance.instanceId
            let region = group.region
            let profile = group.awsProfile

            var fullLog = "[Restart initiated for \(instance.name)]\n\n"

            // Step 1: Stop instance
            let stopCommand = "aws-vault exec \(profile) -- aws ec2 stop-instances --instance-ids \(instanceId) --region \(region)"
            fullLog += "[Command] \(stopCommand)\n"

            let stopProcess = Process()
            stopProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
            stopProcess.arguments = ["-c", stopCommand]
            stopProcess.environment = ProcessEnvironment.shared.getEnvironment()

            let stopOutput = Pipe()
            let stopError = Pipe()
            stopProcess.standardOutput = stopOutput
            stopProcess.standardError = stopError

            do {
                try stopProcess.run()
                stopProcess.waitUntilExit()

                let stopOutputData = stopOutput.fileHandleForReading.readDataToEndOfFile()
                let stopErrorData = stopError.fileHandleForReading.readDataToEndOfFile()
                let stopOut = String(data: stopOutputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stopErr = String(data: stopErrorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if stopProcess.terminationStatus != 0 {
                    fullLog += "[Stop Failed] Exit code: \(stopProcess.terminationStatus)\n"
                    if !stopErr.isEmpty { fullLog += "\(stopErr)\n" }
                    await MainActor.run {
                        outputViewModel.setLogs(fullLog)
                        self.updateInstance(group.id, instanceId: instance.id, ip: nil, fetchedDate: Date(), error: "Failed to stop instance")
                        self.isRestarting[instance.id] = false
                    }
                    return
                }

                fullLog += "[Stop] Success\n"
                if !stopOut.isEmpty { fullLog += "\(stopOut)\n" }
                fullLog += "\n"

                // Step 2: Wait for instance to stop
                fullLog += "[Waiting] For instance to stop...\n"
                await MainActor.run { outputViewModel.setLogs(fullLog) }

                let waitStopCommand = "aws-vault exec \(profile) -- aws ec2 wait instance-stopped --instance-ids \(instanceId) --region \(region)"
                let waitStopProcess = Process()
                waitStopProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
                waitStopProcess.arguments = ["-c", waitStopCommand]
                waitStopProcess.environment = ProcessEnvironment.shared.getEnvironment()

                try waitStopProcess.run()
                waitStopProcess.waitUntilExit()

                fullLog += "[Stopped] Instance is now stopped\n\n"

                // Step 3: Start instance
                let startCommand = "aws-vault exec \(profile) -- aws ec2 start-instances --instance-ids \(instanceId) --region \(region)"
                fullLog += "[Command] \(startCommand)\n"
                await MainActor.run { outputViewModel.setLogs(fullLog) }

                let startProcess = Process()
                startProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
                startProcess.arguments = ["-c", startCommand]
                startProcess.environment = ProcessEnvironment.shared.getEnvironment()

                let startOutput = Pipe()
                let startError = Pipe()
                startProcess.standardOutput = startOutput
                startProcess.standardError = startError

                try startProcess.run()
                startProcess.waitUntilExit()

                let startOutputData = startOutput.fileHandleForReading.readDataToEndOfFile()
                let startErrorData = startError.fileHandleForReading.readDataToEndOfFile()
                let startOut = String(data: startOutputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let startErr = String(data: startErrorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if startProcess.terminationStatus != 0 {
                    fullLog += "[Start Failed] Exit code: \(startProcess.terminationStatus)\n"
                    if !startErr.isEmpty { fullLog += "\(startErr)\n" }
                    await MainActor.run {
                        outputViewModel.setLogs(fullLog)
                        self.updateInstance(group.id, instanceId: instance.id, ip: nil, fetchedDate: Date(), error: "Failed to start instance")
                        self.isRestarting[instance.id] = false
                    }
                    return
                }

                fullLog += "[Start] Success\n"
                if !startOut.isEmpty { fullLog += "\(startOut)\n" }
                fullLog += "\n"

                // Step 4: Wait for instance to be running
                fullLog += "[Waiting] For instance to be running...\n"
                await MainActor.run { outputViewModel.setLogs(fullLog) }

                let waitRunCommand = "aws-vault exec \(profile) -- aws ec2 wait instance-running --instance-ids \(instanceId) --region \(region)"
                let waitRunProcess = Process()
                waitRunProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
                waitRunProcess.arguments = ["-c", waitRunCommand]
                waitRunProcess.environment = ProcessEnvironment.shared.getEnvironment()

                try waitRunProcess.run()
                waitRunProcess.waitUntilExit()

                fullLog += "[Running] Instance is now running\n\n"

                // Step 5: Fetch new IP
                fullLog += "[Fetching] New IP address...\n"
                await MainActor.run { outputViewModel.setLogs(fullLog) }

                let ipCommand = "aws-vault exec \(profile) -- aws ec2 describe-instances --instance-ids \(instanceId) --region \(region) --query 'Reservations[0].Instances[0].PublicIpAddress' --output text"
                let ipProcess = Process()
                ipProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
                ipProcess.arguments = ["-c", ipCommand]
                ipProcess.environment = ProcessEnvironment.shared.getEnvironment()

                let ipOutput = Pipe()
                ipProcess.standardOutput = ipOutput

                try ipProcess.run()
                ipProcess.waitUntilExit()

                let ipData = ipOutput.fileHandleForReading.readDataToEndOfFile()
                let newIP = String(data: ipData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                fullLog += "[Success] Restart complete. New IP: \(newIP)\n"

                await MainActor.run {
                    outputViewModel.setLogs(fullLog)
                    self.updateInstance(group.id, instanceId: instance.id, ip: newIP, fetchedDate: Date(), error: nil)
                    self.isRestarting[instance.id] = false
                    self.toastQueue?.enqueue(message: "'\(instance.name)' restarted successfully")
                }
            } catch {
                fullLog += "\n[Error] \(error.localizedDescription)\n"
                await MainActor.run {
                    outputViewModel.setLogs(fullLog)
                    self.updateInstance(group.id, instanceId: instance.id, ip: nil, fetchedDate: Date(), error: "Restart failed: \(error.localizedDescription)")
                    self.isRestarting[instance.id] = false
                }
            }
        }
    }

    func checkInstanceHealth(group: InstanceGroup, instance: EC2Instance) {
        isCheckingHealth[instance.id] = true

        // Create or get output view model for this instance
        let outputViewModel = instanceOutputs[instance.id] ?? CommandOutputViewModel()
        if instanceOutputs[instance.id] == nil {
            instanceOutputs[instance.id] = outputViewModel
        }

        Task.detached(priority: .userInitiated) {
            let command = "aws-vault exec \(group.awsProfile) -- aws ec2 describe-instance-status --instance-ids \(instance.instanceId) --region \(group.region) --include-all-instances"

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
                var fullLog = "[Health Check] \(instance.name)\n"
                fullLog += "[Command] \(command)\n\n"
                fullLog += "[Exit Code] \(exitCode)\n\n"
                if !output.isEmpty {
                    fullLog += "[STDOUT]\n\(output)\n\n"
                }
                if !errorOutput.isEmpty {
                    fullLog += "[STDERR]\n\(errorOutput)\n"
                }

                await MainActor.run {
                    outputViewModel.setLogs(fullLog)
                    self.isCheckingHealth[instance.id] = false
                }
            } catch {
                let errorLog = "[Health Check] \(instance.name)\n[Command] \(command)\n\n[Error] \(error.localizedDescription)\n"
                await MainActor.run {
                    outputViewModel.setLogs(errorLog)
                    self.isCheckingHealth[instance.id] = false
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
        isLoading = true

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
                self.isLoading = false

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
