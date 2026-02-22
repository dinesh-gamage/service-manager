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
    let tunnel: SSHTunnel

    @State private var editedTunnel: SSHTunnel
    @State private var isValid = true

    init(manager: InstanceGroupManager, group: InstanceGroup, tunnel: SSHTunnel) {
        self.manager = manager
        self.group = group
        self.tunnel = tunnel
        _editedTunnel = State(initialValue: tunnel)
    }

    var body: some View {
        NavigationStack {
            TunnelForm(tunnel: $editedTunnel, isValid: $isValid, instances: group.instances)
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
        .frame(minWidth: 500, minHeight: 450)
    }

    private func saveTunnel() {
        manager.updateTunnel(groupId: group.id, tunnelId: tunnel.id, newTunnel: editedTunnel)
        dismiss()
    }
}
