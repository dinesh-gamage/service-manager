//
//  BackupManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation
import Combine

enum BackupError: Error, LocalizedError {
    case configNotSet
    case invalidConfig
    case passphraseNotSet
    case exportFailed(String)
    case encryptionFailed(Error)
    case uploadFailed(String)
    case downloadFailed(String)
    case decryptionFailed(Error)
    case awsCommandFailed(String)
    case noModulesAvailable

    var errorDescription: String? {
        switch self {
        case .configNotSet:
            return "Backup configuration not set"
        case .invalidConfig:
            return "Invalid backup configuration"
        case .passphraseNotSet:
            return "Encryption passphrase not set"
        case .exportFailed(let moduleName):
            return "Failed to export \(moduleName)"
        case .encryptionFailed(let error):
            return "Encryption failed: \(error.localizedDescription)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .decryptionFailed(let error):
            return "Decryption failed: \(error.localizedDescription)"
        case .awsCommandFailed(let message):
            return "AWS command failed: \(message)"
        case .noModulesAvailable:
            return "No modules available for backup"
        }
    }
}

/// Progress update during backup operation
struct BackupProgress {
    let moduleName: String
    let status: String  // "Exporting...", "Encrypting...", "Uploading...", "Success", "Failed"
    let isComplete: Bool
    let error: String?
}

@MainActor
class BackupManager: ObservableObject {
    static let shared = BackupManager()

    @Published var config: BackupConfig?
    @Published var status: BackupStatus = BackupStatus()
    @Published var isBackupInProgress = false
    @Published var currentProgress: BackupProgress?

    private let fileEncryption = FileEncryption.shared
    private let processEnvironment = ProcessEnvironment.shared

    private init() {
        loadConfig()
        loadStatus()
    }

    // MARK: - Config Management

    func loadConfig() {
        let loaded: [BackupConfig]? = StorageManager.shared.load(forKey: "backupConfig")
        config = loaded?.first
    }

    func saveConfig(_ newConfig: BackupConfig) {
        config = newConfig
        StorageManager.shared.save([newConfig], forKey: "backupConfig")
    }

    func hasValidConfig() -> Bool {
        guard let config = config else { return false }
        return config.isValid && fileEncryption.hasPassphrase()
    }

    // MARK: - Status Management

    private func loadStatus() {
        let loaded: [BackupStatus]? = StorageManager.shared.load(forKey: "lastBackupStatus")
        status = loaded?.first ?? BackupStatus()
    }

    private func saveStatus() {
        StorageManager.shared.save([status], forKey: "lastBackupStatus")
    }

    // MARK: - Backup Operations

    /// Backup all modules to S3
    func backupAllModules(modules: [any DevDashModule]) async throws {
        guard let config = config, config.isValid else {
            throw BackupError.configNotSet
        }

        guard fileEncryption.hasPassphrase() else {
            throw BackupError.passphraseNotSet
        }

        guard !modules.isEmpty else {
            throw BackupError.noModulesAvailable
        }

        isBackupInProgress = true
        var moduleStatuses: [ModuleBackupStatus] = []

        for module in modules {
            let moduleName = module.name

            do {
                // Update progress: Exporting
                currentProgress = BackupProgress(
                    moduleName: moduleName,
                    status: "Exporting...",
                    isComplete: false,
                    error: nil
                )

                // Export data from module
                let jsonData = try await module.exportForBackup()

                // Update progress: Encrypting
                currentProgress = BackupProgress(
                    moduleName: moduleName,
                    status: "Encrypting...",
                    isComplete: false,
                    error: nil
                )

                // Encrypt data
                let encryptedData: Data
                do {
                    encryptedData = try fileEncryption.encrypt(jsonData)
                } catch {
                    throw BackupError.encryptionFailed(error)
                }

                // Update progress: Uploading
                currentProgress = BackupProgress(
                    moduleName: moduleName,
                    status: "Uploading to S3...",
                    isComplete: false,
                    error: nil
                )

                // Upload to S3
                let fileName = "\(module.backupFileName).enc"
                try await uploadToS3(data: encryptedData, fileName: fileName, config: config)

                // Update progress: Success
                currentProgress = BackupProgress(
                    moduleName: moduleName,
                    status: "Success",
                    isComplete: true,
                    error: nil
                )

                // Record success
                moduleStatuses.append(ModuleBackupStatus(
                    id: module.id,
                    moduleName: moduleName,
                    success: true,
                    timestamp: Date(),
                    errorMessage: nil
                ))

            } catch {
                // Update progress: Failed
                let errorMessage = error.localizedDescription
                currentProgress = BackupProgress(
                    moduleName: moduleName,
                    status: "Failed",
                    isComplete: true,
                    error: errorMessage
                )

                // Record failure
                moduleStatuses.append(ModuleBackupStatus(
                    id: module.id,
                    moduleName: moduleName,
                    success: false,
                    timestamp: Date(),
                    errorMessage: errorMessage
                ))
            }
        }

        // Update overall status
        status.lastBackupDate = Date()
        status.moduleStatuses = moduleStatuses
        saveStatus()

        isBackupInProgress = false
        currentProgress = nil
    }

    /// Upload encrypted data to S3
    private func uploadToS3(data: Data, fileName: String, config: BackupConfig) async throws {
        // Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(fileName)

        try data.write(to: tempFile)

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        // Build S3 path
        let s3Path = config.s3FullPath(for: fileName)

        // Build aws-vault command
        let command = """
        aws-vault exec \(config.awsProfile) -- aws s3 cp "\(tempFile.path)" "\(s3Path)"
        """

        // Execute command
        let (output, exitCode) = try await runCommand(command)

        guard exitCode == 0 else {
            throw BackupError.uploadFailed(output)
        }
    }

    /// Download and decrypt backup from S3
    func restoreFromS3(fileName: String) async throws -> Data {
        guard let config = config, config.isValid else {
            throw BackupError.configNotSet
        }

        guard fileEncryption.hasPassphrase() else {
            throw BackupError.passphraseNotSet
        }

        // Build S3 path
        let s3Path = config.s3FullPath(for: fileName)

        // Create temp file for download
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(fileName)

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        // Build aws-vault command
        let command = """
        aws-vault exec \(config.awsProfile) -- aws s3 cp "\(s3Path)" "\(tempFile.path)"
        """

        // Execute command
        let (output, exitCode) = try await runCommand(command)

        guard exitCode == 0 else {
            throw BackupError.downloadFailed(output)
        }

        // Read encrypted data
        let encryptedData = try Data(contentsOf: tempFile)

        // Decrypt
        do {
            return try fileEncryption.decrypt(encryptedData)
        } catch {
            throw BackupError.decryptionFailed(error)
        }
    }

    // MARK: - Command Execution

    private func runCommand(_ command: String) async throws -> (output: String, exitCode: Int32) {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", command]
            process.environment = processEnvironment.getEnvironment()

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            var outputData = Data()
            var errorData = Data()

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                outputData.append(handle.availableData)
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                errorData.append(handle.availableData)
            }

            process.terminationHandler = { proc in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                let combined = error.isEmpty ? output : "\(output)\n\(error)"

                continuation.resume(returning: (combined.trimmingCharacters(in: .whitespacesAndNewlines), proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: BackupError.awsCommandFailed(error.localizedDescription))
            }
        }
    }
}
