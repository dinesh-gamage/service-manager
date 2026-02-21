//
//  CredentialDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct CredentialDetailView: View {
    let credential: Credential

    @ObservedObject private var state = CredentialsManagerState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with metadata
                ModuleDetailHeader(
                    title: credential.title,
                    metadata: [
                        MetadataRow(icon: "folder.fill", label: "Category", value: credential.category),
                        MetadataRow(icon: "calendar", label: "Created", value: credential.createdAt.formatted(date: .abbreviated, time: .shortened)),
                        MetadataRow(icon: "clock", label: "Modified", value: credential.lastModified.formatted(date: .abbreviated, time: .shortened))
                    ],
                    actionButtons: {
                        HStack(spacing: 12) {
                            VariantButton("Edit", icon: "pencil", variant: .primary) {
                                state.credentialToEdit = credential
                                state.showingEditCredential = true
                            }
                        }
                    }
                )

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    // Username
                    if let username = credential.username {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Username", systemImage: "person.fill")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            HStack {
                                InlineCopyableText(username)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }

                    // URL/Server
                    if let url = credential.url {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("URL/Server", systemImage: "link")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            HStack {
                                InlineCopyableText(url)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    // Password
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Password", systemImage: "lock.fill")
                            .font(AppTheme.h3)
                            .foregroundColor(.secondary)

                        HStack {
                            if let revealed = state.revealedPasswords[credential.id] {
                                Text(revealed)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            } else {
                                Text("••••••••••••")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                VariantButton(
                                    icon: state.revealedPasswords[credential.id] != nil ? "eye.slash" : "eye",
                                    variant: .secondary,
                                    tooltip: state.revealedPasswords[credential.id] != nil ? "Hide password" : "Reveal password"
                                ) {
                                    Task {
                                        if state.revealedPasswords[credential.id] != nil {
                                            state.hidePassword(for: credential)
                                        } else {
                                            await state.revealPassword(for: credential)
                                        }
                                    }
                                }

                                VariantButton(icon: "doc.on.doc", variant: .secondary, tooltip: "Copy password") {
                                    Task {
                                        do {
                                            let password = try state.manager.getPassword(for: credential)
                                            await state.copyToClipboard(password, fieldName: "Password")
                                        } catch {
                                            state.alertQueue.enqueue(title: "Error", message: error.localizedDescription)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    // Access Token
                    if credential.accessTokenKeychainKey != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Access Token", systemImage: "key.horizontal.fill")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            HStack {
                                if let revealed = state.revealedAccessTokens[credential.id] {
                                    Text(revealed)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                } else {
                                    Text("••••••••••••")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    VariantButton(
                                        icon: state.revealedAccessTokens[credential.id] != nil ? "eye.slash" : "eye",
                                        variant: .secondary,
                                        tooltip: state.revealedAccessTokens[credential.id] != nil ? "Hide access token" : "Reveal access token"
                                    ) {
                                        Task {
                                            if state.revealedAccessTokens[credential.id] != nil {
                                                state.hideAccessToken(for: credential)
                                            } else {
                                                await state.revealAccessToken(for: credential)
                                            }
                                        }
                                    }

                                    VariantButton(icon: "doc.on.doc", variant: .secondary, tooltip: "Copy access token") {
                                        Task {
                                            do {
                                                if let accessToken = try state.manager.getAccessToken(for: credential) {
                                                    await state.copyToClipboard(accessToken, fieldName: "Access Token")
                                                }
                                            } catch {
                                                state.alertQueue.enqueue(title: "Error", message: error.localizedDescription)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }

                    // Recovery Codes
                    if credential.recoveryCodesKeychainKey != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Recovery Codes", systemImage: "shield.lefthalf.filled")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            HStack(alignment: .top) {
                                if let revealed = state.revealedRecoveryCodes[credential.id] {
                                    Text(revealed)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text("••••••••••••")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(spacing: 8) {
                                    VariantButton(
                                        icon: state.revealedRecoveryCodes[credential.id] != nil ? "eye.slash" : "eye",
                                        variant: .secondary,
                                        tooltip: state.revealedRecoveryCodes[credential.id] != nil ? "Hide recovery codes" : "Reveal recovery codes"
                                    ) {
                                        Task {
                                            if state.revealedRecoveryCodes[credential.id] != nil {
                                                state.hideRecoveryCodes(for: credential)
                                            } else {
                                                await state.revealRecoveryCodes(for: credential)
                                            }
                                        }
                                    }

                                    VariantButton(icon: "doc.on.doc", variant: .secondary, tooltip: "Copy recovery codes") {
                                        Task {
                                            do {
                                                if let recoveryCodes = try state.manager.getRecoveryCodes(for: credential) {
                                                    await state.copyToClipboard(recoveryCodes, fieldName: "Recovery Codes")
                                                }
                                            } catch {
                                                state.alertQueue.enqueue(title: "Error", message: error.localizedDescription)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }

                    // Additional Fields
                    if !credential.additionalFields.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Additional Fields", systemImage: "list.bullet")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            ForEach(credential.additionalFields) { field in
                                CredentialFieldRow(field: field)
                            }
                        }
                    }

                    // Notes
                    if let notes = credential.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Notes", systemImage: "note.text")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            Text(notes)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case CredentialCategory.databases: return "cylinder.fill"
        case CredentialCategory.apiKeys: return "network"
        case CredentialCategory.ssh: return "terminal.fill"
        case CredentialCategory.websites: return "globe"
        case CredentialCategory.servers: return "server.rack"
        case CredentialCategory.applications: return "app.fill"
        default: return "key.fill"
        }
    }
}

// MARK: - Credential Field Row

struct CredentialFieldRow: View {
    let field: CredentialField

    @ObservedObject private var state = CredentialsManagerState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.key)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                if field.isSecret {
                    if let revealed = state.revealedFields[field.id] {
                        Text(revealed)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("••••••••••••")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(field.value)
                        .font(.body)
                        .textSelection(.enabled)
                }

                Spacer()

                HStack(spacing: 8) {
                    if field.isSecret {
                        VariantButton(
                            icon: state.revealedFields[field.id] != nil ? "eye.slash" : "eye",
                            variant: .secondary,
                            tooltip: state.revealedFields[field.id] != nil ? "Hide value" : "Reveal value"
                        ) {
                            Task {
                                if state.revealedFields[field.id] != nil {
                                    state.hideField(field)
                                } else {
                                    await state.revealField(field)
                                }
                            }
                        }
                    }

                    VariantButton(icon: "doc.on.doc", variant: .secondary, tooltip: "Copy \(field.key)") {
                        Task {
                            do {
                                let value = try state.manager.getFieldValue(for: field)
                                await state.copyToClipboard(value, fieldName: field.key)
                            } catch {
                                state.alertQueue.enqueue(title: "Error", message: error.localizedDescription)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}
