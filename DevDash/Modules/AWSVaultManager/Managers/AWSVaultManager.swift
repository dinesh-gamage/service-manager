//
//  AWSVaultManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
class AWSVaultManager: ObservableObject {
    @Published private(set) var profiles: [AWSVaultProfile] = []
    @Published private(set) var isLoading = false
    @Published var listRefreshTrigger = UUID()

    private let alertQueue: AlertQueue

    init(alertQueue: AlertQueue) {
        self.alertQueue = alertQueue
        loadProfiles()
    }

    // MARK: - Profile Management

    func loadProfiles() {
        profiles = StorageManager.shared.load(forKey: "awsVaultProfiles") ?? []
    }

    private func saveProfiles() {
        StorageManager.shared.save(profiles, forKey: "awsVaultProfiles")
    }

    func addProfile(_ profile: AWSVaultProfile, accessKeyId: String?, secretAccessKey: String?) async {
        isLoading = true

        do {
            var updatedProfile = profile

            // If credentials provided, add to aws-vault
            if let accessKeyId = accessKeyId, let secretAccessKey = secretAccessKey {
                try await addToAWSVault(profile: profile, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)

                // Store the current aws-vault binary hash
                updatedProfile.awsVaultBinaryHash = await getCurrentAWSVaultBinaryHash()
            }

            // Add to local storage
            profiles.append(updatedProfile)
            saveProfiles()
            listRefreshTrigger = UUID()

            isLoading = false
        } catch {
            isLoading = false
            alertQueue.enqueue(title: "Error", message: "Failed to add profile: \(error.localizedDescription)")
        }
    }

    func updateProfile(_ profile: AWSVaultProfile, accessKeyId: String?, secretAccessKey: String?) async {
        isLoading = true

        do {
            var updatedProfile = profile
            updatedProfile.lastModified = Date()

            // If credentials provided, update in aws-vault
            if let accessKeyId = accessKeyId, let secretAccessKey = secretAccessKey {
                // Remove old profile from aws-vault
                try await removeFromAWSVault(profileName: profile.name)
                // Add with new credentials
                try await addToAWSVault(profile: profile, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)

                // Update the binary hash since credentials were re-added
                updatedProfile.awsVaultBinaryHash = await getCurrentAWSVaultBinaryHash()
            }

            // Update in local storage
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = updatedProfile
                saveProfiles()
                listRefreshTrigger = UUID()
            }

            isLoading = false
        } catch {
            isLoading = false
            alertQueue.enqueue(title: "Error", message: "Failed to update profile: \(error.localizedDescription)")
        }
    }

    func deleteProfile(_ profile: AWSVaultProfile) async {
        isLoading = true

        var vaultError: Error? = nil

        // Try to remove from aws-vault (but don't fail if it errors)
        do {
            try await removeFromAWSVault(profileName: profile.name)
        } catch {
            vaultError = error
        }

        // Always remove from local storage
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
        listRefreshTrigger = UUID()

        isLoading = false

        // If there was a vault error, show a warning but still succeed
        if let error = vaultError {
            let errorMsg = error.localizedDescription
            let suggestion = errorMsg.contains("-25244") || errorMsg.contains("Keychain Error")
                ? " Click the 🩺 (stethoscope) icon in the toolbar to check keychain health and get fix instructions."
                : " You may need to run 'aws-vault remove \(profile.name)' manually."

            alertQueue.enqueue(
                title: "Warning",
                message: "Profile removed from DevDash, but couldn't remove from aws-vault keychain: \(errorMsg).\(suggestion)"
            )
        }
    }

    // MARK: - AWS Vault CLI Integration

    private func addToAWSVault(profile: AWSVaultProfile, accessKeyId: String, secretAccessKey: String) async throws {
        // aws-vault add requires interactive input, so we'll use expect or input redirection
        let script = """
        #!/bin/bash
        export AWS_ACCESS_KEY_ID="\(accessKeyId)"
        export AWS_SECRET_ACCESS_KEY="\(secretAccessKey)"
        aws-vault add \(profile.name) --env
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "AWSVaultManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }

    private func removeFromAWSVault(profileName: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "aws-vault remove \(profileName) -f"]
        process.environment = ProcessEnvironment.shared.getEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"

            // Ignore error if profile doesn't exist
            if errorMessage.contains("not found") || errorMessage.contains("does not exist") {
                return
            }

            // Provide helpful error message for keychain errors
            if errorMessage.contains("Keychain Error") {
                throw NSError(
                    domain: "AWSVaultManager",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Keychain access denied or locked. The aws-vault keychain may be locked or you may not have permission to access it."]
                )
            }

            throw NSError(domain: "AWSVaultManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }

    func listAWSVaultProfiles() async throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "aws-vault list"]
        process.environment = ProcessEnvironment.shared.getEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "AWSVaultManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        // Parse table output to get profiles WITH credentials
        // Format:
        // Profile                  Credentials              Sessions
        // =======                  ===========              ========
        // lucy-saas                lucy-saas                -
        // ivivacloud               -                        -
        //
        // We only want profiles where Credentials column is NOT "-"

        var profilesWithCredentials: [String] = []
        let lines = output.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            // Skip header and separator lines
            if index < 2 || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }

            // Split by whitespace and filter empty strings
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
                .map { String($0) }

            // Need at least 2 columns: Profile and Credentials
            guard columns.count >= 2 else { continue }

            let profileName = columns[0]
            let credentials = columns[1]

            // Only include profiles that have credentials (credentials column != "-")
            if credentials != "-" {
                profilesWithCredentials.append(profileName)
            }
        }

        return profilesWithCredentials
    }

    // MARK: - Sync

    func syncFromAWSVault() async -> Int {
        do {
            let awsVaultProfiles = try await listAWSVaultProfiles()
            let localNames = Set(profiles.map { $0.name })
            let newProfiles = awsVaultProfiles.filter { !localNames.contains($0) }

            if !newProfiles.isEmpty {
                var updatedProfiles = profiles
                for name in newProfiles {
                    updatedProfiles.append(AWSVaultProfile(name: name, region: nil, description: nil))
                }
                profiles = updatedProfiles
                saveProfiles()
                listRefreshTrigger = UUID()
            }

            return newProfiles.count
        } catch {
            alertQueue.enqueue(title: "Sync Failed", message: error.localizedDescription)
            return 0
        }
    }

    // MARK: - Keychain Health Check

    struct KeychainHealthStatus {
        let isHealthy: Bool
        let keychainExists: Bool
        let isInSearchList: Bool
        let canAccess: Bool
        let hasVersionMismatch: Bool
        let mismatchedProfiles: [String]
        let errorMessage: String?
        let recommendation: String?
    }

    func checkKeychainHealth() async -> KeychainHealthStatus {
        let keychainPath = NSString(string: "~/Library/Keychains/aws-vault.keychain-db").expandingTildeInPath

        // Check if keychain file exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: keychainPath) else {
            return KeychainHealthStatus(
                isHealthy: true,
                keychainExists: false,
                isInSearchList: false,
                canAccess: false,
                hasVersionMismatch: false,
                mismatchedProfiles: [],
                errorMessage: "AWS Vault keychain does not exist yet",
                recommendation: "Add your first profile using the '+ Add Profile' button to create the keychain."
            )
        }

        // Get current aws-vault binary hash
        let currentHash = await getCurrentAWSVaultBinaryHash()

        // Check if keychain is in search list
        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        listProcess.arguments = ["list-keychains", "-d", "user"]

        let listOutput = Pipe()
        listProcess.standardOutput = listOutput

        do {
            try listProcess.run()
            listProcess.waitUntilExit()

            let outputData = listOutput.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let isInSearchList = output.contains("aws-vault.keychain-db")

            if !isInSearchList {
                return KeychainHealthStatus(
                    isHealthy: false,
                    keychainExists: true,
                    isInSearchList: false,
                    canAccess: false,
                    hasVersionMismatch: false,
                    mismatchedProfiles: [],
                    errorMessage: "AWS Vault keychain exists but is not in the keychain search list",
                    recommendation: "Run this command in Terminal:\nsecurity list-keychains -d user -s ~/Library/Keychains/login.keychain-db ~/Library/Keychains/aws-vault.keychain-db"
                )
            }
        } catch {
            return KeychainHealthStatus(
                isHealthy: false,
                keychainExists: true,
                isInSearchList: false,
                canAccess: false,
                hasVersionMismatch: false,
                mismatchedProfiles: [],
                errorMessage: "Failed to check keychain search list: \(error.localizedDescription)",
                recommendation: nil
            )
        }

        // Try to test access by listing profiles
        do {
            _ = try await listAWSVaultProfiles()

            // Check for version mismatches
            var mismatchedProfiles: [String] = []
            if let currentHash = currentHash {
                for profile in profiles {
                    // Only check profiles that have credentials
                    if let storedHash = profile.awsVaultBinaryHash,
                       storedHash != currentHash {
                        mismatchedProfiles.append(profile.name)
                    }
                }
            }

            let hasVersionMismatch = !mismatchedProfiles.isEmpty

            if hasVersionMismatch {
                return KeychainHealthStatus(
                    isHealthy: false,
                    keychainExists: true,
                    isInSearchList: true,
                    canAccess: true,
                    hasVersionMismatch: true,
                    mismatchedProfiles: mismatchedProfiles,
                    errorMessage: "AWS Vault binary has been updated since these profiles were created.",
                    recommendation: "Profile(s) affected: \(mismatchedProfiles.joined(separator: ", "))\n\nThis may cause permission errors. Click 'Recreate Keychain' to fix this automatically."
                )
            }

            // All checks passed
            return KeychainHealthStatus(
                isHealthy: true,
                keychainExists: true,
                isInSearchList: true,
                canAccess: true,
                hasVersionMismatch: false,
                mismatchedProfiles: [],
                errorMessage: nil,
                recommendation: nil
            )
        } catch {
            let errorMsg = error.localizedDescription

            // Check for permission error (-25244)
            if errorMsg.contains("-25244") || errorMsg.contains("Keychain Error") {
                return KeychainHealthStatus(
                    isHealthy: false,
                    keychainExists: true,
                    isInSearchList: true,
                    canAccess: false,
                    hasVersionMismatch: false,
                    mismatchedProfiles: [],
                    errorMessage: "Keychain permission error detected (Code -25244). This usually happens after aws-vault updates.",
                    recommendation: "Delete and recreate the keychain:\n\n1. Run in Terminal:\n   rm ~/Library/Keychains/aws-vault.keychain-db\n\n2. Re-add your profiles:\n   aws-vault add <profile-name>\n\nYou'll need to re-enter your AWS credentials.\n\nOr use the 'Recreate Keychain' button for automatic migration."
                )
            }

            return KeychainHealthStatus(
                isHealthy: false,
                keychainExists: true,
                isInSearchList: true,
                canAccess: false,
                hasVersionMismatch: false,
                mismatchedProfiles: [],
                errorMessage: "Failed to access keychain: \(errorMsg)",
                recommendation: "Try running 'aws-vault list' in Terminal to diagnose the issue."
            )
        }
    }

    // MARK: - Keychain Recreation

    func recreateKeychainWithMigration() async -> (success: Bool, message: String) {
        isLoading = true

        // Step 1: Export all credentials from keychain
        var credentialsMap: [String: (accessKeyId: String, secretAccessKey: String)] = [:]

        for profile in profiles {
            do {
                let creds = try retrieveCredentialsFromKeychain(profileName: profile.name)
                credentialsMap[profile.name] = creds
            } catch {
                // Profile might not have credentials in keychain, skip it
                continue
            }
        }

        guard !credentialsMap.isEmpty else {
            isLoading = false
            return (false, "No credentials found in keychain to migrate.")
        }

        // Step 2: Delete the keychain file
        let keychainPath = NSString(string: "~/Library/Keychains/aws-vault.keychain-db").expandingTildeInPath
        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: keychainPath) {
                try fileManager.removeItem(atPath: keychainPath)
            }
        } catch {
            isLoading = false
            return (false, "Failed to delete keychain: \(error.localizedDescription)")
        }

        // Step 3: Re-add all profiles with their credentials
        var successCount = 0
        var failedProfiles: [String] = []

        for (profileName, creds) in credentialsMap {
            guard let profile = profiles.first(where: { $0.name == profileName }) else {
                continue
            }

            do {
                // Add to aws-vault
                try await addToAWSVault(profile: profile, accessKeyId: creds.accessKeyId, secretAccessKey: creds.secretAccessKey)

                // Update the profile with new binary hash
                if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                    profiles[index].awsVaultBinaryHash = await getCurrentAWSVaultBinaryHash()
                    profiles[index].lastModified = Date()
                }

                successCount += 1
            } catch {
                failedProfiles.append(profileName)
            }
        }

        // Save updated profiles
        saveProfiles()
        listRefreshTrigger = UUID()
        isLoading = false

        if failedProfiles.isEmpty {
            return (true, "Successfully recreated keychain and migrated \(successCount) profile(s).")
        } else {
            return (false, "Migrated \(successCount) profile(s), but failed for: \(failedProfiles.joined(separator: ", "))")
        }
    }

    // MARK: - AWS Vault Binary Version Tracking

    func getCurrentAWSVaultBinaryHash() async -> String? {
        // Find aws-vault binary location
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "which aws-vault"]
        process.environment = ProcessEnvironment.shared.getEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let binaryPath = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let binaryPath = binaryPath, !binaryPath.isEmpty else { return nil }

            // Calculate SHA256 hash of the binary
            return try await calculateFileSHA256(path: binaryPath)
        } catch {
            return nil
        }
    }

    private func calculateFileSHA256(path: String) async throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        // Output format: "hash  filename"
        let hash = output.components(separatedBy: " ").first
        return hash
    }

    // MARK: - Import/Export

    private func retrieveCredentialsFromKeychain(profileName: String) throws -> (accessKeyId: String, secretAccessKey: String) {
        let keychainPath = NSString(string: "~/Library/Keychains/aws-vault.keychain-db").expandingTildeInPath

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-a", profileName,
            "-s", "aws-vault",
            "-w",
            keychainPath
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AWSVaultManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Credentials not found in keychain for profile '\(profileName)'"])
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let jsonString = String(data: outputData, encoding: .utf8) ?? ""

        struct KeychainCreds: Codable {
            let AccessKeyID: String
            let SecretAccessKey: String
        }

        guard let jsonData = jsonString.data(using: .utf8),
              let creds = try? JSONDecoder().decode(KeychainCreds.self, from: jsonData) else {
            throw NSError(domain: "AWSVaultManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse credentials"])
        }

        return (creds.AccessKeyID, creds.SecretAccessKey)
    }

    func exportProfiles() {
        let panel = NSSavePanel()
        panel.title = "Export AWS Vault Profiles"
        panel.nameFieldStringValue = "aws-vault-profiles-\(Date().timeIntervalSince1970).json"
        panel.allowedContentTypes = [.json]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task {
                do {
                    var exportData: [[String: Any]] = []

                    for profile in self.profiles {
                        var profileData: [String: Any] = [
                            "id": profile.id.uuidString,
                            "name": profile.name,
                            "createdAt": profile.createdAt.timeIntervalSince1970,
                            "lastModified": profile.lastModified.timeIntervalSince1970
                        ]

                        if let region = profile.region { profileData["region"] = region }
                        if let desc = profile.description { profileData["description"] = desc }

                        // Try to retrieve credentials from keychain
                        if let creds = try? self.retrieveCredentialsFromKeychain(profileName: profile.name) {
                            profileData["accessKeyId"] = creds.accessKeyId
                            profileData["secretAccessKey"] = creds.secretAccessKey
                        }

                        exportData.append(profileData)
                    }

                    let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted])
                    try jsonData.write(to: url)

                    await MainActor.run {
                        self.alertQueue.enqueue(
                            title: "Export Successful",
                            message: "Exported \(self.profiles.count) profile(s) with credentials. Keep this file secure!"
                        )
                    }
                } catch {
                    await MainActor.run {
                        self.alertQueue.enqueue(title: "Export Failed", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    func importProfiles() {
        let panel = NSOpenPanel()
        panel.title = "Import AWS Vault Profiles"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task {
                do {
                    let data = try Data(contentsOf: url)
                    let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

                    var importedCount = 0
                    let existingNames = Set(self.profiles.map { $0.name })

                    for item in jsonArray {
                        guard let name = item["name"] as? String,
                              !existingNames.contains(name) else {
                            continue
                        }

                        let profile = AWSVaultProfile(
                            name: name,
                            region: item["region"] as? String,
                            description: item["description"] as? String
                        )

                        let accessKeyId = item["accessKeyId"] as? String
                        let secretAccessKey = item["secretAccessKey"] as? String

                        await self.addProfile(profile, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)
                        importedCount += 1
                    }

                    await MainActor.run {
                        self.alertQueue.enqueue(
                            title: "Import Complete",
                            message: "Imported \(importedCount) profile(s) with credentials"
                        )
                    }
                } catch {
                    await MainActor.run {
                        self.alertQueue.enqueue(title: "Import Failed", message: error.localizedDescription)
                    }
                }
            }
        }
    }
}
