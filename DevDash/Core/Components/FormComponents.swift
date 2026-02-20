//
//  FormComponents.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

// MARK: - Environment Variable Model

struct EnvVar: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

// MARK: - Service Form Content

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

// MARK: - Form Helpers

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
