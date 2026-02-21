//
//  CredentialModels.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation

// MARK: - Credential Field

struct CredentialField: Identifiable, Codable, Equatable {
    let id: UUID
    var key: String
    var value: String           // Plain text value OR keychain key if isSecret
    var isSecret: Bool

    init(id: UUID = UUID(), key: String, value: String, isSecret: Bool) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
    }

    /// Get the keychain key for this field
    var keychainKey: String {
        "field-\(id.uuidString)"
    }
}

// MARK: - Credential

struct Credential: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var category: String
    var url: String?                        // Service URL/Server address
    var username: String?
    var passwordKeychainKey: String         // Key to retrieve password from Keychain
    var accessTokenKeychainKey: String?     // Key to retrieve access token from Keychain
    var recoveryCodesKeychainKey: String?   // Key to retrieve recovery codes from Keychain
    var additionalFields: [CredentialField]
    var notes: String?
    let createdAt: Date
    var lastModified: Date

    init(
        id: UUID = UUID(),
        title: String,
        category: String,
        url: String? = nil,
        username: String? = nil,
        passwordKeychainKey: String,
        accessTokenKeychainKey: String? = nil,
        recoveryCodesKeychainKey: String? = nil,
        additionalFields: [CredentialField] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.url = url
        self.username = username
        self.passwordKeychainKey = passwordKeychainKey
        self.accessTokenKeychainKey = accessTokenKeychainKey
        self.recoveryCodesKeychainKey = recoveryCodesKeychainKey
        self.additionalFields = additionalFields
        self.notes = notes
        self.createdAt = Date()
        self.lastModified = Date()
    }

    /// Get the keychain key for password
    static func passwordKeychainKey(for credentialId: UUID) -> String {
        "credential-password-\(credentialId.uuidString)"
    }

    /// Get the keychain key for access token
    static func accessTokenKeychainKey(for credentialId: UUID) -> String {
        "credential-accesstoken-\(credentialId.uuidString)"
    }

    /// Get the keychain key for recovery codes
    static func recoveryCodesKeychainKey(for credentialId: UUID) -> String {
        "credential-recoverycodes-\(credentialId.uuidString)"
    }
}

// MARK: - Credential Category

struct CredentialCategory {
    static let databases = "Databases"
    static let apiKeys = "API Keys"
    static let ssh = "SSH"
    static let websites = "Websites"
    static let servers = "Servers"
    static let applications = "Applications"
    static let other = "Other"

    static let all = [
        databases,
        apiKeys,
        ssh,
        websites,
        servers,
        applications,
        other
    ]
}
