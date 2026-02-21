//
//  EditTunnelView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-22.
//

import SwiftUI

struct EditTunnelView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: InstanceGroupManager
    let group: InstanceGroup
    let instance: EC2Instance
    let tunnel: SSHTunnel

    @State private var editedTunnel: SSHTunnel
    @State private var isValid = true

    init(manager: InstanceGroupManager, group: InstanceGroup, instance: EC2Instance, tunnel: SSHTunnel) {
        self.manager = manager
        self.group = group
        self.instance = instance
        self.tunnel = tunnel
        _editedTunnel = State(initialValue: tunnel)
    }

    var body: some View {
        NavigationStack {
            TunnelForm(tunnel: $editedTunnel, isValid: $isValid)
                .navigationTitle("Edit Tunnel")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveTunnel() }
                            .disabled(!isValid)
                    }
                }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func saveTunnel() {
        // Find group and instance indices
        guard let groupIndex = manager.groups.firstIndex(where: { $0.id == group.id }),
              let instanceIndex = manager.groups[groupIndex].instances.firstIndex(where: { $0.id == instance.id }),
              let tunnelIndex = manager.groups[groupIndex].instances[instanceIndex].tunnels.firstIndex(where: { $0.id == tunnel.id }) else {
            return
        }

        // Update tunnel
        manager.groups[groupIndex].instances[instanceIndex].tunnels[tunnelIndex] = editedTunnel
        manager.saveGroups()

        dismiss()
    }
}
