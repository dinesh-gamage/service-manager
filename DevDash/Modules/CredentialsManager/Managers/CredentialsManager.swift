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

@MainActor
class CredentialsManager: ObservableObject {
    @Published private(set) var credentials: [Credential] = []
    @Published private(set) var isLoading = false

    private let keychainManager = KeychainManager.shared
    private weak var alertQueue: AlertQueue?
    private weak var toastQueue: ToastQueue?

    init(alertQueue: AlertQueue? = nil, toastQueue: ToastQueue? = nil) {
        self.alertQueue = alertQueue
        self.toastQueue = toastQueue
        loadCredentials()
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

        // Save password to Keychain
        try keychainManager.save(password, for: passwordKey)

        // Save access token to Keychain if provided
        var accessTokenKey: String?
        if let accessToken = accessToken, !accessToken.isEmpty {
            let key = Credential.accessTokenKeychainKey(for: credentialId)
            try keychainManager.save(accessToken, for: key)
            accessTokenKey = key
        }

        // Save recovery codes to Keychain if provided
        var recoveryCodesKey: String?
        if let recoveryCodes = recoveryCodes, !recoveryCodes.isEmpty {
            let key = Credential.recoveryCodesKeychainKey(for: credentialId)
            try keychainManager.save(recoveryCodes, for: key)
            recoveryCodesKey = key
        }

        // Save secret fields to Keychain
        for field in additionalFields where field.isSecret {
            try keychainManager.save(field.value, for: field.keychainKey)
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
            try keychainManager.save(password, for: credential.passwordKeychainKey)
        }

        // Update access token in Keychain if provided
        var accessTokenKey = credential.accessTokenKeychainKey
        if let accessToken = accessToken, !accessToken.isEmpty {
            let key = credential.accessTokenKeychainKey ?? Credential.accessTokenKeychainKey(for: credential.id)
            try keychainManager.save(accessToken, for: key)
            accessTokenKey = key
        }

        // Update recovery codes in Keychain if provided
        var recoveryCodesKey = credential.recoveryCodesKeychainKey
        if let recoveryCodes = recoveryCodes, !recoveryCodes.isEmpty {
            let key = credential.recoveryCodesKeychainKey ?? Credential.recoveryCodesKeychainKey(for: credential.id)
            try keychainManager.save(recoveryCodes, for: key)
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
            try keychainManager.save(field.value, for: keychainKey)
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
        try keychainManager.retrieve(credential.passwordKeychainKey)
    }

    func getAccessToken(for credential: Credential) throws -> String? {
        guard let key = credential.accessTokenKeychainKey else {
            return nil
        }
        return try? keychainManager.retrieve(key)
    }

    func getRecoveryCodes(for credential: Credential) throws -> String? {
        guard let key = credential.recoveryCodesKeychainKey else {
            return nil
        }
        return try? keychainManager.retrieve(key)
    }

    func getFieldValue(for field: CredentialField) throws -> String {
        if field.isSecret {
            return try keychainManager.retrieve(field.value) // field.value is the keychain key
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
        let panel = NSSavePanel()
        panel.title = "Export Credentials"
        panel.nameFieldStringValue = "credentials-\(Date().timeIntervalSince1970).json"
        panel.allowedContentTypes = [.json]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                // Export metadata only (no passwords or secret fields)
                let exportData = self.credentials.map { credential -> [String: Any] in
                    return [
                        "id": credential.id.uuidString,
                        "title": credential.title,
                        "category": credential.category,
                        "username": credential.username as Any,
                        "additionalFields": credential.additionalFields.filter { !$0.isSecret }.map { field in
                            ["key": field.key, "value": field.value]
                        },
                        "notes": credential.notes as Any,
                        "createdAt": credential.createdAt.timeIntervalSince1970,
                        "lastModified": credential.lastModified.timeIntervalSince1970
                    ]
                }

                let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted])
                try jsonData.write(to: url)

                self.toastQueue?.enqueue(message: "Credentials exported (passwords not included)")
            } catch {
                self.alertQueue?.enqueue(title: "Export Failed", message: error.localizedDescription)
            }
        }
    }

    func importCredentials() {
        let panel = NSOpenPanel()
        panel.title = "Import Credentials"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                self.isLoading = true

                do {
                    let data = try Data(contentsOf: url)
                    let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

                    var newCount = 0
                    var updatedCount = 0

                    for item in jsonArray {
                        guard let title = item["title"] as? String,
                              let category = item["category"] as? String else {
                            continue
                        }

                        let username = item["username"] as? String
                        let url = item["url"] as? String
                        let notes = item["notes"] as? String
                        let fieldsData = item["additionalFields"] as? [[String: Any]] ?? []

                        let fields = fieldsData.compactMap { fieldData -> CredentialField? in
                            guard let key = fieldData["key"] as? String else { return nil }
                            return CredentialField(
                                key: key,
                                value: fieldData["value"] as? String ?? "",
                                isSecret: fieldData["isSecret"] as? Bool ?? false
                            )
                        }

                        // Check if credential with same title exists
                        if let index = self.credentials.firstIndex(where: { $0.title == title }) {
                            // Replace existing credential
                            let existingCredential = self.credentials[index]

                            var updatedCredential = existingCredential
                            updatedCredential.title = title
                            updatedCredential.category = category
                            updatedCredential.url = url
                            updatedCredential.username = username
                            updatedCredential.additionalFields = fields
                            updatedCredential.notes = notes
                            updatedCredential.lastModified = Date()

                            self.credentials[index] = updatedCredential
                            updatedCount += 1
                        } else {
                            // Create new credential with empty password (user must set it manually)
                            let credentialId = UUID()
                            let passwordKey = Credential.passwordKeychainKey(for: credentialId)

                            // Save empty password to keychain
                            try? self.keychainManager.save("", for: passwordKey)

                            let credential = Credential(
                                id: credentialId,
                                title: title,
                                category: category,
                                url: url,
                                username: username,
                                passwordKeychainKey: passwordKey,
                                accessTokenKeychainKey: nil,
                                recoveryCodesKeychainKey: nil,
                                additionalFields: fields,
                                notes: notes
                            )

                            self.credentials.append(credential)
                            newCount += 1
                        }
                    }

                    self.saveCredentials()
                    self.isLoading = false

                    // Show success toast
                    let message: String
                    if newCount > 0 && updatedCount > 0 {
                        message = "Imported \(newCount) new, updated \(updatedCount) existing (set passwords manually)"
                    } else if newCount > 0 {
                        message = "Imported \(newCount) new credential\(newCount == 1 ? "" : "s") (set passwords manually)"
                    } else if updatedCount > 0 {
                        message = "Updated \(updatedCount) credential\(updatedCount == 1 ? "" : "s") (set passwords manually)"
                    } else {
                        message = "No credentials imported"
                    }
                    self.toastQueue?.enqueue(message: message)
                } catch {
                    self.isLoading = false
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
}
