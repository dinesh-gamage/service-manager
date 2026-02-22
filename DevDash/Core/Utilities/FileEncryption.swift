//
//  FileEncryption.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation
import CryptoKit
import CommonCrypto
import LocalAuthentication

enum FileEncryptionError: Error, LocalizedError {
    case passphraseNotSet
    case encryptionFailed
    case decryptionFailed
    case invalidData
    case keychainError(OSStatus)
    case weakPassphrase

    var errorDescription: String? {
        switch self {
        case .passphraseNotSet:
            return "Encryption passphrase not set. Please configure backup settings first."
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data. Please check your passphrase."
        case .invalidData:
            return "Invalid encrypted data format"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .weakPassphrase:
            return "Passphrase must be at least 8 characters"
        }
    }
}

/// Handles AES-256-GCM encryption/decryption for backup files
class FileEncryption {
    static let shared = FileEncryption()

    private let keychainManager = KeychainManager.shared
    private let passphraseKey = "backup-encryption-passphrase"

    // Legacy keychain keys (before KeychainManager refactoring)
    private let legacyKeychainService = "com.devdash.backup"
    private let legacyKeychainAccount = "encryption-master-key"

    private init() {
        migrateLegacyPassphrase()
    }

    // MARK: - Migration

    /// Migrate passphrase from legacy keychain location to KeychainManager
    private func migrateLegacyPassphrase() {
        // Check if already using new location
        if keychainManager.exists(passphraseKey) {
            return
        }

        // Try to load from legacy location
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
            kSecAttrAccount as String: legacyKeychainAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let passphrase = String(data: data, encoding: .utf8) else {
            return
        }

        // Migrate to new location
        try? keychainManager.save(passphrase, for: passphraseKey)

        // Delete from old location
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
            kSecAttrAccount as String: legacyKeychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }

    // MARK: - Passphrase Management

    /// Save passphrase to Keychain
    func savePassphrase(_ passphrase: String, context: LAContext? = nil) throws {
        guard passphrase.count >= 8 else {
            throw FileEncryptionError.weakPassphrase
        }

        // Delete existing passphrase if any
        try? keychainManager.delete(passphraseKey)

        // Save new passphrase using KeychainManager with authenticated context
        try keychainManager.save(passphrase, for: passphraseKey, context: context)
    }

    /// Load passphrase from Keychain
    private func loadPassphrase(context: LAContext? = nil) throws -> String {
        do {
            return try keychainManager.retrieve(passphraseKey, context: context)
        } catch KeychainError.itemNotFound {
            throw FileEncryptionError.passphraseNotSet
        } catch {
            throw FileEncryptionError.invalidData
        }
    }

    /// Derive encryption key from passphrase using PBKDF2
    private func deriveKey(from passphrase: String, salt: Data) -> SymmetricKey {
        let passphraseData = passphrase.data(using: .utf8)!
        let derivedKey = PBKDF2.deriveKey(
            from: passphraseData,
            salt: salt,
            iterations: 100_000,
            keyLength: 32  // 256 bits
        )
        return SymmetricKey(data: derivedKey)
    }

    /// Check if passphrase is set
    /// Uses exists() to avoid retrieving data, preventing keychain password prompts
    func hasPassphrase() -> Bool {
        return keychainManager.exists(passphraseKey)
    }

    // MARK: - Encryption/Decryption

    /// Encrypt data using AES-256-GCM with passphrase
    /// - Parameters:
    ///   - data: Plain data to encrypt
    ///   - context: Authenticated LAContext to prevent keychain password prompts
    /// - Returns: Encrypted data (16 bytes salt + encrypted content with nonce/tag)
    func encrypt(_ data: Data, context: LAContext? = nil) throws -> Data {
        let passphrase = try loadPassphrase(context: context)

        // Generate random salt
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }

        // Derive key from passphrase + salt
        let key = deriveKey(from: passphrase, salt: salt)

        // Encrypt with AES-GCM
        guard let sealedBox = try? AES.GCM.seal(data, using: key) else {
            throw FileEncryptionError.encryptionFailed
        }

        guard let combined = sealedBox.combined else {
            throw FileEncryptionError.encryptionFailed
        }

        // Return: salt + encrypted data
        return salt + combined
    }

    /// Decrypt data using AES-256-GCM with passphrase
    /// - Parameters:
    ///   - encryptedData: Encrypted data (salt + encrypted content)
    ///   - context: Authenticated LAContext to prevent keychain password prompts
    /// - Returns: Decrypted plain data
    func decrypt(_ encryptedData: Data, context: LAContext? = nil) throws -> Data {
        let passphrase = try loadPassphrase(context: context)

        // Extract salt (first 16 bytes)
        guard encryptedData.count > 16 else {
            throw FileEncryptionError.invalidData
        }

        let salt = encryptedData.prefix(16)
        let ciphertext = encryptedData.suffix(from: 16)

        // Derive key from passphrase + salt
        let key = deriveKey(from: passphrase, salt: Data(salt))

        // Decrypt with AES-GCM
        guard let sealedBox = try? AES.GCM.SealedBox(combined: ciphertext) else {
            throw FileEncryptionError.invalidData
        }

        guard let decrypted = try? AES.GCM.open(sealedBox, using: key) else {
            throw FileEncryptionError.decryptionFailed
        }

        return decrypted
    }

    // MARK: - Convenience Methods

    /// Encrypt JSON-encodable object
    func encryptJSON<T: Encodable>(_ object: T, context: LAContext? = nil) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData = try encoder.encode(object)
        return try encrypt(jsonData, context: context)
    }

    /// Decrypt to JSON-decodable object
    func decryptJSON<T: Decodable>(_ encryptedData: Data, as type: T.Type, context: LAContext? = nil) throws -> T {
        let decryptedData = try decrypt(encryptedData, context: context)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: decryptedData)
    }

    // MARK: - Passphrase Reset

    /// Delete passphrase from Keychain
    func deletePassphrase() {
        try? keychainManager.delete(passphraseKey)
    }
}

// MARK: - PBKDF2 Helper

private struct PBKDF2 {
    static func deriveKey(from password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        var derivedKeyData = Data(count: keyLength)
        let derivedCount = derivedKeyData.count

        let derivationStatus = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        derivedCount
                    )
                }
            }
        }

        return derivationStatus == kCCSuccess ? derivedKeyData : Data()
    }
}
