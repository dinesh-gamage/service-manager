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

// MARK: - Service Runtime State

class ServiceRuntime: ObservableObject, Identifiable, Hashable {

    let config: ServiceConfig

    @Published var logs: String = ""
    @Published var isRunning: Bool = false
    @Published var hasPortConflict: Bool = false
    @Published var conflictingPID: Int? = nil

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
    @State private var selectedService: ServiceRuntime?
    @State private var showingAddService = false
    @State private var showingDeleteAlert = false
    @State private var serviceToDelete: ServiceRuntime?

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
                List(manager.services, selection: $selectedService) { service in
                    ServiceListItem(service: service) {
                        // Show delete confirmation
                        serviceToDelete = service
                        showingDeleteAlert = true
                    }
                    .tag(service)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 250)
        } detail: {
            // Detail view
            if let service = selectedService {
                ServiceDetailView(service: service)
            } else {
                Text("Select a service")
                    .foregroundColor(.gray)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showingAddService) {
            AddServiceView(manager: manager)
        }
        .alert("Delete Service", isPresented: $showingDeleteAlert, presenting: serviceToDelete) { service in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let index = manager.services.firstIndex(where: { $0.id == service.id }) {
                    manager.deleteService(at: IndexSet(integer: index))
                    if selectedService?.id == service.id {
                        selectedService = manager.services.first
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
                selectedService = first
            }
        }
    }
}

// MARK: - Sidebar List Item

struct ServiceListItem: View {
    @ObservedObject var service: ServiceRuntime
    var onDelete: () -> Void

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

            // Logs
            VStack(alignment: .leading, spacing: 8) {
                Text("Output")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)

                LogView(logs: service.logs)
            }
        }
    }
}

// MARK: - Auto-scrolling Log View

struct LogView: View {
    let logs: String

    @State private var shouldAutoScroll = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(logs)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)

                    // Invisible anchor at bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.05))
            .onChange(of: logs) { oldValue, newValue in
                if shouldAutoScroll {
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
