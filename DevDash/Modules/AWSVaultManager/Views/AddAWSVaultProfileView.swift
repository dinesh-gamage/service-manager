//
//  AddAWSVaultProfileView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct AddAWSVaultProfileView: View {
    let manager: AWSVaultManager

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var alertQueue = AlertQueue()

    @State private var name = ""
    @State private var region = ""
    @State private var description = ""
    @State private var accessKeyId = ""
    @State private var secretAccessKey = ""

    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add AWS Vault Profile")
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

                    Text("AWS Credentials")
                        .font(AppTheme.h3)
                        .foregroundColor(.secondary)

                    Text("These credentials will be stored securely in aws-vault")
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

                Button("Add Profile") {
                    saveProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 600, height: 550)
        .alertQueue(alertQueue)
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var isValid: Bool {
        !name.isEmpty && !accessKeyId.isEmpty && !secretAccessKey.isEmpty
    }

    private func saveProfile() {
        Task {
            let profile = AWSVaultProfile(
                name: name,
                region: region.isEmpty ? nil : region,
                description: description.isEmpty ? nil : description
            )

            await manager.addProfile(profile, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)
            dismiss()
        }
    }
}
