//
//  ContentView.swift
//  ServiceManager
//
//  Created by Dinesh Gamage on 2026-02-14.
//

import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

// MARK: - Service Model

// Prerequisite command to run before service starts
struct PrerequisiteCommand: Codable, Identifiable {
    let id: UUID
    var command: String
    var delay: Int
    var isRequired: Bool

    init(id: UUID = UUID(), command: String, delay: Int = 0, isRequired: Bool = false) {
        self.id = id
        self.command = command
        self.delay = delay
        self.isRequired = isRequired
    }
}

// Represents one service from config
struct ServiceConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var command: String
    var workingDirectory: String
    var port: Int?
    var environment: [String: String]
    var prerequisites: [PrerequisiteCommand]?
    var checkCommand: String?
    var stopCommand: String?
    var restartCommand: String?
    var maxLogLines: Int?

    init(id: UUID = UUID(), name: String, command: String, workingDirectory: String, port: Int? = nil, environment: [String: String] = [:], prerequisites: [PrerequisiteCommand]? = nil, checkCommand: String? = nil, stopCommand: String? = nil, restartCommand: String? = nil, maxLogLines: Int? = 1000) {
        self.id = id
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.port = port
        self.environment = environment
        self.prerequisites = prerequisites
        self.checkCommand = checkCommand
        self.stopCommand = stopCommand
        self.restartCommand = restartCommand
        self.maxLogLines = maxLogLines
    }
}

// MARK: - Log Entry Model

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let lineNumber: Int
    let timestamp: Date
    let type: LogType
    var stackTrace: [String]?

    enum LogType {
        case error
        case warning
    }
}

// MARK: - Service Runtime State

@MainActor
class ServiceRuntime: ObservableObject, Identifiable, Hashable {

    let config: ServiceConfig

    @Published var logs: String = ""
    @Published var isRunning: Bool = false
    @Published var isExternallyManaged: Bool = false
    @Published var hasPortConflict: Bool = false
    @Published var conflictingPID: Int? = nil
    @Published var errors: [LogEntry] = []
    @Published var warnings: [LogEntry] = []

    private var process: Process?
    private var pipe: Pipe?

    // Identifiable conformance
    var id: UUID { config.id }

    init(config: ServiceConfig) {
        self.config = config
    }

    // Hashable conformance
    static func == (lhs: ServiceRuntime, rhs: ServiceRuntime) -> Bool {
        lhs.config.id == rhs.config.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(config.id)
    }

    // Parse log line for errors and warnings
    private var lineNumber = 0
    private var collectingStackTrace = false
    private var currentStackTrace: [String] = []

    private func parseLine(_ line: String) {
        lineNumber += 1
        let lowercased = line.lowercased()
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Stack trace line patterns (indented, starts with "at ", frame info, etc.)
        let isStackTraceLine = line.hasPrefix("    ") ||
                               line.hasPrefix("\t") ||
                               trimmed.hasPrefix("at ") ||
                               trimmed.contains("(") && trimmed.contains(")") && trimmed.contains(":") ||
                               trimmed.hasPrefix("File ") ||
                               trimmed.matches(of: /^\s*\d+\s+/).count > 0

        // If we're collecting a stack trace
        if collectingStackTrace {
            if isStackTraceLine && !trimmed.isEmpty {
                currentStackTrace.append(trimmed)
                return
            } else {
                // Stack trace ended, attach to last error
                if !currentStackTrace.isEmpty, !errors.isEmpty {
                    errors[errors.count - 1].stackTrace = currentStackTrace
                }
                collectingStackTrace = false
                currentStackTrace = []
            }
        }

        // Error patterns
        let errorPatterns = [
            "error", "err", "fatal", "fail", "failed", "failure",
            "exception", "panic", "critical", "severe", "cannot",
            "unable to", "not found", "invalid", "undefined",
            "traceback", "stacktrace"
        ]

        // Warning patterns
        let warningPatterns = [
            "warning", "warn", "deprecated", "obsolete", "caution",
            "notice", "should", "recommend", "may cause"
        ]

        // Check for errors
        for pattern in errorPatterns {
            if lowercased.contains(pattern) {
                let entry = LogEntry(
                    message: trimmed,
                    lineNumber: lineNumber,
                    timestamp: Date(),
                    type: .error,
                    stackTrace: nil
                )
                errors.append(entry)

                // Start collecting stack trace
                collectingStackTrace = true
                currentStackTrace = []
                return // Don't double-count as error and warning
            }
        }

        // Check for warnings
        for pattern in warningPatterns {
            if lowercased.contains(pattern) {
                let entry = LogEntry(
                    message: trimmed,
                    lineNumber: lineNumber,
                    timestamp: Date(),
                    type: .warning,
                    stackTrace: nil
                )
                warnings.append(entry)
                return
            }
        }
    }

    // Start the service
    func start() {
        if isRunning { return }

        logs = ""
        errors = []
        warnings = []
        lineNumber = 0
        collectingStackTrace = false
        currentStackTrace = []

        let config = self.config

        Task {
            // Execute prerequisites off main
            let prereqs = config.prerequisites ?? []
            if !prereqs.isEmpty {
                await MainActor.run { self.logs += "[Prerequisites] Running \(prereqs.count) prerequisite command(s)\n" }

                for (index, prereq) in prereqs.enumerated() {
                    await MainActor.run { self.logs += "[Prerequisites] [\(index + 1)/\(prereqs.count)] Running: \(prereq.command)\n" }

                    let result = await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
                        task.arguments = ["-c", prereq.command]
                        task.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)
                        let pipe = Pipe()
                        task.standardOutput = pipe
                        task.standardError = pipe
                        do {
                            try task.run()
                            task.waitUntilExit()
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            let output = String(data: data, encoding: .utf8) ?? ""
                            return (task.terminationStatus, output)
                        } catch {
                            return (-1, error.localizedDescription)
                        }
                    }.value

                    let (exitCode, output) = result
                    if !output.isEmpty { await MainActor.run { self.logs += output } }

                    if exitCode != 0 {
                        if prereq.isRequired {
                            await MainActor.run {
                                self.logs += "[Prerequisites] ❌ Required prerequisite failed with exit code \(exitCode)\n"
                                self.logs += "[Prerequisites] Stopping service start due to required prerequisite failure\n"
                            }
                            return
                        } else {
                            await MainActor.run { self.logs += "[Prerequisites] ⚠️ Optional prerequisite failed with exit code \(exitCode), continuing...\n" }
                        }
                    } else {
                        await MainActor.run { self.logs += "[Prerequisites] ✓ Command completed successfully\n" }
                    }

                    if prereq.delay > 0 {
                        await MainActor.run { self.logs += "[Prerequisites] Waiting \(prereq.delay)s before continuing...\n" }
                        try? await Task.sleep(nanoseconds: UInt64(prereq.delay) * 1_000_000_000)
                    }
                }
            }

            // Check port before starting
            if let port = config.port {
                let pid = await Task.detached(priority: .userInitiated) { () -> Int? in
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                    task.arguments = ["-i", ":\(port)", "-t"]
                    let pipe = Pipe()
                    task.standardOutput = pipe
                    try? task.run()
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let trimmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return trimmed.components(separatedBy: .newlines).first.flatMap { Int($0) }
                }.value

                await MainActor.run {
                    self.hasPortConflict = pid != nil
                    self.conflictingPID = pid
                    if pid != nil {
                        self.logs += "Port \(port) is already in use by process \(pid!). Click 'Kill & Restart' to stop it.\n"
                    }
                }
                if pid != nil { return }
            }

            await MainActor.run { self.logs += "[Starting] \(config.name)\n" }

            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", config.command]
            process.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)

            var env = ProcessInfo.processInfo.environment
            for (key, value) in config.environment { env[key] = value }
            process.environment = env

            process.standardOutput = pipe
            process.standardError = pipe

            await MainActor.run {
                self.process = process
                self.pipe = pipe
            }

            // Live log streaming
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.count > 0, let output = String(data: data, encoding: .utf8) {
                    Task { @MainActor in
                        self.logs += output
                        let lines = output.components(separatedBy: .newlines)
                        for line in lines where !line.isEmpty {
                            self.parseLine(line)
                        }
                        // Amortized trim: only split/join when well over the limit
                        if let max = self.config.maxLogLines {
                            let threshold = max + 200
                            let approxCount = self.logs.lazy.filter { $0 == "\n" }.count
                            if approxCount > threshold {
                                let allLines = self.logs.components(separatedBy: "\n")
                                self.logs = allLines.suffix(max).joined(separator: "\n")
                            }
                        }
                    }
                }
            }

            // Termination handler
            process.terminationHandler = { [weak self] proc in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.logs += "\n[Process terminated with code \(proc.terminationStatus)]\n"
                    if self.logs.contains("EADDRINUSE") {
                        self.detectPortConflict()
                    }
                    // If a check command or port is configured, re-check true state
                    // (handles fire-and-forget launchers like `open -a Docker`)
                    if self.config.checkCommand != nil || self.config.port != nil {
                        self.checkStatus()
                    } else {
                        self.process = nil
                        self.isRunning = false
                    }
                }
            }

            do {
                try process.run()
                await MainActor.run { self.isRunning = true }
            } catch {
                await MainActor.run {
                    self.logs += "Failed to start process: \(error.localizedDescription)\n"
                }
            }
        }
    }

    // Check if port is in use — must be called from main thread
    func checkPort(_ port: Int) {
        hasPortConflict = false
        conflictingPID = nil

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-i", ":\(port)", "-t"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let pids = trimmed.components(separatedBy: .newlines)
                    if let firstPID = pids.first, let pid = Int(firstPID) {
                        hasPortConflict = true
                        conflictingPID = pid
                        logs += "[Port Check] Port \(port) is in use by PID \(pid)\n"
                    }
                } else {
                    logs += "[Port Check] Port \(port) is free\n"
                }
            }
        } catch {
            logs += "[Port Check] Failed to check port \(port): \(error.localizedDescription)\n"
        }
    }

    // Detect port conflict from error logs
    func detectPortConflict() {
        guard let port = config.port else { return }
        checkPort(port)
    }

    // Check if service is running (via checkCommand or port fallback)
    // Safe to call from any thread — blocking work runs in a detached task
    func checkStatus() {
        let config = self.config
        let ownedProcess = self.process

        if let checkCmd = config.checkCommand, !checkCmd.isEmpty {
            Task.detached {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/zsh")
                task.arguments = ["-c", checkCmd]
                task.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)
                do {
                    try task.run()
                    task.waitUntilExit()
                    let running = task.terminationStatus == 1
                    await MainActor.run {
                        if running && ownedProcess == nil {
                            self.isExternallyManaged = true
                            self.isRunning = true
                        } else if !running {
                            self.isExternallyManaged = false
                            self.isRunning = ownedProcess?.isRunning ?? false
                        }
                        self.logs += "[Check] Service is \(running ? "running" : "not running")\(self.isExternallyManaged ? " (external)" : "")\n"
                    }
                } catch {
                    await MainActor.run {
                        self.logs += "[Check] Failed to run check command: \(error.localizedDescription)\n"
                    }
                }
            }
        } else if let port = config.port {
            Task.detached {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                task.arguments = ["-i", ":\(port)", "-t"]
                let pipe = Pipe()
                task.standardOutput = pipe
                do {
                    try task.run()
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let trimmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let pid = trimmed.components(separatedBy: .newlines).first.flatMap { Int($0) }
                    await MainActor.run {
                        self.hasPortConflict = pid != nil
                        self.conflictingPID = pid
                        if pid != nil && ownedProcess == nil {
                            self.isExternallyManaged = true
                            self.isRunning = true
                        }
                        self.logs += "[Check] Port \(port) is \(pid != nil ? "in use by PID \(pid!)" : "free")\n"
                    }
                } catch {
                    await MainActor.run {
                        self.logs += "[Check] Failed to check port \(port): \(error.localizedDescription)\n"
                    }
                }
            }
        } else {
            logs += "[Check] No check command or port configured\n"
        }
    }

    // Kill conflicting process and restart
    func killAndRestart() {
        guard let pid = conflictingPID else { return }
        Task {
            let success = await Task.detached(priority: .userInitiated) { () -> Bool in
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/kill")
                task.arguments = ["-9", "\(pid)"]
                do { try task.run(); task.waitUntilExit(); return true }
                catch { return false }
            }.value

            if success {
                hasPortConflict = false
                conflictingPID = nil
                logs += "\n[Killed process \(pid)]\n"
                try? await Task.sleep(nanoseconds: 500_000_000)
                start()
            } else {
                logs += "Failed to kill process \(pid)\n"
            }
        }
    }

    // Stop the service
    func stop() {
        let config = self.config

        // Case 1: custom stop command
        if let stopCmd = config.stopCommand, !stopCmd.isEmpty {
            Task {
                let output = await Task.detached(priority: .userInitiated) { () -> String in
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    task.arguments = ["-c", stopCmd]
                    task.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)
                    let pipe = Pipe()
                    task.standardOutput = pipe
                    task.standardError = pipe
                    do {
                        try task.run(); task.waitUntilExit()
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        return String(data: data, encoding: .utf8) ?? ""
                    } catch { return "[Stop] Failed: \(error.localizedDescription)\n" }
                }.value
                if !output.isEmpty { logs += output }
                process = nil
                isRunning = false
                isExternallyManaged = false
            }
            return
        }

        // Case 2: we own the process
        if let proc = process {
            let pid = proc.processIdentifier
            proc.terminate()
            process = nil
            isRunning = false
            isExternallyManaged = false
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let stillRunning = await Task.detached(priority: .userInitiated) { proc.isRunning }.value
                if stillRunning {
                    let killTask = Process()
                    killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                    killTask.arguments = ["-9", "\(pid)"]
                    try? killTask.run()
                }
            }
            return
        }

        // Case 3: externally managed — use port-based PID kill
        if let port = config.port {
            Task {
                let pid = await Task.detached(priority: .userInitiated) { () -> Int? in
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                    task.arguments = ["-i", ":\(port)", "-t"]
                    let pipe = Pipe()
                    task.standardOutput = pipe
                    try? task.run(); task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let trimmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return trimmed.components(separatedBy: .newlines).first.flatMap { Int($0) }
                }.value

                if let pid {
                    let killed = await Task.detached(priority: .userInitiated) { () -> Bool in
                        let killTask = Process()
                        killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                        killTask.arguments = ["-9", "\(pid)"]
                        do { try killTask.run(); killTask.waitUntilExit(); return true }
                        catch { return false }
                    }.value
                    logs += killed ? "[Stop] Killed external process \(pid) on port \(port)\n"
                                   : "[Stop] Failed to kill external process \(pid)\n"
                } else {
                    logs += "[Stop] No process found on port \(port)\n"
                }
                isRunning = false
                isExternallyManaged = false
                hasPortConflict = false
                conflictingPID = nil
            }
            return
        }

        // Case 4: no way to stop
        logs += "[Stop] Cannot stop: no stop command or port configured\n"
    }

    // Restart the service
    func restart() {
        let config = self.config
        if let restartCmd = config.restartCommand, !restartCmd.isEmpty {
            Task {
                let output = await Task.detached(priority: .userInitiated) { () -> String in
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    task.arguments = ["-c", restartCmd]
                    task.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)
                    let pipe = Pipe()
                    task.standardOutput = pipe
                    task.standardError = pipe
                    do {
                        try task.run(); task.waitUntilExit()
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        return String(data: data, encoding: .utf8) ?? ""
                    } catch { return "[Restart] Failed: \(error.localizedDescription)\n" }
                }.value
                if !output.isEmpty { logs += output }
                logs += "[Restart] Command completed\n"
            }
        } else {
            stop()
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                start()
            }
        }
    }

    // Clear errors
    func clearErrors() {
        errors.removeAll()
    }

    // Clear warnings
    func clearWarnings() {
        warnings.removeAll()
    }
}

// MARK: - Service Manager (Data Layer)

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
        for service in services {
            service.checkStatus()
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

// MARK: - Main View

struct ContentView: View {

    @StateObject private var manager = ServiceManager()
    @State private var selectedServiceId: UUID?
    @State private var showingAddService = false
    @State private var showingEditService = false
    @State private var showingDeleteAlert = false
    @State private var showingJSONEditor = false
    @State private var serviceToDelete: ServiceRuntime?
    @State private var serviceToEditId: UUID?

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // Header with buttons
                HStack {
                    Text("Services")
                        .font(.headline)
                    Spacer()

                    Button(action: { manager.checkAllServices() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Check All Services")

                    Button(action: { manager.importServices() }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .help("Import Services")

                    Button(action: { manager.exportServices() }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .help("Export Services")

                    Button(action: { showingJSONEditor = true }) {
                        Image(systemName: "curlybraces")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit JSON")

                    Button(action: { showingAddService = true }) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Add Service")
                }
                .padding()

                Divider()

                // Service list
                List(manager.services, selection: $selectedServiceId) { service in
                    ServiceListItem(service: service) {
                        // Show delete confirmation
                        serviceToDelete = service
                        showingDeleteAlert = true
                    } onEdit: {
                        // Show edit sheet
                        serviceToEditId = service.id
                        showingEditService = true
                    }
                    .tag(service.id)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 250)
        } detail: {
            // Detail view
            if let selectedId = selectedServiceId,
               let service = manager.services.first(where: { $0.id == selectedId }) {
                ServiceDetailView(service: service)
                    .id(selectedId)
            } else {
                Text("Select a service")
                    .foregroundColor(.gray)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showingAddService) {
            AddServiceView(manager: manager)
        }
        .sheet(isPresented: $showingEditService, onDismiss: {
            serviceToEditId = nil
        }) {
            if let editId = serviceToEditId,
               let service = manager.services.first(where: { $0.id == editId }) {
                EditServiceView(manager: manager, service: service)
            }
        }
        .id(serviceToEditId)
        .sheet(isPresented: $showingJSONEditor, onDismiss: {
            // Force refresh of selected service after JSON changes
            if let currentId = selectedServiceId {
                // Check if the selected service still exists
                if manager.services.first(where: { $0.id == currentId }) != nil {
                    // Force refresh by temporarily clearing and restoring
                    let tempId = currentId
                    selectedServiceId = nil
                    DispatchQueue.main.async {
                        selectedServiceId = tempId
                    }
                } else {
                    // Selected service was deleted, select first available
                    selectedServiceId = manager.services.first?.id
                }
            }
        }) {
            JSONEditorView(manager: manager)
        }
        .alert("Delete Service", isPresented: $showingDeleteAlert, presenting: serviceToDelete) { service in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let index = manager.services.firstIndex(where: { $0.id == service.id }) {
                    manager.deleteService(at: IndexSet(integer: index))
                    if selectedServiceId == service.id {
                        selectedServiceId = manager.services.first?.id
                    }
                }
            }
        } message: { service in
            Text("Are you sure you want to delete '\(service.config.name)'? This action cannot be undone.")
        }
        .alert("Import Complete", isPresented: $manager.showImportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let message = manager.importMessage {
                Text(message)
            }
        }
        .onAppear {
            if let first = manager.services.first {
                selectedServiceId = first.id
            }
            manager.checkAllServices()
        }
    }
}

// MARK: - Sidebar List Item

struct ServiceListItem: View {
    @ObservedObject var service: ServiceRuntime
    var onDelete: () -> Void
    var onEdit: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            Circle()
                .fill(service.isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(service.config.name)
                .font(.body)

            Spacer()

            if isHovering {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Service Detail View

struct ServiceDetailView: View {
    @ObservedObject var service: ServiceRuntime
    @State private var showingErrors = false
    @State private var showingWarnings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with actions
            VStack(alignment: .leading, spacing: 8) {
                Text(service.config.name)
                    .font(.title2)
                    .fontWeight(.bold)

                // Action buttons
                HStack {
                    if service.isRunning {
                        if service.isExternallyManaged {
                            Text("Running outside ServiceManager")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        Button("Stop") {
                            service.stop()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button("Restart") {
                            service.restart()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        if service.isExternallyManaged {
                            Button("Kill & Start") {
                                service.stop()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    service.start()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                    } else if service.hasPortConflict {
                        Text("Port \(service.config.port ?? 0) in use (PID: \(service.conflictingPID ?? 0))")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Button("Kill & Restart") {
                            service.killAndRestart()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button("Start") {
                            service.start()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        service.checkStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Check service status")

                    Spacer()

                    // Error/Warning badges
                    if !service.errors.isEmpty {
                        HStack(spacing: 6) {
                            Button(action: { showingErrors = true; showingWarnings = false }) {
                                HStack(spacing: 4) {
                                    Text("❌")
                                    Text("\(service.errors.count)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .frame(height: 12)

                            Button(action: {
                                service.clearErrors()
                                showingErrors = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Clear all errors")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }

                    if !service.warnings.isEmpty {
                        HStack(spacing: 6) {
                            Button(action: { showingWarnings = true; showingErrors = false }) {
                                HStack(spacing: 4) {
                                    Text("⚠️")
                                    Text("\(service.warnings.count)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .frame(height: 12)

                            Button(action: {
                                service.clearWarnings()
                                showingWarnings = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .foregroundColor(.orange.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Clear all warnings")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Circle()
                        .fill(service.isRunning ? Color.green : Color.red)
                        .frame(width: 12, height: 12)

                    Text(service.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Divider()

                // Service info
                VStack(alignment: .leading, spacing: 4) {
                    Label("Command: \(service.config.command)", systemImage: "terminal")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("Directory: \(service.config.workingDirectory)", systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let port = service.config.port {
                        Label("Port: \(port)", systemImage: "network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !service.config.environment.isEmpty {
                        Label("Environment: \(service.config.environment.keys.joined(separator: ", "))", systemImage: "gearshape")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let prereqs = service.config.prerequisites, !prereqs.isEmpty {
                        Label("Prerequisites: \(prereqs.count) command(s)", systemImage: "list.bullet.clipboard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()

            Divider()

            // Logs or Error/Warning List
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if showingErrors || showingWarnings {
                        Button(action: {
                            showingErrors = false
                            showingWarnings = false
                        }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back to Output")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading)
                    }

                    Text(showingErrors ? "Errors" : showingWarnings ? "Warnings" : "Output")
                        .font(.headline)
                        .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 8)

                if showingErrors {
                    ErrorWarningListView(entries: service.errors, type: .error)
                } else if showingWarnings {
                    ErrorWarningListView(entries: service.warnings, type: .warning)
                } else {
                    LogView(logs: service.logs)
                }
            }
        }
        .onAppear {
            service.checkStatus()
        }
    }
}

// MARK: - Error/Warning List View

struct ErrorWarningListView: View {
    let entries: [LogEntry]
    let type: LogEntry.LogType

    @State private var expandedEntries: Set<UUID> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(type == .error ? "❌" : "⚠️")
                                .font(.body)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Line \(entry.lineNumber)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Text(entry.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text(entry.message)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)

                                // Stack trace toggle button
                                if let stackTrace = entry.stackTrace, !stackTrace.isEmpty {
                                    Button(action: {
                                        if expandedEntries.contains(entry.id) {
                                            expandedEntries.remove(entry.id)
                                        } else {
                                            expandedEntries.insert(entry.id)
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: expandedEntries.contains(entry.id) ? "chevron.down" : "chevron.right")
                                                .font(.caption)
                                            Text("Stack Trace (\(stackTrace.count) lines)")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 4)
                                }
                            }
                        }
                        .padding(8)

                        // Expandable stack trace
                        if let stackTrace = entry.stackTrace,
                           !stackTrace.isEmpty,
                           expandedEntries.contains(entry.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(stackTrace.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                        .padding(.leading, 32)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                        }
                    }
                    .background(type == .error ? Color.red.opacity(0.05) : Color.orange.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.05))
    }
}

// MARK: - Auto-scrolling Log View

struct LogView: View {
    let logs: String

    @State private var shouldAutoScroll = true
    @State private var searchText = ""

    private var matchCount: Int {
        guard !searchText.isEmpty else { return 0 }
        let lowercasedLogs = logs.lowercased()
        let lowercasedSearch = searchText.lowercased()
        var count = 0
        var searchRange = lowercasedLogs.startIndex..<lowercasedLogs.endIndex

        while let range = lowercasedLogs.range(of: lowercasedSearch, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<lowercasedLogs.endIndex
        }
        return count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))

                TextField("Search in output...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Text("\(matchCount) match\(matchCount == 1 ? "" : "es")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)

                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .padding(8)

            // Logs with highlighting
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if searchText.isEmpty {
                            Text(logs)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        } else {
                            Text(highlightedAttributedString(logs, searchText: searchText))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }

                        // Invisible anchor at bottom
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.05))
                .onChange(of: logs) { oldValue, newValue in
                    if shouldAutoScroll && searchText.isEmpty {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func highlightedAttributedString(_ text: String, searchText: String) -> AttributedString {
        var attributedString = AttributedString(text)
        let lowercasedText = text.lowercased()
        let lowercasedSearch = searchText.lowercased()

        var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex

        while let matchRange = lowercasedText.range(of: lowercasedSearch, range: searchRange) {
            // Convert String.Index to AttributedString.Index
            let lowerBound = AttributedString.Index(matchRange.lowerBound, within: attributedString)!
            let upperBound = AttributedString.Index(matchRange.upperBound, within: attributedString)!
            let attrRange = lowerBound..<upperBound

            // Apply yellow background to match
            attributedString[attrRange].backgroundColor = .yellow.opacity(0.5)

            // Continue searching after this match
            searchRange = matchRange.upperBound..<lowercasedText.endIndex
        }

        return attributedString
    }
}

// MARK: - Shared form model

struct EnvVar: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

// MARK: - Shared Service Form Content

struct ServiceFormContent: View {
    @Binding var name: String
    @Binding var command: String
    @Binding var workingDirectory: String
    @Binding var port: String
    @Binding var envVars: [EnvVar]
    @Binding var prerequisites: [PrerequisiteCommand]
    @Binding var checkCommand: String
    @Binding var stopCommand: String
    @Binding var restartCommand: String
    @Binding var maxLogLines: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Basic Info
                FormSection(title: "Basic Info") {
                    HStack(spacing: 12) {
                        FormField(label: "Name") {
                            TextField("My Service", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        FormField(label: "Port", width: 100) {
                            TextField("8080", text: $port)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    FormField(label: "Command") {
                        TextField("/usr/bin/myservice start", text: $command)
                            .textFieldStyle(.roundedBorder)
                    }
                    FormField(label: "Working Directory") {
                        TextField("/Users/me/project", text: $workingDirectory)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Environment Variables
                FormSection(title: "Environment Variables") {
                    ForEach($envVars) { $envVar in
                        HStack(spacing: 8) {
                            TextField("KEY", text: $envVar.key)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 160)
                            TextField("value", text: $envVar.value)
                                .textFieldStyle(.roundedBorder)
                            Button(action: { envVars.removeAll { $0.id == envVar.id } }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button(action: { envVars.append(EnvVar(key: "", value: "")) }) {
                        Label("Add Variable", systemImage: "plus.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                // Prerequisites
                FormSection(title: "Prerequisites") {
                    ForEach($prerequisites) { $prereq in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                TextField("Command", text: $prereq.command)
                                    .textFieldStyle(.roundedBorder)
                                Button(action: { prerequisites.removeAll { $0.id == prereq.id } }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            HStack(spacing: 16) {
                                HStack(spacing: 6) {
                                    Text("Delay (s)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("0", value: $prereq.delay, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 56)
                                }
                                Toggle("Required", isOn: $prereq.isRequired)
                                    .toggleStyle(.checkbox)
                                    .font(.callout)
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                    }
                    Button(action: { prerequisites.append(PrerequisiteCommand(command: "", delay: 0, isRequired: false)) }) {
                        Label("Add Prerequisite", systemImage: "plus.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                // Advanced Commands
                FormSection(title: "Advanced Commands") {
                    FormField(label: "Check Command", hint: "Exit code: 1 = running, 0 = stopped") {
                        TextField("pgrep -x myservice", text: $checkCommand)
                            .textFieldStyle(.roundedBorder)
                    }
                    FormField(label: "Stop Command", hint: "Defaults to SIGTERM → SIGKILL or port-based kill") {
                        TextField("myservice stop", text: $stopCommand)
                            .textFieldStyle(.roundedBorder)
                    }
                    FormField(label: "Restart Command", hint: "Defaults to stop + start") {
                        TextField("myservice restart", text: $restartCommand)
                            .textFieldStyle(.roundedBorder)
                    }
                    FormField(label: "Max Log Lines", hint: "Default 1000. Leave empty for unlimited.") {
                        TextField("1000", text: $maxLogLines)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Form helpers

struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Divider()
            content()
        }
    }
}

struct FormField<Content: View>: View {
    let label: String
    var hint: String? = nil
    var width: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
            content()
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: width ?? .infinity, alignment: .leading)
    }
}

// MARK: - Add Service View

struct AddServiceView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: ServiceManager

    @State private var name = ""
    @State private var command = ""
    @State private var workingDirectory = ""
    @State private var port = ""
    @State private var envVars: [EnvVar] = []
    @State private var prerequisites: [PrerequisiteCommand] = []
    @State private var checkCommand = ""
    @State private var stopCommand = ""
    @State private var restartCommand = ""
    @State private var maxLogLines = "1000"

    var body: some View {
        NavigationStack {
            ServiceFormContent(
                name: $name, command: $command, workingDirectory: $workingDirectory,
                port: $port, envVars: $envVars, prerequisites: $prerequisites,
                checkCommand: $checkCommand, stopCommand: $stopCommand, restartCommand: $restartCommand,
                maxLogLines: $maxLogLines
            )
            .navigationTitle("Add Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addService() }
                        .disabled(name.isEmpty || command.isEmpty || workingDirectory.isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 500)
    }

    func addService() {
        let portInt = Int(port)
        let envDict = Dictionary(uniqueKeysWithValues: envVars.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) })
        let validPrereqs = prerequisites.filter { !$0.command.isEmpty }

        let config = ServiceConfig(
            name: name, command: command, workingDirectory: workingDirectory,
            port: portInt, environment: envDict,
            prerequisites: validPrereqs.isEmpty ? nil : validPrereqs,
            checkCommand: checkCommand.isEmpty ? nil : checkCommand,
            stopCommand: stopCommand.isEmpty ? nil : stopCommand,
            restartCommand: restartCommand.isEmpty ? nil : restartCommand,
            maxLogLines: maxLogLines.isEmpty ? nil : Int(maxLogLines)
        )
        manager.addService(config)
        dismiss()
    }
}

// MARK: - Edit Service View

struct EditServiceView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: ServiceManager
    let service: ServiceRuntime

    @State private var name = ""
    @State private var command = ""
    @State private var workingDirectory = ""
    @State private var port = ""
    @State private var envVars: [EnvVar] = []
    @State private var prerequisites: [PrerequisiteCommand] = []
    @State private var checkCommand = ""
    @State private var stopCommand = ""
    @State private var restartCommand = ""
    @State private var maxLogLines = "1000"

    var body: some View {
        NavigationStack {
            ServiceFormContent(
                name: $name, command: $command, workingDirectory: $workingDirectory,
                port: $port, envVars: $envVars, prerequisites: $prerequisites,
                checkCommand: $checkCommand, stopCommand: $stopCommand, restartCommand: $restartCommand,
                maxLogLines: $maxLogLines
            )
            .navigationTitle("Edit Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { updateService() }
                        .disabled(name.isEmpty || command.isEmpty || workingDirectory.isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 500)
        .onAppear {
            name = service.config.name
            command = service.config.command
            workingDirectory = service.config.workingDirectory
            port = service.config.port.map { "\($0)" } ?? ""
            envVars = service.config.environment.map { EnvVar(key: $0.key, value: $0.value) }
            prerequisites = service.config.prerequisites ?? []
            checkCommand = service.config.checkCommand ?? ""
            stopCommand = service.config.stopCommand ?? ""
            restartCommand = service.config.restartCommand ?? ""
            maxLogLines = service.config.maxLogLines.map { "\($0)" } ?? ""
        }
    }

    func updateService() {
        let portInt = Int(port)
        let envDict = Dictionary(uniqueKeysWithValues: envVars.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) })
        let validPrereqs = prerequisites.filter { !$0.command.isEmpty }

        let config = ServiceConfig(
            id: service.config.id,
            name: name, command: command, workingDirectory: workingDirectory,
            port: portInt, environment: envDict,
            prerequisites: validPrereqs.isEmpty ? nil : validPrereqs,
            checkCommand: checkCommand.isEmpty ? nil : checkCommand,
            stopCommand: stopCommand.isEmpty ? nil : stopCommand,
            restartCommand: restartCommand.isEmpty ? nil : restartCommand,
            maxLogLines: maxLogLines.isEmpty ? nil : Int(maxLogLines)
        )
        manager.updateService(service, with: config)
        dismiss()
    }
}

// MARK: - Plain Text Editor (without smart quotes)

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: PlainTextEditor

        init(_ parent: PlainTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - JSON Editor View

struct JSONEditorView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: ServiceManager

    @State private var jsonText: String = ""
    @State private var errorMessage: String?
    @State private var isValidJSON: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Error banner
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                }

                // JSON Editor
                PlainTextEditor(text: $jsonText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: jsonText) { oldValue, newValue in
                        validateJSON()
                    }
            }
            .navigationTitle("Edit Services JSON")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveJSON()
                    }
                    .disabled(!isValidJSON)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            loadJSON()
        }
    }

    func loadJSON() {
        let configs = manager.services.map { $0.config }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        if let jsonData = try? encoder.encode(configs),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            jsonText = jsonString
        }
    }

    func validateJSON() {
        guard let jsonData = jsonText.data(using: .utf8) else {
            errorMessage = "Invalid text encoding"
            isValidJSON = false
            return
        }

        do {
            let _ = try JSONDecoder().decode([ServiceConfig].self, from: jsonData)
            errorMessage = nil
            isValidJSON = true
        } catch {
            errorMessage = "Invalid JSON: \(error.localizedDescription)"
            isValidJSON = false
        }
    }

    func saveJSON() {
        guard let jsonData = jsonText.data(using: .utf8),
              let configs = try? JSONDecoder().decode([ServiceConfig].self, from: jsonData) else {
            return
        }

        // Replace all services with new ones
        manager.services = configs.map { ServiceRuntime(config: $0) }
        manager.saveServices()
        manager.objectWillChange.send()

        dismiss()
    }
}
