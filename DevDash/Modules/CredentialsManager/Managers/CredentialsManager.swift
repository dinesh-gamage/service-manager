//
//  CredentialsManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine
import LocalAuthentication

// MARK: - Import Models

struct ImportCredential: Codable {
    let id: String?
    let title: String
    let category: String
    let username: String?
    let url: String?
    let password: String?
    let accessToken: String?
    let recoveryCodes: String?
    let additionalFields: [ImportCredentialField]?
    let notes: String?
    let createdAt: Double?
    let lastModified: Double?

    // Custom decoding to handle both ISO 8601 strings and Unix timestamps
    enum CodingKeys: String, CodingKey {
        case id, title, category, username, url, password, accessToken, recoveryCodes, additionalFields, notes, createdAt, lastModified
    }

    // Memberwise initializer
    init(id: String?, title: String, category: String, username: String?, url: String?, password: String?, accessToken: String?, recoveryCodes: String?, additionalFields: [ImportCredentialField]?, notes: String?, createdAt: Double?, lastModified: Double?) {
        self.id = id
        self.title = title
        self.category = category
        self.username = username
        self.url = url
        self.password = password
        self.accessToken = accessToken
        self.recoveryCodes = recoveryCodes
        self.additionalFields = additionalFields
        self.notes = notes
        self.createdAt = createdAt
        self.lastModified = lastModified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        password = try container.decodeIfPresent(String.self, forKey: .password)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        recoveryCodes = try container.decodeIfPresent(String.self, forKey: .recoveryCodes)
        additionalFields = try container.decodeIfPresent([ImportCredentialField].self, forKey: .additionalFields)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)

        // Handle both ISO 8601 strings and Unix timestamps
        if let timestampDouble = try? container.decodeIfPresent(Double.self, forKey: .createdAt) {
            createdAt = timestampDouble
        } else if let timestampString = try? container.decodeIfPresent(String.self, forKey: .createdAt) {
            // Parse ISO 8601 date string
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: timestampString) {
                createdAt = date.timeIntervalSince1970
            } else {
                createdAt = nil
            }
        } else {
            createdAt = nil
        }

        if let timestampDouble = try? container.decodeIfPresent(Double.self, forKey: .lastModified) {
            lastModified = timestampDouble
        } else if let timestampString = try? container.decodeIfPresent(String.self, forKey: .lastModified) {
            // Parse ISO 8601 date string
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: timestampString) {
                lastModified = date.timeIntervalSince1970
            } else {
                lastModified = nil
            }
        } else {
            lastModified = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(password, forKey: .password)
        try container.encodeIfPresent(accessToken, forKey: .accessToken)
        try container.encodeIfPresent(recoveryCodes, forKey: .recoveryCodes)
        try container.encodeIfPresent(additionalFields, forKey: .additionalFields)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
    }
}

struct ImportCredentialField: Codable {
    let key: String
    let value: String
    let isSecret: Bool
}

@MainActor
class CredentialsManager: ObservableObject {
    @Published private(set) var credentials: [Credential] = []
    @Published private(set) var isLoading = false

    private let keychainManager = KeychainManager.shared
    private let authManager = BiometricAuthManager.shared
    private weak var alertQueue: AlertQueue?
    private weak var toastQueue: ToastQueue?

    init(alertQueue: AlertQueue? = nil, toastQueue: ToastQueue? = nil) {
        self.alertQueue = alertQueue
        self.toastQueue = toastQueue
        loadCredentials()
    }

    /// Get the authenticated context for keychain operations
    private var authContext: LAContext? {
        authManager.getAuthenticatedContext()
    }

    // MARK: - Load/Save

    func loadCredentials() {
        credentials = StorageManager.shared.load(forKey: "credentials") ?? []
    }

    private func saveCredentials() {
        StorageManager.shared.save(credentials, forKey: "credentials")
    }

    // MARK: - CRUD Operations

    func addCredential(
        title: String,
        category: String,
        url: String?,
        username: String?,
        password: String,
        accessToken: String?,
        recoveryCodes: String?,
        additionalFields: [CredentialField],
        notes: String?
    ) throws {
        let credentialId = UUID()
        let passwordKey = Credential.passwordKeychainKey(for: credentialId)

        // Save password to Keychain with authenticated context
        try keychainManager.save(password, for: passwordKey, context: authContext)

        // Save access token to Keychain if provided
        var accessTokenKey: String?
        if let accessToken = accessToken, !accessToken.isEmpty {
            let key = Credential.accessTokenKeychainKey(for: credentialId)
            try keychainManager.save(accessToken, for: key, context: authContext)
            accessTokenKey = key
        }

        // Save recovery codes to Keychain if provided
        var recoveryCodesKey: String?
        if let recoveryCodes = recoveryCodes, !recoveryCodes.isEmpty {
            let key = Credential.recoveryCodesKeychainKey(for: credentialId)
            try keychainManager.save(recoveryCodes, for: key, context: authContext)
            recoveryCodesKey = key
        }

        // Save secret fields to Keychain
        for field in additionalFields where field.isSecret {
            try keychainManager.save(field.value, for: field.keychainKey, context: authContext)
        }

        // Create credential with keychain references
        let credential = Credential(
            id: credentialId,
            title: title,
            category: category,
            url: url,
            username: username,
            passwordKeychainKey: passwordKey,
            accessTokenKeychainKey: accessTokenKey,
            recoveryCodesKeychainKey: recoveryCodesKey,
            additionalFields: additionalFields.map { field in
                if field.isSecret {
                    // Store keychain key instead of actual value
                    return CredentialField(
                        id: field.id,
                        key: field.key,
                        value: field.keychainKey,
                        isSecret: true
                    )
                }
                return field
            },
            notes: notes
        )

        credentials.append(credential)
        saveCredentials()
        toastQueue?.enqueue(message: "'\(title)' added")
    }

    func updateCredential(
        _ credential: Credential,
        title: String,
        category: String,
        url: String?,
        username: String?,
        password: String?,
        accessToken: String?,
        recoveryCodes: String?,
        additionalFields: [CredentialField],
        notes: String?
    ) throws {
        guard let index = credentials.firstIndex(where: { $0.id == credential.id }) else {
            throw NSError(domain: "CredentialsManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Credential not found"])
        }

        // Update password in Keychain if provided
        if let password = password, !password.isEmpty {
            try keychainManager.save(password, for: credential.passwordKeychainKey, context: authContext)
        }

        // Update access token in Keychain if provided
        var accessTokenKey = credential.accessTokenKeychainKey
        if let accessToken = accessToken, !accessToken.isEmpty {
            let key = credential.accessTokenKeychainKey ?? Credential.accessTokenKeychainKey(for: credential.id)
            try keychainManager.save(accessToken, for: key, context: authContext)
            accessTokenKey = key
        }

        // Update recovery codes in Keychain if provided
        var recoveryCodesKey = credential.recoveryCodesKeychainKey
        if let recoveryCodes = recoveryCodes, !recoveryCodes.isEmpty {
            let key = credential.recoveryCodesKeychainKey ?? Credential.recoveryCodesKeychainKey(for: credential.id)
            try keychainManager.save(recoveryCodes, for: key, context: authContext)
            recoveryCodesKey = key
        }

        // Handle additional fields
        let oldFields = credential.additionalFields
        let newFields = additionalFields

        // Delete removed secret fields from Keychain
        for oldField in oldFields where oldField.isSecret {
            if !newFields.contains(where: { $0.id == oldField.id }) {
                try? keychainManager.delete(oldField.value) // oldField.value is the keychain key
            }
        }

        // Update/add secret fields in Keychain
        for field in newFields where field.isSecret {
            let keychainKey = field.keychainKey
            try keychainManager.save(field.value, for: keychainKey, context: authContext)
        }

        // Update credential
        var updatedCredential = credential
        updatedCredential.title = title
        updatedCredential.category = category
        updatedCredential.url = url
        updatedCredential.username = username
        updatedCredential.accessTokenKeychainKey = accessTokenKey
        updatedCredential.recoveryCodesKeychainKey = recoveryCodesKey
        updatedCredential.additionalFields = newFields.map { field in
            if field.isSecret {
                return CredentialField(
                    id: field.id,
                    key: field.key,
                    value: field.keychainKey,
                    isSecret: true
                )
            }
            return field
        }
        updatedCredential.notes = notes
        updatedCredential.lastModified = Date()

        credentials[index] = updatedCredential
        saveCredentials()
        toastQueue?.enqueue(message: "'\(title)' updated")
    }

    func deleteCredential(at offsets: IndexSet) {
        for index in offsets {
            let credential = credentials[index]

            // Delete password from Keychain
            try? keychainManager.delete(credential.passwordKeychainKey)

            // Delete access token from Keychain if exists
            if let accessTokenKey = credential.accessTokenKeychainKey {
                try? keychainManager.delete(accessTokenKey)
            }

            // Delete recovery codes from Keychain if exists
            if let recoveryCodesKey = credential.recoveryCodesKeychainKey {
                try? keychainManager.delete(recoveryCodesKey)
            }

            // Delete secret fields from Keychain
            for field in credential.additionalFields where field.isSecret {
                try? keychainManager.delete(field.value) // field.value is the keychain key
            }
        }

        credentials.remove(atOffsets: offsets)
        saveCredentials()
    }

    func deleteCredential(_ credential: Credential) {
        if let index = credentials.firstIndex(where: { $0.id == credential.id }) {
            deleteCredential(at: IndexSet(integer: index))
        }
    }

    // MARK: - Retrieve Secrets

    func getPassword(for credential: Credential) throws -> String {
        try keychainManager.retrieve(credential.passwordKeychainKey, context: authContext)
    }

    func getAccessToken(for credential: Credential) throws -> String? {
        guard let key = credential.accessTokenKeychainKey else {
            return nil
        }
        return try? keychainManager.retrieve(key, context: authContext)
    }

    func getRecoveryCodes(for credential: Credential) throws -> String? {
        guard let key = credential.recoveryCodesKeychainKey else {
            return nil
        }
        return try? keychainManager.retrieve(key, context: authContext)
    }

    func getFieldValue(for field: CredentialField) throws -> String {
        if field.isSecret {
            return try keychainManager.retrieve(field.value, context: authContext) // field.value is the keychain key
        }
        return field.value
    }

    // MARK: - Safe Retrieval (Non-Throwing)

    func getPasswordSafe(for credential: Credential) -> String? {
        try? keychainManager.retrieve(credential.passwordKeychainKey, context: authContext)
    }

    func getAccessTokenSafe(for credential: Credential) -> String? {
        guard let key = credential.accessTokenKeychainKey else { return nil }
        return try? keychainManager.retrieve(key, context: authContext)
    }

    func getRecoveryCodesSafe(for credential: Credential) -> String? {
        guard let key = credential.recoveryCodesKeychainKey else { return nil }
        return try? keychainManager.retrieve(key, context: authContext)
    }

    func getFieldValueSafe(for field: CredentialField) -> String? {
        if field.isSecret {
            return try? keychainManager.retrieve(field.value, context: authContext)
        }
        return field.value
    }

    // MARK: - Search/Filter

    func filteredCredentials(searchText: String, category: String?) -> [Credential] {
        var filtered = credentials

        // Filter by category
        if let category = category, category != "All" {
            filtered = filtered.filter { $0.category == category }
        }

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { credential in
                credential.title.localizedCaseInsensitiveContains(searchText) ||
                credential.category.localizedCaseInsensitiveContains(searchText) ||
                (credential.username?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (credential.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return filtered
    }

    // MARK: - Import/Export

    func exportCredentials() {
        Task {
            do {
                // Require biometric auth before export
                try await BiometricAuthManager.shared.authenticate(reason: "Authenticate to export credentials")

                // Export with all secrets from Keychain using Codable format
                let exportData = self.credentials.map { credential -> ImportCredential in
                    // Retrieve password from Keychain
                    let password = try? self.keychainManager.retrieve(credential.passwordKeychainKey, context: self.authContext)

                    // Retrieve access token if exists
                    var accessToken: String?
                    if let accessTokenKey = credential.accessTokenKeychainKey {
                        accessToken = try? self.keychainManager.retrieve(accessTokenKey, context: self.authContext)
                    }

                    // Retrieve recovery codes if exists
                    var recoveryCodes: String?
                    if let recoveryCodesKey = credential.recoveryCodesKeychainKey {
                        recoveryCodes = try? self.keychainManager.retrieve(recoveryCodesKey, context: self.authContext)
                    }

                    // Include all fields (including secret ones from Keychain)
                    let fields = credential.additionalFields.map { field -> ImportCredentialField in
                        let value: String
                        if field.isSecret {
                            // Retrieve secret value from Keychain
                            value = (try? self.keychainManager.retrieve(field.keychainKey, context: self.authContext)) ?? ""
                        } else {
                            value = field.value
                        }
                        return ImportCredentialField(
                            key: field.key,
                            value: value,
                            isSecret: field.isSecret
                        )
                    }

                    return ImportCredential(
                        id: credential.id.uuidString,
                        title: credential.title,
                        category: credential.category,
                        username: credential.username,
                        url: credential.url,
                        password: password,
                        accessToken: accessToken,
                        recoveryCodes: recoveryCodes,
                        additionalFields: fields.isEmpty ? nil : fields,
                        notes: credential.notes,
                        createdAt: credential.createdAt.timeIntervalSince1970,
                        lastModified: credential.lastModified.timeIntervalSince1970
                    )
                }

                // Use ImportExportManager for consistent file dialogs and JSON handling
                ImportExportManager.shared.exportJSON(
                    exportData,
                    defaultFileName: "credentials-\(Date().timeIntervalSince1970).json",
                    title: "Export Credentials"
                ) { [weak self] result in
                    switch result {
                    case .success:
                        self?.toastQueue?.enqueue(message: "Credentials exported with all secrets")
                    case .failure(let error):
                        if case .userCancelled = error {
                            return
                        }
                        self?.alertQueue?.enqueue(title: "Export Failed", message: error.localizedDescription)
                    }
                }
            } catch {
                await MainActor.run {
                    self.alertQueue?.enqueue(title: "Authentication Required", message: "You must authenticate to export credentials")
                }
            }
        }
    }

    func importCredentials() {
        ImportExportManager.shared.importJSON(ImportCredential.self, title: "Import Credentials") { result in
            Task { @MainActor in
                switch result {
                case .success(let importedCredentials):
                    self.isLoading = true

                    var newCount = 0
                    var updatedCount = 0

                    for importItem in importedCredentials {
                        do {
                            // Check if credential with same title exists (trim whitespace)
                            let trimmedTitle = importItem.title.trimmingCharacters(in: .whitespaces)
                            if let index = self.credentials.firstIndex(where: {
                                $0.title.trimmingCharacters(in: .whitespaces) == trimmedTitle
                            }) {
                                // Update existing credential
                                let existingCredential = self.credentials[index]

                                // Update password if provided
                                if let password = importItem.password, !password.isEmpty {
                                    try self.keychainManager.save(password, for: existingCredential.passwordKeychainKey, context: self.authContext)
                                }

                                // Update access token if provided
                                var accessTokenKey = existingCredential.accessTokenKeychainKey
                                if let accessToken = importItem.accessToken, !accessToken.isEmpty {
                                    let key = existingCredential.accessTokenKeychainKey ?? Credential.accessTokenKeychainKey(for: existingCredential.id)
                                    try self.keychainManager.save(accessToken, for: key, context: self.authContext)
                                    accessTokenKey = key
                                }

                                // Update recovery codes if provided
                                var recoveryCodesKey = existingCredential.recoveryCodesKeychainKey
                                if let recoveryCodes = importItem.recoveryCodes, !recoveryCodes.isEmpty {
                                    let key = existingCredential.recoveryCodesKeychainKey ?? Credential.recoveryCodesKeychainKey(for: existingCredential.id)
                                    try self.keychainManager.save(recoveryCodes, for: key, context: self.authContext)
                                    recoveryCodesKey = key
                                }

                                // Update additional fields
                                let fields = (importItem.additionalFields ?? []).map { importField in
                                    CredentialField(
                                        key: importField.key,
                                        value: importField.value,
                                        isSecret: importField.isSecret
                                    )
                                }

                                // Save secret fields to keychain
                                for field in fields where field.isSecret {
                                    try self.keychainManager.save(field.value, for: field.keychainKey, context: self.authContext)
                                }

                                // Update credential
                                var updatedCredential = existingCredential
                                updatedCredential.title = importItem.title
                                updatedCredential.category = importItem.category
                                updatedCredential.url = importItem.url
                                updatedCredential.username = importItem.username
                                updatedCredential.accessTokenKeychainKey = accessTokenKey
                                updatedCredential.recoveryCodesKeychainKey = recoveryCodesKey
                                updatedCredential.additionalFields = fields.map { field in
                                    if field.isSecret {
                                        return CredentialField(
                                            id: field.id,
                                            key: field.key,
                                            value: field.keychainKey,
                                            isSecret: true
                                        )
                                    }
                                    return field
                                }
                                updatedCredential.notes = importItem.notes
                                updatedCredential.lastModified = Date()

                                self.credentials[index] = updatedCredential
                                updatedCount += 1
                            } else {
                                // Create new credential
                                let credentialId = UUID()
                                let passwordKey = Credential.passwordKeychainKey(for: credentialId)

                                // Save password to keychain with authenticated context
                                let password = importItem.password ?? ""
                                try self.keychainManager.save(password, for: passwordKey, context: self.authContext)

                                // Save access token if provided
                                var accessTokenKey: String?
                                if let accessToken = importItem.accessToken, !accessToken.isEmpty {
                                    let key = Credential.accessTokenKeychainKey(for: credentialId)
                                    try self.keychainManager.save(accessToken, for: key, context: self.authContext)
                                    accessTokenKey = key
                                }

                                // Save recovery codes if provided
                                var recoveryCodesKey: String?
                                if let recoveryCodes = importItem.recoveryCodes, !recoveryCodes.isEmpty {
                                    let key = Credential.recoveryCodesKeychainKey(for: credentialId)
                                    try self.keychainManager.save(recoveryCodes, for: key, context: self.authContext)
                                    recoveryCodesKey = key
                                }

                                // Process additional fields
                                let fields = (importItem.additionalFields ?? []).map { importField in
                                    CredentialField(
                                        key: importField.key,
                                        value: importField.value,
                                        isSecret: importField.isSecret
                                    )
                                }

                                // Save secret fields to keychain
                                for field in fields where field.isSecret {
                                    try self.keychainManager.save(field.value, for: field.keychainKey, context: self.authContext)
                                }

                                // Create credential
                                let credential = Credential(
                                    id: credentialId,
                                    title: importItem.title,
                                    category: importItem.category,
                                    url: importItem.url,
                                    username: importItem.username,
                                    passwordKeychainKey: passwordKey,
                                    accessTokenKeychainKey: accessTokenKey,
                                    recoveryCodesKeychainKey: recoveryCodesKey,
                                    additionalFields: fields.map { field in
                                        if field.isSecret {
                                            return CredentialField(
                                                id: field.id,
                                                key: field.key,
                                                value: field.keychainKey,
                                                isSecret: true
                                            )
                                        }
                                        return field
                                    },
                                    notes: importItem.notes
                                )

                                self.credentials.append(credential)
                                newCount += 1
                            }
                        } catch {
                            // Log error but continue with other credentials
                            print("Failed to import credential '\(importItem.title)': \(error.localizedDescription)")
                        }
                    }

                    self.saveCredentials()
                    self.isLoading = false

                    // Show success toast
                    let message: String
                    if newCount > 0 && updatedCount > 0 {
                        message = "Imported \(newCount) new, updated \(updatedCount) existing"
                    } else if newCount > 0 {
                        message = "Imported \(newCount) new credential\(newCount == 1 ? "" : "s")"
                    } else if updatedCount > 0 {
                        message = "Updated \(updatedCount) credential\(updatedCount == 1 ? "" : "s")"
                    } else {
                        message = "No credentials imported"
                    }
                    self.toastQueue?.enqueue(message: message)

                case .failure(let error):
                    self.isLoading = false

                    // Only show error alerts, not cancellation
                    if case .userCancelled = error {
                        return
                    }
                    self.alertQueue?.enqueue(title: "Import Failed", message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        // Remove orphaned keychain entries
        for credential in credentials {
            if !keychainManager.exists(credential.passwordKeychainKey) {
                // Password missing in keychain, might need attention
            }

            for field in credential.additionalFields where field.isSecret {
                if !keychainManager.exists(field.value) {
                    // Field value missing in keychain
                }
            }
        }
    }

    // MARK: - Clear All

    /// Delete all credentials and their keychain entries
    func clearAll() {
        // Delete all keychain entries
        for credential in credentials {
            // Delete password
            try? keychainManager.delete(credential.passwordKeychainKey)

            // Delete access token if exists
            if let accessTokenKey = credential.accessTokenKeychainKey {
                try? keychainManager.delete(accessTokenKey)
            }

            // Delete recovery codes if exists
            if let recoveryCodesKey = credential.recoveryCodesKeychainKey {
                try? keychainManager.delete(recoveryCodesKey)
            }

            // Delete secret fields
            for field in credential.additionalFields where field.isSecret {
                try? keychainManager.delete(field.value)
            }
        }

        // Clear credentials array
        credentials = []
        saveCredentials()

        toastQueue?.enqueue(message: "All credentials cleared")
    }
}
