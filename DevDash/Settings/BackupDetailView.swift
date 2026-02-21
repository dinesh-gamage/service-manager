//
//  BackupDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct BackupDetailView: View {
    @ObservedObject private var backupManager = BackupManager.shared
    @ObservedObject private var moduleRegistry = ModuleRegistry.shared
    @State private var isConfigUnlocked = false
    @State private var showingPassphrasePrompt = false
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""

    // Config fields
    @State private var s3Bucket = ""
    @State private var s3Path = ""
    @State private var selectedProfile = ""

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ModuleDetailHeader(
                title: "Backup"
            )

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Show backup action section if configured (even before first backup)
                    if backupManager.hasValidConfig() {
                        backupActionSection
                    }

                    // Configuration section - changes based on state
                    if isConfigUnlocked {
                        // Show full form when unlocked
                        configurationFormSection
                    } else {
                        // Show status card when locked
                        configurationStatusCard
                    }

                    Spacer()
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingPassphrasePrompt) {
            passphrasePromptView
        }
        .onAppear {
            loadConfig()
        }
    }

    // MARK: - Backup Action Section (Horizontal Layout)

    private var backupActionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backup")
                .font(AppTheme.h2)

            HStack(spacing: 20) {
                // Left: Backup button and progress
                VStack(alignment: .leading, spacing: 12) {
                    VariantButton(
                        "Backup Now",
                        icon: "arrow.triangle.2.circlepath",
                        variant: .primary,
                        isLoading: backupManager.isBackupInProgress,
                        action: performBackup
                    )

                    if backupManager.isBackupInProgress, let progress = backupManager.currentProgress {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("\(progress.moduleName): \(progress.status)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(width: 200)

                Divider()

                // Right: Backup history and status
                if backupManager.status.hasAnyBackup {
                    VStack(alignment: .leading, spacing: 12) {
                        if let lastBackup = backupManager.status.lastBackupDate {
                            HStack {
                                Text("Last Backup:")
                                    .foregroundColor(.secondary)
                                Text(dateFormatter.string(from: lastBackup))
                                    .fontWeight(.medium)
                            }
                        }

                        HStack(spacing: 24) {
                            // Successful modules
                            if !backupManager.status.successfulModules.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Backed Up (\(backupManager.status.successfulModules.count))")
                                            .font(.headline)
                                            .foregroundColor(.green)
                                    }

                                    ForEach(backupManager.status.successfulModules) { moduleStatus in
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 4, height: 4)
                                            Text(moduleStatus.moduleName)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }

                            // Failed modules
                            if !backupManager.status.failedModules.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                        Text("Failed (\(backupManager.status.failedModules.count))")
                                            .font(.headline)
                                            .foregroundColor(.red)
                                    }

                                    ForEach(backupManager.status.failedModules) { moduleStatus in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Circle()
                                                    .fill(Color.red)
                                                    .frame(width: 4, height: 4)
                                                Text(moduleStatus.moduleName)
                                                    .font(.caption)
                                            }
                                            if let error = moduleStatus.errorMessage {
                                                Text(error)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .padding(.leading, 10)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("No backup history yet")
                                .foregroundColor(.secondary)
                        }
                        Text("Click 'Backup Now' to create your first backup")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Configuration Status Card (when locked - Horizontal Layout)

    private var configurationStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration")
                .font(AppTheme.h2)

            if backupManager.hasValidConfig() {
                // Configuration is set up - Horizontal layout
                HStack(spacing: 20) {
                    // Left: Icon and title
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)

                        VStack(spacing: 4) {
                            Text("Configured")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text("Ready to use")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 140)

                    Divider()

                    // Middle: Configuration details
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "externaldrive.fill")
                                .foregroundColor(.purple)
                                .frame(width: 20)
                            Text("S3 Bucket:")
                                .foregroundColor(.secondary)
                            Text(backupManager.config?.s3Bucket ?? "")
                                .fontWeight(.medium)
                        }

                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.purple)
                                .frame(width: 20)
                            Text("Path:")
                                .foregroundColor(.secondary)
                            Text(backupManager.config?.s3Path ?? "")
                                .fontWeight(.medium)
                        }

                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.purple)
                                .frame(width: 20)
                            Text("AWS Profile:")
                                .foregroundColor(.secondary)
                            Text(backupManager.config?.awsProfile ?? "")
                                .fontWeight(.medium)
                        }

                        if FileEncryption.shared.hasPassphrase() {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 20)
                                Text("Encryption:")
                                    .foregroundColor(.secondary)
                                Text("Enabled")
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .font(.callout)

                    Spacer()

                    // Right: Edit button
                    VariantButton(
                        "Edit Configuration",
                        icon: "pencil",
                        variant: .primary,
                        action: unlockConfig
                    )
                }
                .padding()
            } else {
                // Not configured yet - Horizontal layout
                HStack(spacing: 20) {
                    // Left: Icon and title
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)

                        VStack(spacing: 4) {
                            Text("Not Configured")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text("Setup required")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 140)

                    Divider()

                    // Middle: Description and benefits
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Set up S3 backup to securely store your data in the cloud.")
                            .font(.body)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Encrypted backups with your passphrase")
                                    .font(.callout)
                            }

                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Automatic sync to AWS S3")
                                    .font(.callout)
                            }

                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Restore on any device with your passphrase")
                                    .font(.callout)
                            }
                        }
                    }

                    Spacer()

                    // Right: Configure button
                    VariantButton(
                        "Configure Backup",
                        icon: "gear",
                        variant: .primary,
                        action: unlockConfig
                    )
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Configuration Form Section (when unlocked)

    private var configurationFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Configuration")
                    .font(AppTheme.h2)

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                        .foregroundColor(.green)
                    Text("Unlocked")
                        .foregroundColor(.green)
                        .font(.callout)

                    VariantButton(
                        icon: "xmark",
                        variant: .secondary,
                        tooltip: "Cancel and Lock",
                        action: {
                            loadConfig()
                            lockConfig()
                        }
                    )
                }
            }

            Divider()

            VStack(spacing: 16) {
                // Encryption Passphrase
                VStack(alignment: .leading, spacing: 8) {
                    Text("Encryption Passphrase")
                        .font(.headline)

                    if FileEncryption.shared.hasPassphrase() {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Passphrase is set")
                        }

                        VariantButton(
                            "Change Passphrase",
                            variant: .secondary,
                            action: { showingPassphrasePrompt = true }
                        )
                    } else {
                        Text("No passphrase set. You must set a passphrase to enable backup.")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        VariantButton(
                            "Set Passphrase",
                            variant: .primary,
                            action: { showingPassphrasePrompt = true }
                        )
                    }
                }

                Divider()

                // S3 Configuration
                VStack(alignment: .leading, spacing: 12) {
                    Text("S3 Configuration")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("S3 Bucket")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("my-devdash-backups", text: $s3Bucket)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("S3 Path")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("devdash-backups/", text: $s3Path)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("AWS Vault Profile")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        AWSVaultProfilePicker(selectedProfile: $selectedProfile)
                    }

                    HStack(spacing: 12) {
                        VariantButton(
                            "Cancel",
                            variant: .secondary,
                            action: {
                                loadConfig()
                                lockConfig()
                            }
                        )

                        VariantButton(
                            "Save Configuration",
                            variant: .primary,
                            action: saveConfig
                        )
                        .disabled(s3Bucket.isEmpty || s3Path.isEmpty || selectedProfile.isEmpty)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Passphrase Prompt

    private var passphrasePromptView: some View {
        VStack(spacing: 20) {
            Text(FileEncryption.shared.hasPassphrase() ? "Change Encryption Passphrase" : "Set Encryption Passphrase")
                .font(.title2)
                .fontWeight(.bold)

            Text("This passphrase encrypts your backup files. You'll need it to restore backups on other devices.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            SecureField("Enter Passphrase (min 8 characters)", text: $passphrase)
                .textFieldStyle(.roundedBorder)

            SecureField("Confirm Passphrase", text: $confirmPassphrase)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                VariantButton(
                    "Cancel",
                    variant: .secondary,
                    action: {
                        passphrase = ""
                        confirmPassphrase = ""
                        showingPassphrasePrompt = false
                    }
                )

                VariantButton(
                    "Save",
                    variant: .primary,
                    action: savePassphrase
                )
                .disabled(passphrase.count < 8 || passphrase != confirmPassphrase)
            }
        }
        .padding(30)
        .frame(width: 400)
    }

    // MARK: - Actions

    private func loadConfig() {
        if let config = backupManager.config {
            s3Bucket = config.s3Bucket
            s3Path = config.s3Path
            selectedProfile = config.awsProfile
        }
    }

    private func saveConfig() {
        let config = BackupConfig(
            s3Bucket: s3Bucket,
            s3Path: s3Path,
            awsProfile: selectedProfile
        )
        backupManager.saveConfig(config)
        // Keep unlocked after saving so user can make additional changes
    }

    private func unlockConfig() {
        Task {
            do {
                try await BiometricAuthManager.shared.authenticate(reason: "Authenticate to edit backup settings")
                await MainActor.run {
                    isConfigUnlocked = true
                }
            } catch {
                // Authentication failed or cancelled - keep locked
                await MainActor.run {
                    isConfigUnlocked = false
                }
            }
        }
    }

    private func lockConfig() {
        isConfigUnlocked = false
    }

    private func savePassphrase() {
        do {
            try FileEncryption.shared.savePassphrase(passphrase)
            passphrase = ""
            confirmPassphrase = ""
            showingPassphrasePrompt = false
        } catch {
            // Handle error (show alert)
        }
    }

    private func performBackup() {
        Task {
            do {
                try await backupManager.backupAllModules(modules: moduleRegistry.modules)
            } catch {
                // Show error alert
                print("Backup failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - AWS Vault Profile Picker

struct AWSVaultProfilePicker: View {
    @Binding var selectedProfile: String
    @ObservedObject private var manager = AWSVaultManagerState.shared.manager

    var body: some View {
        Picker("", selection: $selectedProfile) {
            Text("Select Profile").tag("")
            ForEach(manager.profiles) { profile in
                Text(profile.name).tag(profile.name)
            }
        }
        .labelsHidden()
    }
}
