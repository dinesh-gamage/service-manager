//
//  SSHConfigForm.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-22.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SSHConfigForm: View {
    @Binding var config: SSHConfig?
    var showInheritedHint: Bool = false
    var inheritedConfig: SSHConfig?

    @State private var isEnabled: Bool
    @State private var username: String
    @State private var keyPath: String
    @State private var customOptions: String

    init(config: Binding<SSHConfig?>, showInheritedHint: Bool = false, inheritedConfig: SSHConfig? = nil) {
        self._config = config
        self.showInheritedHint = showInheritedHint
        self.inheritedConfig = inheritedConfig

        // Initialize state from binding
        let initialConfig = config.wrappedValue ?? SSHConfig()
        _isEnabled = State(initialValue: config.wrappedValue != nil)
        _username = State(initialValue: initialConfig.username)
        _keyPath = State(initialValue: initialConfig.keyPath)
        _customOptions = State(initialValue: initialConfig.customOptions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showInheritedHint {
                Toggle("Use custom SSH configuration", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        if newValue {
                            config = SSHConfig(username: username, keyPath: keyPath, customOptions: customOptions)
                        } else {
                            config = nil
                        }
                    }

                if !isEnabled, let inherited = inheritedConfig {
                    Text("Inheriting from group: \(inherited.username)@... (key: \(inherited.keyPath))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if !isEnabled {
                    Text("No group SSH configuration set")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if isEnabled || !showInheritedHint {
                VStack(alignment: .leading, spacing: 8) {
                    FormField(label: "Username") {
                        TextField("ubuntu", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: username) { _, newValue in
                                updateConfig()
                            }
                    }

                    FormField(label: "SSH Key Path") {
                        HStack(spacing: 8) {
                            TextField("~/.ssh/id_rsa", text: $keyPath)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: keyPath) { _, newValue in
                                    updateConfig()
                                }

                            Button("Browse...") {
                                selectKeyFile()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    FormField(label: "Custom Options") {
                        TextField("Additional SSH flags (optional)", text: $customOptions)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: customOptions) { _, newValue in
                                updateConfig()
                            }
                    }

                    Text("Example: ~/.ssh/lucysaas.pem")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func updateConfig() {
        config = SSHConfig(username: username, keyPath: keyPath, customOptions: customOptions)
    }

    private func selectKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select SSH Private Key"
        panel.allowedContentTypes = [.item]

        // Start in ~/.ssh if it exists
        let sshDir = NSString(string: "~/.ssh").expandingTildeInPath
        if FileManager.default.fileExists(atPath: sshDir) {
            panel.directoryURL = URL(fileURLWithPath: sshDir)
        }

        if panel.runModal() == .OK, let url = panel.url {
            // Convert to tilde path if in home directory
            let path = url.path
            let homePath = NSString(string: "~").expandingTildeInPath
            if path.hasPrefix(homePath) {
                keyPath = "~" + path.dropFirst(homePath.count)
            } else {
                keyPath = path
            }
            updateConfig()
        }
    }
}
