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
    @Published var instanceHealthData: [UUID: [String: Any]] = [:]
    @Published private(set) var isLoading = false

    private weak var alertQueue: AlertQueue?
    private weak var toastQueue: ToastQueue?

    // Store running tasks for cancellation
    private var fetchTasks: [UUID: Task<Void, Never>] = [:]
    private var restartTasks: [UUID: Task<Void, Never>] = [:]
    private var healthCheckTasks: [UUID: Task<Void, Never>] = [:]

    // Tunnel management
    private var tunnelRuntimes: [UUID: TunnelRuntime] = [:]
    private var tunnelCancellables: [UUID: AnyCancellable] = [:]

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
        }
    }

    func fetchInstanceIP(group: InstanceGroup, instance: EC2Instance) {
        // Cancel existing fetch task for this instance
        fetchTasks[instance.id]?.cancel()

        // Clear previous error immediately
        if let groupIndex = groups.firstIndex(where: { $0.id == group.id }),
           let instanceIndex = groups[groupIndex].instances.firstIndex(where: { $0.id == instance.id }) {
            groups[groupIndex].instances[instanceIndex].fetchError = nil
        }

        isFetching[instance.id] = true

        // Create or get output view model for this instance
        let outputViewModel = instanceOutputs[instance.id] ?? CommandOutputViewModel()
        if instanceOutputs[instance.id] == nil {
            instanceOutputs[instance.id] = outputViewModel
        }

        let task = Task.detached(priority: .userInitiated) {
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

                // Check if task was cancelled
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isFetching[instance.id] = false
                        self.fetchTasks.removeValue(forKey: instance.id)
                    }
                    return
                }

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
                    self.fetchTasks.removeValue(forKey: instance.id)
                }
            } catch {
                let errorLog = "[Command] \(command)\n\n[Error] \(error.localizedDescription)\n"
                await MainActor.run {
                    outputViewModel.setLogs(errorLog)
                    self.updateInstance(group.id, instanceId: instance.id, ip: nil, fetchedDate: Date(), error: "Process error: \(error.localizedDescription)")
                    self.isFetching[instance.id] = false
                    self.fetchTasks.removeValue(forKey: instance.id)
                }
            }
        }

        // Store task for cancellation
        fetchTasks[instance.id] = task
    }

    func restartInstance(group: InstanceGroup, instance: EC2Instance) {
        // Cancel existing restart task for this instance
        restartTasks[instance.id]?.cancel()

        // Clear previous error immediately
        if let groupIndex = groups.firstIndex(where: { $0.id == group.id }),
           let instanceIndex = groups[groupIndex].instances.firstIndex(where: { $0.id == instance.id }) {
            groups[groupIndex].instances[instanceIndex].fetchError = nil
        }

        isRestarting[instance.id] = true

        // Create or get output view model for this instance
        let outputViewModel = instanceOutputs[instance.id] ?? CommandOutputViewModel()
        if instanceOutputs[instance.id] == nil {
            instanceOutputs[instance.id] = outputViewModel
        }

        let task = Task.detached(priority: .userInitiated) {
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

                // Check if task was cancelled
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isRestarting[instance.id] = false
                        self.restartTasks.removeValue(forKey: instance.id)
                    }
                    return
                }

                if stopProcess.terminationStatus != 0 {
                    fullLog += "[Stop Failed] Exit code: \(stopProcess.terminationStatus)\n"
                    if !stopErr.isEmpty { fullLog += "\(stopErr)\n" }
                    await MainActor.run {
                        outputViewModel.setLogs(fullLog)
                        self.updateInstance(group.id, instanceId: instance.id, ip: nil, fetchedDate: Date(), error: "Failed to stop instance")
                        self.isRestarting[instance.id] = false
                        self.restartTasks.removeValue(forKey: instance.id)
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

                // Check if task was cancelled
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isRestarting[instance.id] = false
                        self.restartTasks.removeValue(forKey: instance.id)
                    }
                    return
                }

                if startProcess.terminationStatus != 0 {
                    fullLog += "[Start Failed] Exit code: \(startProcess.terminationStatus)\n"
                    if !startErr.isEmpty { fullLog += "\(startErr)\n" }
                    await MainActor.run {
                        outputViewModel.setLogs(fullLog)
                        self.updateInstance(group.id, instanceId: instance.id, ip: nil, fetchedDate: Date(), error: "Failed to start instance")
                        self.isRestarting[instance.id] = false
                        self.restartTasks.removeValue(forKey: instance.id)
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
                    self.restartTasks.removeValue(forKey: instance.id)
                    self.toastQueue?.enqueue(message: "'\(instance.name)' restarted successfully")
                }
            } catch {
                fullLog += "\n[Error] \(error.localizedDescription)\n"
                await MainActor.run {
                    outputViewModel.setLogs(fullLog)
                    self.updateInstance(group.id, instanceId: instance.id, ip: nil, fetchedDate: Date(), error: "Restart failed: \(error.localizedDescription)")
                    self.isRestarting[instance.id] = false
                    self.restartTasks.removeValue(forKey: instance.id)
                }
            }
        }

        // Store task for cancellation
        restartTasks[instance.id] = task
    }

    func checkInstanceHealth(group: InstanceGroup, instance: EC2Instance, completion: @escaping ([String: Any]?) -> Void) {
        // Cancel existing health check task for this instance
        healthCheckTasks[instance.id]?.cancel()

        isCheckingHealth[instance.id] = true

        // Create or get output view model for this instance
        let outputViewModel = instanceOutputs[instance.id] ?? CommandOutputViewModel()
        if instanceOutputs[instance.id] == nil {
            instanceOutputs[instance.id] = outputViewModel
        }

        let task = Task.detached(priority: .userInitiated) {
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

                // Check if task was cancelled
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isCheckingHealth[instance.id] = false
                        self.healthCheckTasks.removeValue(forKey: instance.id)
                        completion(nil)
                    }
                    return
                }

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

                // Parse JSON response
                var parsedData: [String: Any]? = nil
                if exitCode == 0 && !output.isEmpty {
                    if let jsonData = output.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        parsedData = json
                    }
                }

                await MainActor.run {
                    outputViewModel.setLogs(fullLog)
                    self.isCheckingHealth[instance.id] = false
                    self.healthCheckTasks.removeValue(forKey: instance.id)

                    // Store health data temporarily (session only)
                    if let parsedData = parsedData {
                        self.instanceHealthData[instance.id] = parsedData
                    }

                    completion(parsedData)
                }
            } catch {
                let errorLog = "[Health Check] \(instance.name)\n[Command] \(command)\n\n[Error] \(error.localizedDescription)\n"
                await MainActor.run {
                    outputViewModel.setLogs(errorLog)
                    self.isCheckingHealth[instance.id] = false
                    self.healthCheckTasks.removeValue(forKey: instance.id)
                    completion(nil)
                }
            }
        }

        // Store task for cancellation
        healthCheckTasks[instance.id] = task
    }

    // MARK: - Group CRUD

    func addGroup(_ group: InstanceGroup) {
        groups.append(group)
        saveGroups()
        toastQueue?.enqueue(message: "'\(group.name)' added")
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
        Task {
            do {
                // Require biometric auth before export
                try await BiometricAuthManager.shared.authenticate(reason: "Authenticate to export EC2 groups")

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
            } catch {
                await MainActor.run {
                    self.alertQueue?.enqueue(title: "Authentication Required", message: "You must authenticate to export EC2 groups")
                }
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
                    let trimmedName = group.name.trimmingCharacters(in: .whitespaces)
                    if let index = self.groups.firstIndex(where: {
                        $0.name.trimmingCharacters(in: .whitespaces) == trimmedName
                    }) {
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

    // MARK: - Tunnel Management

    /// Get tunnel runtime for a specific tunnel ID
    func getTunnelRuntime(tunnelId: UUID) -> TunnelRuntime? {
        return tunnelRuntimes[tunnelId]
    }

    /// Resolve SSH config for an instance (instance config takes precedence over group)
    func resolveSSHConfig(instance: EC2Instance, group: InstanceGroup) -> SSHConfig? {
        return instance.sshConfig ?? group.sshConfig
    }

    /// Start an SSH tunnel for an instance
    func startTunnel(instance: EC2Instance, tunnel: SSHTunnel, group: InstanceGroup) {
        // Validate bastion IP exists
        guard let bastionIP = instance.lastKnownIP else {
            alertQueue?.enqueue(title: "No IP Available", message: "Fetch the instance IP first before starting a tunnel.")
            return
        }

        // Resolve SSH config
        guard let sshConfig = resolveSSHConfig(instance: instance, group: group) else {
            alertQueue?.enqueue(title: "SSH Not Configured", message: "Configure SSH settings in the group or instance first.")
            return
        }

        // Validate SSH key file exists
        let expandedKeyPath = NSString(string: sshConfig.keyPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedKeyPath) else {
            alertQueue?.enqueue(title: "SSH Key Not Found", message: "Key file does not exist: \(expandedKeyPath)")
            return
        }

        // Check if port is already in use
        if isPortInUse(tunnel.localPort) {
            alertQueue?.enqueue(title: "Port Conflict", message: "Port \(tunnel.localPort) is already in use by another process.")
            return
        }

        // Check if tunnel is already running
        if let existingRuntime = tunnelRuntimes[tunnel.id], existingRuntime.isConnected {
            toastQueue?.enqueue(message: "Tunnel '\(tunnel.name)' is already running")
            return
        }

        // Create and start tunnel runtime
        let runtime = TunnelRuntime(tunnel: tunnel, bastionIP: bastionIP, sshConfig: sshConfig)
        tunnelRuntimes[tunnel.id] = runtime

        // Subscribe to runtime changes to trigger UI updates
        let cancellable = runtime.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        tunnelCancellables[tunnel.id] = cancellable

        runtime.start()

        toastQueue?.enqueue(message: "Tunnel '\(tunnel.name)' started")
    }

    /// Stop an SSH tunnel
    func stopTunnel(tunnelId: UUID) {
        guard let runtime = tunnelRuntimes[tunnelId] else { return }

        runtime.stop()
        toastQueue?.enqueue(message: "Tunnel '\(runtime.tunnel.name)' stopped")
    }

    /// Stop all tunnels for an instance
    func stopAllTunnelsForInstance(instanceId: UUID) {
        // Find all tunnels for this instance
        for group in groups {
            if let instance = group.instances.first(where: { $0.id == instanceId }) {
                for tunnel in instance.tunnels {
                    if let runtime = tunnelRuntimes[tunnel.id], runtime.isConnected {
                        runtime.stop()
                    }
                }
            }
        }
    }

    /// Check if a local port is in use
    private func isPortInUse(_ port: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", ":\(port)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // lsof returns non-empty output if port is in use
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Open SSH terminal session for an instance
    func openSSHTerminal(instance: EC2Instance, group: InstanceGroup) {
        // Validate IP exists
        guard let bastionIP = instance.lastKnownIP else {
            alertQueue?.enqueue(title: "No IP Available", message: "Fetch the instance IP first.")
            return
        }

        // Resolve SSH config
        guard let sshConfig = resolveSSHConfig(instance: instance, group: group) else {
            alertQueue?.enqueue(title: "SSH Not Configured", message: "Configure SSH settings in the group or instance first.")
            return
        }

        // Validate key file
        let expandedKeyPath = NSString(string: sshConfig.keyPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedKeyPath) else {
            alertQueue?.enqueue(title: "SSH Key Not Found", message: "Key file does not exist: \(expandedKeyPath)")
            return
        }

        // Open terminal
        do {
            try TerminalLauncher.openSSH(
                host: bastionIP,
                username: sshConfig.username,
                keyPath: sshConfig.keyPath,
                customOptions: sshConfig.customOptions
            )
        } catch {
            alertQueue?.enqueue(title: "Failed to Open Terminal", message: error.localizedDescription)
        }
    }
}
