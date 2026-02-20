//
//  EditServiceView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

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
