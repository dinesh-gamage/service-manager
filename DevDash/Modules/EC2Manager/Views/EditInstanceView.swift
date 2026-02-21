//
//  EditInstanceView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct EditInstanceView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: InstanceGroupManager
    let group: InstanceGroup
    let instance: EC2Instance

    @State private var name: String
    @State private var instanceId: String
    @State private var sshConfig: SSHConfig?
    @State private var showingAddTunnel = false
    @State private var showingEditTunnel = false
    @State private var tunnelToEdit: SSHTunnel?
    @State private var tunnelToDelete: SSHTunnel?
    @State private var showingDeleteTunnelConfirmation = false

    // Computed property to get current instance from manager
    private var currentInstance: EC2Instance? {
        guard let groupIndex = manager.groups.firstIndex(where: { $0.id == group.id }),
              let instanceIndex = manager.groups[groupIndex].instances.firstIndex(where: { $0.id == instance.id }) else {
            return nil
        }
        return manager.groups[groupIndex].instances[instanceIndex]
    }

    init(manager: InstanceGroupManager, group: InstanceGroup, instance: EC2Instance) {
        self.manager = manager
        self.group = group
        self.instance = instance
        _name = State(initialValue: instance.name)
        _instanceId = State(initialValue: instance.instanceId)
        _sshConfig = State(initialValue: instance.sshConfig)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Instance Details") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    TextField("Instance ID (e.g., i-0123456789abcdef0)", text: $instanceId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Section("Cached Data") {
                    if let ip = instance.lastKnownIP {
                        HStack {
                            Text("Last Known IP:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(ip)
                                .font(.system(.body, design: .monospaced))
                        }
                    }

                    if let date = instance.lastFetched {
                        HStack {
                            Text("Last Fetched:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(date, style: .relative)
                        }
                    }
                }

                Section("SSH Configuration") {
                    SSHConfigForm(
                        config: $sshConfig,
                        showInheritedHint: true,
                        inheritedConfig: group.sshConfig
                    )
                }

                Section("SSH Tunnels") {
                    if currentInstance?.tunnels.isEmpty ?? true {
                        Text("No tunnels configured")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else if let tunnels = currentInstance?.tunnels {
                        List {
                            ForEach(tunnels) { tunnel in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tunnel.name)
                                            .font(.body)

                                        Text("127.0.0.1:\(tunnel.localPort) → \(tunnel.remoteHost):\(tunnel.remotePort)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    HStack(spacing: 6) {
                                        VariantButton(icon: "pencil", variant: .secondary, tooltip: "Edit") {
                                            tunnelToEdit = tunnel
                                            showingEditTunnel = true
                                        }

                                        VariantButton(icon: "trash", variant: .danger, tooltip: "Delete") {
                                            tunnelToDelete = tunnel
                                            showingDeleteTunnelConfirmation = true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    VariantButton("Add Tunnel", icon: "plus", variant: .primary) {
                        showingAddTunnel = true
                    }
                }

                Section {
                    Text("Editing instance in '\(group.name)' group.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit EC2 Instance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveInstance() }
                        .disabled(name.isEmpty || instanceId.isEmpty)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 550)
        .sheet(isPresented: $showingAddTunnel) {
            AddTunnelView(manager: manager, group: group, instance: instance)
        }
        .sheet(isPresented: $showingEditTunnel) {
            if let tunnel = tunnelToEdit {
                EditTunnelView(manager: manager, group: group, instance: instance, tunnel: tunnel)
            }
        }
        .alert("Delete Tunnel", isPresented: $showingDeleteTunnelConfirmation) {
            Button("Cancel", role: .cancel) {
                tunnelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let tunnel = tunnelToDelete {
                    deleteTunnel(tunnel)
                    tunnelToDelete = nil
                }
            }
        } message: {
            if let tunnel = tunnelToDelete {
                Text("Are you sure you want to delete the tunnel '\(tunnel.name)'?")
            }
        }
    }

    private func saveInstance() {
        let updatedInstance = EC2Instance(
            id: instance.id,
            name: name,
            instanceId: instanceId,
            lastKnownIP: instance.lastKnownIP,
            lastFetched: instance.lastFetched,
            fetchError: instance.fetchError,
            sshConfig: sshConfig,
            tunnels: currentInstance?.tunnels ?? []
        )
        manager.updateInstanceData(groupId: group.id, instanceId: instance.id, newInstance: updatedInstance)
        dismiss()
    }

    private func deleteTunnel(_ tunnel: SSHTunnel) {
        guard let groupIndex = manager.groups.firstIndex(where: { $0.id == group.id }),
              let instanceIndex = manager.groups[groupIndex].instances.firstIndex(where: { $0.id == instance.id }),
              let tunnelIndex = manager.groups[groupIndex].instances[instanceIndex].tunnels.firstIndex(where: { $0.id == tunnel.id }) else {
            return
        }

        // Stop tunnel if running
        manager.stopTunnel(tunnelId: tunnel.id)

        // Remove tunnel
        manager.groups[groupIndex].instances[instanceIndex].tunnels.remove(at: tunnelIndex)
        manager.saveGroups()
    }
}
