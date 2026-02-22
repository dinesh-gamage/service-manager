//
//  BackupManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation
import Combine
import LocalAuthentication

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
    let progress: Double  // 0.0 to 1.0
}

@MainActor
class BackupManager: ObservableObject {
    static let shared = BackupManager()

    @Published var config: BackupConfig?
    @Published var status: BackupStatus = BackupStatus()
    @Published var isBackupInProgress = false
    @Published var currentProgress: BackupProgress?
    @Published var moduleProgressMap: [String: BackupProgress] = [:]  // Track progress per module

    private let fileEncryption = FileEncryption.shared
    private let processEnvironment = ProcessEnvironment.shared
    private let authManager = BiometricAuthManager.shared

    private init() {
        loadConfig()
        loadStatus()
    }

    /// Get the authenticated context for keychain operations
    private var authContext: LAContext? {
        authManager.getAuthenticatedContext()
    }

    // MARK: - Config Management

    func loadConfig() {
        // Try to load config
        let loaded: [BackupConfig]? = StorageManager.shared.load(forKey: "backupConfig")
        config = loaded?.first

        // If config is nil but data exists in UserDefaults, it means decoding failed
        // (likely old config missing awsRegion field) - clear it
        if config == nil && UserDefaults.standard.data(forKey: "backupConfig") != nil {
            UserDefaults.standard.removeObject(forKey: "backupConfig")
        }
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

        // Initialize all modules with "Pending" state
        moduleProgressMap.removeAll()
        for module in modules {
            moduleProgressMap[module.name] = BackupProgress(
                moduleName: module.name,
                status: "Pending...",
                isComplete: false,
                error: nil,
                progress: 0.0
            )
        }

        for module in modules {
            let moduleName = module.name

            do {
                // Update progress: Exporting (25%)
                let exportProgress = BackupProgress(
                    moduleName: moduleName,
                    status: "Exporting...",
                    isComplete: false,
                    error: nil,
                    progress: 0.25
                )
                currentProgress = exportProgress
                moduleProgressMap[moduleName] = exportProgress
                try await Task.sleep(nanoseconds: 300_000_000)  // 300ms delay for visibility

                // Export data from module
                let jsonData = try await module.exportForBackup()

                // Update progress: Encrypting (50%)
                let encryptProgress = BackupProgress(
                    moduleName: moduleName,
                    status: "Encrypting...",
                    isComplete: false,
                    error: nil,
                    progress: 0.50
                )
                currentProgress = encryptProgress
                moduleProgressMap[moduleName] = encryptProgress
                try await Task.sleep(nanoseconds: 300_000_000)  // 300ms delay for visibility

                // Encrypt data with authenticated context
                let encryptedData: Data
                do {
                    encryptedData = try fileEncryption.encrypt(jsonData, context: authContext)
                } catch {
                    throw BackupError.encryptionFailed(error)
                }

                // Update progress: Uploading (75%)
                let uploadProgress = BackupProgress(
                    moduleName: moduleName,
                    status: "Uploading to S3...",
                    isComplete: false,
                    error: nil,
                    progress: 0.75
                )
                currentProgress = uploadProgress
                moduleProgressMap[moduleName] = uploadProgress
                try await Task.sleep(nanoseconds: 300_000_000)  // 300ms delay for visibility

                // Upload to S3
                let fileName = "\(module.backupFileName).enc"
                try await uploadToS3(data: encryptedData, fileName: fileName, config: config)

                // Update progress: Success (100%)
                let successProgress = BackupProgress(
                    moduleName: moduleName,
                    status: "Success",
                    isComplete: true,
                    error: nil,
                    progress: 1.0
                )
                currentProgress = successProgress
                moduleProgressMap[moduleName] = successProgress
                try await Task.sleep(nanoseconds: 300_000_000)  // 300ms delay for visibility

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
                let failedProgress = BackupProgress(
                    moduleName: moduleName,
                    status: "Failed",
                    isComplete: true,
                    error: errorMessage,
                    progress: 0.0
                )
                currentProgress = failedProgress
                moduleProgressMap[moduleName] = failedProgress

                // Record failure
                moduleStatuses.append(ModuleBackupStatus(
                    id: module.id,
                    moduleName: moduleName,
                    success: false,
                    timestamp: Date(),
                    errorMessage: errorMessage
                ))

                // Check if this is an authentication error (AWS vault password denied)
                if errorMessage.contains("authentication") ||
                   errorMessage.contains("credentials") ||
                   errorMessage.contains("denied") ||
                   errorMessage.contains("cancelled") {
                    // Stop backup process - don't continue with other modules
                    // Mark remaining modules as not attempted
                    let currentIndex = modules.firstIndex(where: { $0.name == moduleName }) ?? 0
                    for remainingModule in modules[(currentIndex + 1)...] {
                        moduleProgressMap[remainingModule.name] = BackupProgress(
                            moduleName: remainingModule.name,
                            status: "Cancelled",
                            isComplete: true,
                            error: "Backup cancelled due to authentication failure",
                            progress: 0.0
                        )
                    }
                    break
                }
            }
        }

        // Update overall status
        status.lastBackupDate = Date()
        status.moduleStatuses = moduleStatuses
        saveStatus()

        isBackupInProgress = false
        currentProgress = nil
        // Keep moduleProgressMap so UI can show final states
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

        // Build aws-vault command with region (set as env var for aws-vault STS operations)
        let command = """
        AWS_REGION=\(config.awsRegion) aws-vault exec \(config.awsProfile) -- aws s3 cp "\(tempFile.path)" "\(s3Path)" --region \(config.awsRegion)
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

        // Build aws-vault command with region (set as env var for aws-vault STS operations)
        let command = """
        AWS_REGION=\(config.awsRegion) aws-vault exec \(config.awsProfile) -- aws s3 cp "\(s3Path)" "\(tempFile.path)" --region \(config.awsRegion)
        """

        // Execute command
        let (output, exitCode) = try await runCommand(command)

        guard exitCode == 0 else {
            throw BackupError.downloadFailed(output)
        }

        // Read encrypted data
        let encryptedData = try Data(contentsOf: tempFile)

        // Decrypt with authenticated context
        do {
            return try fileEncryption.decrypt(encryptedData, context: authContext)
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
