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

    init(manager: InstanceGroupManager, group: InstanceGroup, instance: EC2Instance) {
        self.manager = manager
        self.group = group
        self.instance = instance
        _name = State(initialValue: instance.name)
        _instanceId = State(initialValue: instance.instanceId)
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
        .frame(minWidth: 500, minHeight: 350)
    }

    private func saveInstance() {
        let updatedInstance = EC2Instance(
            id: instance.id,
            name: name,
            instanceId: instanceId,
            lastKnownIP: instance.lastKnownIP,
            lastFetched: instance.lastFetched
        )
        manager.updateInstanceData(groupId: group.id, instanceId: instance.id, newInstance: updatedInstance)
        dismiss()
    }
}
