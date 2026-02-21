//
//  AddServiceView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct AddServiceView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: ServiceManager

    @State private var name = ""
    @State private var command = ""
    @State private var workingDirectory = NSHomeDirectory()
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
