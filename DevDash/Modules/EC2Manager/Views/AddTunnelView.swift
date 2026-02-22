//
//  AddTunnelView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-22.
//

import SwiftUI

struct AddTunnelView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: InstanceGroupManager
    let group: InstanceGroup

    // Initialize with a placeholder UUID that will be replaced
    @State private var tunnel: SSHTunnel
    @State private var isValid = false

    init(manager: InstanceGroupManager, group: InstanceGroup) {
        self.manager = manager
        self.group = group

        // Initialize with first instance if available, otherwise use placeholder
        let firstInstanceId = group.instances.first?.id ?? UUID()
        _tunnel = State(initialValue: SSHTunnel(
            name: "",
            localPort: 10000,
            remoteHost: "",
            remotePort: 27017,
            bastionInstanceId: firstInstanceId
        ))
    }

    var body: some View {
        NavigationStack {
            TunnelForm(tunnel: $tunnel, isValid: $isValid, instances: group.instances)
                .navigationTitle("Add Tunnel")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { addTunnel() }
                            .disabled(!isValid)
                    }
                }
        }
        .frame(minWidth: 500, minHeight: 450)
    }

    private func addTunnel() {
        manager.addTunnel(groupId: group.id, tunnel: tunnel)
        dismiss()
    }
}
