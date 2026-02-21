//
//  EditCredentialView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct EditCredentialView: View {
    let manager: CredentialsManager
    let credential: Credential

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var alertQueue = AlertQueue()

    @State private var title = ""
    @State private var category = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var changePassword = false
    @State private var accessToken = ""
    @State private var changeAccessToken = false
    @State private var recoveryCodes = ""
    @State private var changeRecoveryCodes = false
    @State private var additionalFields: [CredentialFieldInput] = []
    @State private var notes = ""

    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Credential")
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
                    // Title
                    FormField(label: "Title") {
                        TextField("e.g., Production Database", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Category
                    FormField(label: "Category") {
                        Picker("Category", selection: $category) {
                            ForEach(CredentialCategory.all, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        .labelsHidden()
                    }

                    // URL/Server
                    FormField(label: "URL/Server") {
                        TextField("https://example.com", text: $url)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Username
                    FormField(label: "Username") {
                        TextField("username@example.com", text: $username)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Password
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Change Password", isOn: $changePassword)
                            .toggleStyle(.switch)

                        if changePassword {
                            FormField(label: "New Password") {
                                SecureField("Enter new password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    // Access Token
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Change Access Token", isOn: $changeAccessToken)
                            .toggleStyle(.switch)

                        if changeAccessToken {
                            FormField(label: "New Access Token") {
                                SecureField("Enter new access token", text: $accessToken)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    // Recovery Codes
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Change Recovery Codes", isOn: $changeRecoveryCodes)
                            .toggleStyle(.switch)

                        if changeRecoveryCodes {
                            FormField(label: "New Recovery Codes") {
                                TextEditor(text: $recoveryCodes)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 80)
                                    .padding(4)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                    )
                            }
                            Text("Enter one code per line")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Additional Fields
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Additional Fields")
                                .font(AppTheme.h3)

                            Spacer()

                            Button(action: addField) {
                                Label("Add Field", systemImage: "plus.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }

                        ForEach(additionalFields.indices, id: \.self) { index in
                            AdditionalFieldInput(
                                field: $additionalFields[index],
                                onDelete: { removeField(at: index) }
                            )
                        }
                    }

                    // Notes
                    FormField(label: "Notes") {
                        TextEditor(text: $notes)
                            .font(.body)
                            .frame(height: 80)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            )
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
                    saveCredential()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 600, height: 700)
        .alertQueue(alertQueue)
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadCredential()
        }
    }

    private var isValid: Bool {
        if changePassword {
            return !title.isEmpty && !password.isEmpty
        }
        return !title.isEmpty
    }

    private func loadCredential() {
        title = credential.title
        category = credential.category
        url = credential.url ?? ""
        username = credential.username ?? ""
        notes = credential.notes ?? ""

        // Load additional fields (decrypt secrets for editing)
        additionalFields = credential.additionalFields.map { field in
            var value = field.value
            if field.isSecret {
                // Retrieve actual value from keychain
                if let decrypted = try? manager.getFieldValue(for: field) {
                    value = decrypted
                }
            }
            return CredentialFieldInput(key: field.key, value: value, isSecret: field.isSecret)
        }
    }

    private func addField() {
        additionalFields.append(CredentialFieldInput(key: "", value: "", isSecret: false))
    }

    private func removeField(at index: Int) {
        additionalFields.remove(at: index)
    }

    private func saveCredential() {
        do {
            let fields = additionalFields.map { input in
                CredentialField(
                    key: input.key,
                    value: input.value,
                    isSecret: input.isSecret
                )
            }

            try manager.updateCredential(
                credential,
                title: title,
                category: category,
                url: url.isEmpty ? nil : url,
                username: username.isEmpty ? nil : username,
                password: changePassword ? password : nil,
                accessToken: changeAccessToken ? accessToken : nil,
                recoveryCodes: changeRecoveryCodes ? recoveryCodes : nil,
                additionalFields: fields,
                notes: notes.isEmpty ? nil : notes
            )

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
