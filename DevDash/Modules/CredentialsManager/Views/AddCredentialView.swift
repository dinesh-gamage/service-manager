//
//  AddCredentialView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct AddCredentialView: View {
    let manager: CredentialsManager

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var alertQueue = AlertQueue()

    @State private var title = ""
    @State private var category = CredentialCategory.other
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var accessToken = ""
    @State private var recoveryCodes = ""
    @State private var additionalFields: [CredentialFieldInput] = []
    @State private var notes = ""

    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Credential")
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
                    FormField(label: "Password") {
                        SecureField("Enter password", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Access Token
                    FormField(label: "Access Token") {
                        SecureField("Optional access token", text: $accessToken)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Recovery Codes
                    FormField(label: "Recovery Codes") {
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
                    if recoveryCodes.isEmpty {
                        Text("Enter one code per line (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
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

                Button("Add Credential") {
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
    }

    private var isValid: Bool {
        !title.isEmpty && !password.isEmpty
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

            try manager.addCredential(
                title: title,
                category: category,
                url: url.isEmpty ? nil : url,
                username: username.isEmpty ? nil : username,
                password: password,
                accessToken: accessToken.isEmpty ? nil : accessToken,
                recoveryCodes: recoveryCodes.isEmpty ? nil : recoveryCodes,
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

// MARK: - Credential Field Input

struct CredentialFieldInput {
    var key: String
    var value: String
    var isSecret: Bool
}

// MARK: - Additional Field Input Row

struct AdditionalFieldInput: View {
    @Binding var field: CredentialFieldInput
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Field name", text: $field.key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                if field.isSecret {
                    SecureField("Value", text: $field.value)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("Value", text: $field.value)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Secret", isOn: $field.isSecret)
                    .toggleStyle(.switch)
                    .help("Toggle to encrypt this field")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Remove field")
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
