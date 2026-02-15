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

// Represents one service from config
struct ServiceConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var command: String
    var workingDirectory: String
    var port: Int?
    var environment: [String: String]

    init(id: UUID = UUID(), name: String, command: String, workingDirectory: String, port: Int? = nil, environment: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.port = port
        self.environment = environment
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

class ServiceRuntime: ObservableObject, Identifiable, Hashable {

    let config: ServiceConfig

    @Published var logs: String = ""
    @Published var isRunning: Bool = false
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

        // Check port before starting
        if let port = config.port {
            checkPort(port)
            if hasPortConflict {
                logs = "Port \(port) is already in use by process \(conflictingPID ?? 0). Click 'Kill & Restart' to stop it.\n"
                return
            }
        }

        logs = ""
        errors = []
        warnings = []
        lineNumber = 0
        collectingStackTrace = false
        currentStackTrace = []

        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", config.command]
        process.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)

        // Set environment with custom vars
        var env = ProcessInfo.processInfo.environment
        for (key, value) in config.environment {
            env[key] = value
        }
        process.environment = env
        
        process.standardOutput = pipe
        process.standardError = pipe
        
        self.process = process
        self.pipe = pipe
        
        // Live log streaming
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.count > 0 {
                if let output = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.logs += output

                        // Parse each line for errors/warnings
                        let lines = output.components(separatedBy: .newlines)
                        for line in lines where !line.isEmpty {
                            self.parseLine(line)
                        }
                    }
                }
            }
        }
        
        // Termination handler
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.logs += "\n[Process terminated with code \(proc.terminationStatus)]\n"

                // Check for port conflict in logs
                if let logs = self?.logs, logs.contains("EADDRINUSE") {
                    self?.detectPortConflict()
                }
            }
        }

        do {
            try process.run()
            isRunning = true
        } catch {
            logs += "Failed to start process: \(error.localizedDescription)\n"
            if let nsError = error as NSError? {
                logs += "Error domain: \(nsError.domain)\n"
                logs += "Error code: \(nsError.code)\n"
                logs += "Error details: \(nsError.userInfo)\n"
            }
        }
    }

    // Check if port is in use
    func checkPort(_ port: Int) {
        hasPortConflict = false
        conflictingPID = nil

        // Find process using this port
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

                // Handle multiple PIDs - take the first one
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

    // Kill conflicting process and restart
    func killAndRestart() {
        guard let pid = conflictingPID else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-9", "\(pid)"]

        do {
            try task.run()
            task.waitUntilExit()

            // Reset conflict state
            DispatchQueue.main.async {
                self.hasPortConflict = false
                self.conflictingPID = nil
                self.logs += "\n[Killed process \(pid)]\n"

                // Restart service
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.start()
                }
            }
        } catch {
            logs += "Failed to kill process: \(error.localizedDescription)\n"
        }
    }

    // Stop the service
    func stop() {
        guard let proc = process else { return }

        // Get PID and force kill
        let pid = proc.processIdentifier

        // Terminate the process
        proc.terminate()

        // Wait briefly for graceful shutdown
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            // Force kill if still running
            if proc.isRunning {
                let killTask = Process()
                killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                killTask.arguments = ["-9", "\(pid)"]
                try? killTask.run()
            }
        }

        process = nil
        isRunning = false
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

    func exportServices() {
        let configs = services.map { $0.config }
        guard let jsonData = try? JSONEncoder().encode(configs),
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
                    if service.hasPortConflict {
                        Text("Port \(service.config.port ?? 0) in use (PID: \(service.conflictingPID ?? 0))")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Button("Kill & Restart") {
                            service.killAndRestart()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else if service.isRunning {
                        Button("Stop") {
                            service.stop()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button("Start") {
                            service.start()
                        }
                        .buttonStyle(.borderedProminent)
                    }

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

// MARK: - Add Service View

struct AddServiceView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: ServiceManager

    @State private var name = ""
    @State private var command = ""
    @State private var workingDirectory = ""
    @State private var port = ""
    @State private var envVars: [EnvVar] = []

    struct EnvVar: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Service Name", text: $name)
                    TextField("Command", text: $command)
                    TextField("Working Directory", text: $workingDirectory)
                    TextField("Port (optional)", text: $port)
                }

                Section("Environment Variables") {
                    ForEach($envVars) { $envVar in
                        HStack {
                            TextField("Key", text: $envVar.key)
                            TextField("Value", text: $envVar.value)
                            Button(action: { removeEnvVar(envVar) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Button("Add Variable") {
                        envVars.append(EnvVar(key: "", value: ""))
                    }
                }
            }
            .navigationTitle("Add Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addService()
                    }
                    .disabled(name.isEmpty || command.isEmpty || workingDirectory.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    func addService() {
        let portInt = Int(port)
        let envDict = Dictionary(uniqueKeysWithValues: envVars.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) })

        let config = ServiceConfig(
            name: name,
            command: command,
            workingDirectory: workingDirectory,
            port: portInt,
            environment: envDict
        )

        manager.addService(config)
        dismiss()
    }

    func removeEnvVar(_ envVar: EnvVar) {
        envVars.removeAll { $0.id == envVar.id }
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

    struct EnvVar: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Service Name", text: $name)
                    TextField("Command", text: $command)
                    TextField("Working Directory", text: $workingDirectory)
                    TextField("Port (optional)", text: $port)
                }

                Section("Environment Variables") {
                    ForEach($envVars) { $envVar in
                        HStack {
                            TextField("Key", text: $envVar.key)
                            TextField("Value", text: $envVar.value)
                            Button(action: { removeEnvVar(envVar) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Button("Add Variable") {
                        envVars.append(EnvVar(key: "", value: ""))
                    }
                }
            }
            .navigationTitle("Edit Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        updateService()
                    }
                    .disabled(name.isEmpty || command.isEmpty || workingDirectory.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            // Pre-populate fields
            name = service.config.name
            command = service.config.command
            workingDirectory = service.config.workingDirectory
            port = service.config.port.map { "\($0)" } ?? ""
            envVars = service.config.environment.map { EnvVar(key: $0.key, value: $0.value) }
        }
    }

    func updateService() {
        let portInt = Int(port)
        let envDict = Dictionary(uniqueKeysWithValues: envVars.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) })

        let config = ServiceConfig(
            id: service.config.id, // Keep same ID
            name: name,
            command: command,
            workingDirectory: workingDirectory,
            port: portInt,
            environment: envDict
        )

        manager.updateService(service, with: config)
        dismiss()
    }

    func removeEnvVar(_ envVar: EnvVar) {
        envVars.removeAll { $0.id == envVar.id }
    }
}
