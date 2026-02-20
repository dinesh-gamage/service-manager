//
//  AddInstanceView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct AddInstanceView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: InstanceGroupManager
    let group: InstanceGroup

    @State private var name = ""
    @State private var instanceId = ""

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

                Section {
                    Text("This instance will be added to the '\(group.name)' group.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add EC2 Instance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addInstance() }
                        .disabled(name.isEmpty || instanceId.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 250)
    }

    private func addInstance() {
        let instance = EC2Instance(
            name: name,
            instanceId: instanceId
        )
        manager.addInstance(groupId: group.id, instance: instance)
        dismiss()
    }
}
