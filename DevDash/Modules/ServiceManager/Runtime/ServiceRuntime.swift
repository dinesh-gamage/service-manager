//
//  ServiceRuntime.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation
import SwiftUI
import Combine

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

    // Ring buffer for logs: fixed-size array of lines
    private var logLines: [String] = []
    private let maxBufferLines: Int

    // Log batching: buffer incoming data, flush on timer
    private var logBuffer = ""
    private var flushTimer: DispatchSourceTimer?

    // Flag set when "EADDRINUSE" is seen in a chunk (avoids full log scan at termination)
    private var seenEADDRINUSE = false

    // Static pattern arrays — allocated once, not per parsed line
    private static let errorPatterns: [String] = [
        "error", "err", "fatal", "fail", "failed", "failure",
        "exception", "panic", "critical", "severe", "cannot",
        "unable to", "not found", "invalid", "undefined",
        "traceback", "stacktrace"
    ]
    private static let warningPatterns: [String] = [
        "warning", "warn", "deprecated", "obsolete", "caution",
        "notice", "should", "recommend", "may cause"
    ]

    // Pre-compiled regex for stack trace numeric-line detection
    private static let stackTraceLineRegex = /^\s*\d+\s+/

    // Cap on errors/warnings arrays to prevent unbounded memory growth
    private static let maxEntries = 500
    private static let trimToEntries = 400

    // Identifiable conformance
    var id: UUID { config.id }

    init(config: ServiceConfig) {
        self.config = config
        self.maxBufferLines = config.maxLogLines ?? 1000
    }

    deinit {
        // Clean up resources - must happen synchronously in deinit
        flushTimer?.cancel()
        flushTimer = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
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
                               trimmed.contains(Self.stackTraceLineRegex)

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

        // Check for errors
        for pattern in Self.errorPatterns {
            if lowercased.contains(pattern) {
                let entry = LogEntry(
                    message: trimmed,
                    lineNumber: lineNumber,
                    timestamp: Date(),
                    type: .error,
                    stackTrace: nil
                )
                errors.append(entry)
                if errors.count > Self.maxEntries {
                    errors.removeFirst(errors.count - Self.trimToEntries)
                }
                collectingStackTrace = true
                currentStackTrace = []
                return
            }
        }

        // Check for warnings
        for pattern in Self.warningPatterns {
            if lowercased.contains(pattern) {
                let entry = LogEntry(
                    message: trimmed,
                    lineNumber: lineNumber,
                    timestamp: Date(),
                    type: .warning,
                    stackTrace: nil
                )
                warnings.append(entry)
                if warnings.count > Self.maxEntries {
                    warnings.removeFirst(warnings.count - Self.trimToEntries)
                }
                return
            }
        }
    }

    // MARK: - Log flush (called on main queue by timer)

    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.flushLogBuffer()
        }
        timer.resume()
        flushTimer = timer
    }

    private func stopFlushTimer() {
        flushTimer?.cancel()
        flushTimer = nil
        // Flush any remaining buffered data
        flushLogBuffer()
    }

    private func flushLogBuffer() {
        guard !logBuffer.isEmpty else { return }
        let chunk = logBuffer
        logBuffer = ""

        // Check for EADDRINUSE in the chunk (cheap, only chunk-sized)
        if !seenEADDRINUSE && chunk.contains("EADDRINUSE") {
            seenEADDRINUSE = true
        }

        // Parse new lines and add to ring buffer
        let lines = chunk.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            parseLine(line)

            // Add to ring buffer with proactive trimming
            logLines.append(line)
            if logLines.count > maxBufferLines {
                logLines.removeFirst(logLines.count - maxBufferLines)
            }
        }

        // Rebuild logs string from ring buffer (only when publishing)
        logs = logLines.joined(separator: "\n")
    }

    // Start the service
    func start() {
        if isRunning { return }

        logs = ""
        logLines = []
        errors = []
        warnings = []
        lineNumber = 0
        logBuffer = ""
        seenEADDRINUSE = false
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

            // Live log streaming — append to buffer only; timer flushes to UI at 100ms intervals
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let data = handle.availableData
                guard data.count > 0, let output = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.logBuffer += output
                }
            }

            // Start the flush timer on main queue
            await MainActor.run { self.startFlushTimer() }

            // Termination handler
            process.terminationHandler = { [weak self] proc in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.stopFlushTimer()
                    self.logBuffer += "\n[Process terminated with code \(proc.terminationStatus)]\n"
                    self.flushLogBuffer()
                    if self.seenEADDRINUSE {
                        self.detectPortConflict()
                    }
                    // If a check command or port is configured, re-check true state
                    // (handles fire-and-forget launchers like `open -a Docker`)
                    if self.config.checkCommand != nil || self.config.port != nil {
                        Task { await self.checkStatus() }
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

    // Check if port is in use — runs async off main thread
    func checkPort(_ port: Int) {
        Task.detached(priority: .userInitiated) {
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
                    await MainActor.run {
                        if !trimmed.isEmpty {
                            let pids = trimmed.components(separatedBy: .newlines)
                            if let firstPID = pids.first, let pid = Int(firstPID) {
                                self.hasPortConflict = true
                                self.conflictingPID = pid
                                self.logs += "[Port Check] Port \(port) is in use by PID \(pid)\n"
                            }
                        } else {
                            self.hasPortConflict = false
                            self.conflictingPID = nil
                            self.logs += "[Port Check] Port \(port) is free\n"
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.logs += "[Port Check] Failed to check port \(port): \(error.localizedDescription)\n"
                }
            }
        }
    }

    // Detect port conflict from error logs
    func detectPortConflict() {
        guard let port = config.port else { return }
        checkPort(port)
    }

    // Check if service is running (via checkCommand or port fallback)
    // Async function that runs blocking work off main thread
    func checkStatus() async {
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
        stopFlushTimer()
        pipe?.fileHandleForReading.readabilityHandler = nil
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
