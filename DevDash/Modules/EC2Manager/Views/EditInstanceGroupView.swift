//
//  EditInstanceGroupView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct EditInstanceGroupView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: InstanceGroupManager
    @ObservedObject var awsVaultState = AWSVaultManagerState.shared
    let group: InstanceGroup

    @State private var name: String
    @State private var region: String
    @State private var awsProfile: String
    @State private var sshConfig: SSHConfig?

    init(manager: InstanceGroupManager, group: InstanceGroup) {
        self.manager = manager
        self.group = group
        _name = State(initialValue: group.name)
        _region = State(initialValue: group.region)
        _awsProfile = State(initialValue: group.awsProfile)
        _sshConfig = State(initialValue: group.sshConfig)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Details") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    TextField("AWS Region (e.g., ap-southeast-1)", text: $region)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 4) {
                        Picker("AWS Profile", selection: $awsProfile) {
                            Text("Select a profile").tag("")
                            ForEach(awsVaultState.manager.getProfileNames(), id: \.self) { profileName in
                                Text(profileName).tag(profileName)
                            }
                        }
                        .pickerStyle(.menu)

                        if awsVaultState.manager.getProfileNames().isEmpty {
                            Text("No profiles found. Add profiles in AWS Vault Manager.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Section("SSH Configuration") {
                    SSHConfigForm(config: $sshConfig)

                    Text("This SSH configuration will be inherited by all instances in this group unless overridden.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Text("Group contains \(group.instances.count) instance(s).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Instance Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveGroup() }
                        .disabled(name.isEmpty || region.isEmpty || awsProfile.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    private func saveGroup() {
        let updatedGroup = InstanceGroup(
            id: group.id,
            name: name,
            region: region,
            awsProfile: awsProfile,
            instances: group.instances,
            sshConfig: sshConfig
        )
        manager.updateGroup(groupId: group.id, newGroup: updatedGroup)
        dismiss()
    }
}
