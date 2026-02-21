//
//  TunnelRuntime.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-22.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class TunnelRuntime: ObservableObject, Identifiable {

    let tunnel: SSHTunnel
    let bastionIP: String
    let sshConfig: SSHConfig

    @Published var isConnected: Bool = false
    @Published var logs: String = ""
    @Published var connectionError: String?

    private var process: Process?
    private var pipe: Pipe?

    // Log batching
    private var logBuffer = ""
    private var flushTimer: DispatchSourceTimer?

    var id: UUID { tunnel.id }

    init(tunnel: SSHTunnel, bastionIP: String, sshConfig: SSHConfig) {
        self.tunnel = tunnel
        self.bastionIP = bastionIP
        self.sshConfig = sshConfig
    }

    deinit {
        // Clean up resources
        flushTimer?.cancel()
        flushTimer = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
    }

    // MARK: - Tunnel Control

    func start() {
        guard !isConnected else { return }

        // Validate SSH key exists
        let expandedKeyPath = NSString(string: sshConfig.keyPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedKeyPath) else {
            connectionError = "SSH key not found: \(expandedKeyPath)"
            return
        }

        // Clear previous state
        logs = ""
        logBuffer = ""
        connectionError = nil

        // Build SSH tunnel command
        // ssh -L localPort:remoteHost:remotePort -N -i keyPath username@bastionIP customOptions
        var command = "ssh -L \(tunnel.localPort):\(tunnel.remoteHost):\(tunnel.remotePort) -N"
        command += " -i \"\(expandedKeyPath)\""
        command += " \(sshConfig.username)@\(bastionIP)"

        if !sshConfig.customOptions.isEmpty {
            command += " \(sshConfig.customOptions)"
        }

        appendLog("[Tunnel] Starting \(tunnel.name)")
        appendLog("[Command] \(command)")
        appendLog("[Local Port] 127.0.0.1:\(tunnel.localPort)")
        appendLog("[Remote] \(tunnel.remoteHost):\(tunnel.remotePort)")
        appendLog("[Bastion] \(bastionIP)")
        appendLog("")

        // Create process
        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        newProcess.arguments = ["-c", command]
        newProcess.environment = ProcessEnvironment.shared.getEnvironment()

        let newPipe = Pipe()
        newProcess.standardOutput = newPipe
        newProcess.standardError = newPipe

        // Set up log streaming
        newPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self.logBuffer += output
                }
            }
        }

        // Set up flush timer (flush logs every 100ms)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.flushLogs()
        }
        timer.resume()

        self.flushTimer = timer
        self.process = newProcess
        self.pipe = newPipe

        // Start process
        do {
            try newProcess.run()
            isConnected = true
            appendLog("[Status] Tunnel started")

            // Monitor process termination
            newProcess.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isConnected = false

                    let exitCode = process.terminationStatus
                    if exitCode != 0 {
                        self.appendLog("[Error] Tunnel terminated with exit code \(exitCode)")
                        self.connectionError = "SSH tunnel failed (exit code: \(exitCode))"
                    } else {
                        self.appendLog("[Status] Tunnel stopped")
                    }

                    self.cleanup()
                }
            }
        } catch {
            isConnected = false
            connectionError = "Failed to start tunnel: \(error.localizedDescription)"
            appendLog("[Error] \(error.localizedDescription)")
            cleanup()
        }
    }

    func stop() {
        guard isConnected else { return }

        appendLog("[Status] Stopping tunnel...")
        isConnected = false

        process?.terminate()
        cleanup()
    }

    // MARK: - Log Management

    private func flushLogs() {
        guard !logBuffer.isEmpty else { return }

        logs += logBuffer
        logBuffer = ""

        // Trim logs if too large (keep last 10,000 characters)
        if logs.count > 10000 {
            let start = logs.index(logs.endIndex, offsetBy: -10000)
            logs = String(logs[start...])
        }
    }

    private func appendLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        logBuffer += "[\(timestamp)] \(message)\n"
        flushLogs()
    }

    private func cleanup() {
        flushTimer?.cancel()
        flushTimer = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
        process = nil
    }
}
