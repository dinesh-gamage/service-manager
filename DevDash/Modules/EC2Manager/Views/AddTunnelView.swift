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
    let instance: EC2Instance

    @State private var tunnel = SSHTunnel(name: "", localPort: 10000, remoteHost: "", remotePort: 27017)
    @State private var isValid = false

    var body: some View {
        NavigationStack {
            TunnelForm(tunnel: $tunnel, isValid: $isValid)
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
        .frame(minWidth: 500, minHeight: 400)
    }

    private func addTunnel() {
        // Find group and instance indices
        guard let groupIndex = manager.groups.firstIndex(where: { $0.id == group.id }),
              let instanceIndex = manager.groups[groupIndex].instances.firstIndex(where: { $0.id == instance.id }) else {
            return
        }

        // Add tunnel to instance
        manager.groups[groupIndex].instances[instanceIndex].tunnels.append(tunnel)
        manager.saveGroups()

        dismiss()
    }
}
