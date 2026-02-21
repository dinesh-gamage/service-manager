//
//  EditAWSVaultProfileView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct EditAWSVaultProfileView: View {
    let manager: AWSVaultManager
    let profile: AWSVaultProfile

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var alertQueue = AlertQueue()

    @State private var name = ""
    @State private var region = ""
    @State private var description = ""
    @State private var updateCredentials = false
    @State private var accessKeyId = ""
    @State private var secretAccessKey = ""

    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit AWS Vault Profile")
                    .font(AppTheme.h2)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Profile Name
                    FormField(label: "Profile Name") {
                        TextField("e.g., lucy-production", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Region
                    FormField(label: "Default Region") {
                        TextField("e.g., ap-southeast-1", text: $region)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Description
                    FormField(label: "Description") {
                        TextField("Optional notes about this profile", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    // Update Credentials Toggle
                    Toggle("Update AWS Credentials", isOn: $updateCredentials)
                        .toggleStyle(.switch)

                    if updateCredentials {
                        Text("New credentials will be stored securely in aws-vault")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Access Key ID
                        FormField(label: "Access Key ID") {
                            TextField("AKIA...", text: $accessKeyId)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Secret Access Key
                        FormField(label: "Secret Access Key") {
                            SecureField("Secret access key", text: $secretAccessKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save Changes") {
                    saveProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 600, height: 600)
        .alertQueue(alertQueue)
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadProfile()
        }
    }

    private var isValid: Bool {
        if updateCredentials {
            return !name.isEmpty && !accessKeyId.isEmpty && !secretAccessKey.isEmpty
        }
        return !name.isEmpty
    }

    private func loadProfile() {
        name = profile.name
        region = profile.region ?? ""
        description = profile.description ?? ""
    }

    private func saveProfile() {
        Task {
            var updatedProfile = profile
            updatedProfile.name = name
            updatedProfile.region = region.isEmpty ? nil : region
            updatedProfile.description = description.isEmpty ? nil : description

            if updateCredentials {
                await manager.updateProfile(updatedProfile, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)
            } else {
                await manager.updateProfile(updatedProfile, accessKeyId: nil, secretAccessKey: nil)
            }

            dismiss()
        }
    }
}
