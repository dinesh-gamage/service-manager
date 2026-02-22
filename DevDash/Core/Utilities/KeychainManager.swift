//
//  KeychainManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation
import Security
import LocalAuthentication

enum KeychainError: Error, LocalizedError {
    case duplicateItem
    case itemNotFound
    case invalidData
    case unexpectedStatus(OSStatus)
    case unableToEncode
    case unableToDecode

    var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "Item already exists in keychain"
        case .itemNotFound:
            return "Item not found in keychain"
        case .invalidData:
            return "Invalid data format"
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .unableToEncode:
            return "Unable to encode data"
        case .unableToDecode:
            return "Unable to decode data"
        }
    }
}

class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.devdash.credentials"

    private init() {}

    // MARK: - Save

    /// Save a string value to keychain
    func save(_ value: String, for key: String, context: LAContext? = nil) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unableToEncode
        }

        try save(data, for: key, context: context)
    }

    /// Save data to keychain
    func save(_ data: Data, for key: String, context: LAContext? = nil) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Pass LAContext if available for authenticated operations
        // This allows biometric-authenticated sessions to access keychain without prompts
        if let context = context {
            query[kSecUseAuthenticationContext as String] = context
        }

        // Try to add the item
        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item exists, update it
            try update(data, for: key, context: context)
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Retrieve

    /// Retrieve a string value from keychain
    func retrieve(_ key: String, context: LAContext? = nil) throws -> String {
        let data = try retrieveData(key, context: context)

        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unableToDecode
        }

        return value
    }

    /// Retrieve data from keychain
    func retrieveData(_ key: String, context: LAContext? = nil) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Pass authenticated context to prevent password prompts
        // This tells Security framework to use the already-authenticated session
        if let context = context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    // MARK: - Update

    /// Update an existing keychain item
    private func update(_ data: Data, for key: String, context: LAContext? = nil) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        var attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Pass LAContext if available for authenticated operations
        if let context = context {
            attributes[kSecUseAuthenticationContext as String] = context
        }

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Delete

    /// Delete an item from keychain
    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Delete all items for this service
    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Existence Check

    /// Check if an item exists in keychain
    func exists(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
