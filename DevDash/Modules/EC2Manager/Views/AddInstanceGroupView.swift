//
//  AddInstanceGroupView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct AddInstanceGroupView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: InstanceGroupManager
    @ObservedObject var awsVaultState = AWSVaultManagerState.shared

    @State private var name = ""
    @State private var region = ""
    @State private var awsProfile = ""

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

                Section {
                    Text("You can add instances to this group after creating it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Instance Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addGroup() }
                        .disabled(name.isEmpty || region.isEmpty || awsProfile.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    private func addGroup() {
        let group = InstanceGroup(
            name: name,
            region: region,
            awsProfile: awsProfile,
            instances: []
        )
        manager.addGroup(group)
        dismiss()
    }
}
