//
//  TunnelForm.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-22.
//

import SwiftUI

struct TunnelForm: View {
    @Binding var tunnel: SSHTunnel
    @Binding var isValid: Bool

    @State private var name: String
    @State private var localPort: String
    @State private var remoteHost: String
    @State private var remotePort: String

    init(tunnel: Binding<SSHTunnel>, isValid: Binding<Bool>) {
        self._tunnel = tunnel
        self._isValid = isValid

        let t = tunnel.wrappedValue
        _name = State(initialValue: t.name)
        _localPort = State(initialValue: String(t.localPort))
        _remoteHost = State(initialValue: t.remoteHost)
        _remotePort = State(initialValue: String(t.remotePort))
    }

    var body: some View {
        Form {
            Section("Tunnel Details") {
                FormField(label: "Name") {
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: name) { _, _ in updateTunnel() }
                }

                FormField(label: "Local Port") {
                    TextField("", text: $localPort)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: localPort) { _, _ in updateTunnel() }
                }

                FormField(label: "Remote Host") {
                    TextField("", text: $remoteHost)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: remoteHost) { _, _ in updateTunnel() }
                }

                FormField(label: "Remote Port") {
                    TextField("", text: $remotePort)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: remotePort) { _, _ in updateTunnel() }
                }
            }

            Section {
                Text("The tunnel will forward connections from 127.0.0.1:\(localPort.isEmpty ? "LOCAL_PORT" : localPort) to \(remoteHost.isEmpty ? "REMOTE_HOST" : remoteHost):\(remotePort.isEmpty ? "REMOTE_PORT" : remotePort) through the instance.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !validationMessage.isEmpty {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var validationMessage: String {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Name is required"
        }

        guard let local = Int(localPort), local >= 1, local <= 65535 else {
            return "Local port must be between 1 and 65535"
        }

        if remoteHost.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Remote host is required"
        }

        guard let remote = Int(remotePort), remote >= 1, remote <= 65535 else {
            return "Remote port must be between 1 and 65535"
        }

        return ""
    }

    private func updateTunnel() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedHost = remoteHost.trimmingCharacters(in: .whitespaces)
        let local = Int(localPort) ?? 0
        let remote = Int(remotePort) ?? 0

        let valid = !trimmedName.isEmpty &&
                    local >= 1 && local <= 65535 &&
                    !trimmedHost.isEmpty &&
                    remote >= 1 && remote <= 65535

        isValid = valid

        if valid {
            tunnel = SSHTunnel(
                id: tunnel.id,
                name: trimmedName,
                localPort: local,
                remoteHost: trimmedHost,
                remotePort: remote
            )
        }
    }
}
