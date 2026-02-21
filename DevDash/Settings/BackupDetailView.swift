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
    @ObservedObject private var accentColor = AppTheme.AccentColor.shared
    @State private var isConfigUnlocked = false
    @State private var showingPassphrasePrompt = false
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""

    // Config fields
    @State private var s3Bucket = ""
    @State private var s3Path = ""
    @State private var selectedProfile = ""
    @State private var selectedRegion = ""

    // Error popup
    @State private var showingErrorDetails = false

    // Save feedback
    @State private var saveError: String?
    @State private var showingSaveSuccess = false

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
                    // Hide backup section when editing config
                    if backupManager.hasValidConfig() && !isConfigUnlocked {
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
        .sheet(isPresented: $showingErrorDetails) {
            errorDetailsView
        }
        .onAppear {
            loadConfig()
        }
    }

    // MARK: - Backup Action Section (Modern Design)

    private var backupActionSection: some View {
        HStack(spacing: 24) {
            // Left: Cloud icon
            Image(systemName: lastBackupWasSuccessful ? "icloud.and.arrow.up.fill" : "icloud.and.arrow.up")
                .font(.system(size: 56))
                .foregroundColor(lastBackupWasSuccessful ? .blue : accentColor.current)
                .frame(width: 80)

            Divider()

            // Middle: Status and module list
            VStack(alignment: .leading, spacing: 12) {
                // Last backup status
                HStack(spacing: 8) {
                    Text("Last Success:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let lastBackup = lastSuccessfulBackupDate {
                        Text(dateFormatter.string(from: lastBackup))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    } else {
                        Text("Never")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if !lastBackupWasSuccessful && backupManager.status.hasAnyBackup {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }

                // Module list with status indicators
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(moduleRegistry.modules.filter { $0.id != "settings" }, id: \.id) { module in
                        moduleBackupRow(for: module)
                    }
                    // Settings module
                    if let settingsModule = moduleRegistry.modules.first(where: { $0.id == "settings" }) {
                        moduleBackupRow(for: settingsModule)
                    }
                }
            }

            Spacer()

            // Right: Backup button and error view
            VStack(spacing: 12) {
                VariantButton(
                    "Backup Now",
                    icon: "arrow.triangle.2.circlepath",
                    variant: .primary,
                    isLoading: backupManager.isBackupInProgress,
                    action: performBackup
                )

                if !backupManager.status.failedModules.isEmpty {
                    VariantButton(
                        "View Errors",
                        icon: "exclamationmark.triangle",
                        variant: .danger,
                        action: { showingErrorDetails = true }
                    )
                }
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.current.opacity(0.2), lineWidth: 1)
        )
    }

    // Module backup row with status indicator and progress
    private func moduleBackupRow(for module: any DevDashModule) -> some View {
        HStack(spacing: 8) {
            // Status indicator
            moduleStatusIndicator(for: module)

            // Module name
            Text(module.name)
                .font(.callout)

            Spacer()

            // Progress bar during backup (show for all modules when backup is in progress)
            if let moduleProgress = backupManager.moduleProgressMap[module.name],
               !moduleProgress.isComplete {
                ProgressView(value: moduleProgress.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 100)
                    .tint(moduleProgress.progress > 0 ? accentColor.current : .gray)
            }
        }
    }

    // Status indicator for each module
    @ViewBuilder
    private func moduleStatusIndicator(for module: any DevDashModule) -> some View {
        let moduleName = module.name

        // Check if module has active progress
        if let moduleProgress = backupManager.moduleProgressMap[moduleName] {
            if !moduleProgress.isComplete {
                // In progress or pending
                if moduleProgress.status == "Pending..." {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                } else {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }
            } else {
                // Complete (success or failed)
                if moduleProgress.error == nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        } else if let status = backupManager.status.moduleStatuses.first(where: { $0.moduleName == moduleName }) {
            // Use last backup status
            if status.success {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        } else {
            // No status yet
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
        }
    }

    // Computed property for last successful backup
    private var lastSuccessfulBackupDate: Date? {
        backupManager.status.successfulModules.isEmpty ? nil : backupManager.status.lastBackupDate
    }

    // Check if last backup was successful
    private var lastBackupWasSuccessful: Bool {
        backupManager.status.hasAnyBackup &&
        !backupManager.status.successfulModules.isEmpty &&
        backupManager.status.failedModules.isEmpty
    }

    // MARK: - Configuration Status Card (when locked - Horizontal Layout)

    private var configurationStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration")
                .font(AppTheme.h2)

            if backupManager.hasValidConfig() {
                // Configuration is set up - Three column layout
                HStack(spacing: 24) {
                    // Left: Icon
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.blue)
                        .frame(width: 80)

                    Divider()

                    // Middle: Configuration details
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "externaldrive.fill")
                                .foregroundColor(accentColor.current)
                                .frame(width: 20)
                            Text("S3 Bucket:")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            Text(backupManager.config?.s3Bucket ?? "")
                                .font(.callout)
                                .fontWeight(.medium)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(accentColor.current)
                                .frame(width: 20)
                            Text("Path:")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            Text(backupManager.config?.s3Path ?? "")
                                .font(.callout)
                                .fontWeight(.medium)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                                .foregroundColor(accentColor.current)
                                .frame(width: 20)
                            Text("AWS Profile:")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            Text(backupManager.config?.awsProfile ?? "")
                                .font(.callout)
                                .fontWeight(.medium)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .foregroundColor(accentColor.current)
                                .frame(width: 20)
                            Text("Region:")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            Text(backupManager.config?.awsRegion ?? "")
                                .font(.callout)
                                .fontWeight(.medium)
                        }

                        if FileEncryption.shared.hasPassphrase() {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 20)
                                Text("Encryption:")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                Text("Enabled")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    Spacer()

                    // Right: Edit button
                    VariantButton(
                        "Edit Configuration",
                        icon: "pencil",
                        variant: .primary,
                        action: unlockConfig
                    )
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(accentColor.current.opacity(0.2), lineWidth: 1)
                )
            } else {
                // Not configured yet - Three column layout
                HStack(spacing: 24) {
                    // Left: Icon
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 56))
                        .foregroundColor(.orange)
                        .frame(width: 80)

                    Divider()

                    // Middle: Description
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Set up S3 backup to securely store your data in the cloud.")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Encrypted backups with your passphrase")
                                    .font(.caption)
                            }

                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Automatic sync to AWS S3")
                                    .font(.caption)
                            }

                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Restore on any device with your passphrase")
                                    .font(.caption)
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
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(accentColor.current.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Configuration Form Section (when unlocked)

    private var configurationFormSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with unlock indicator
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
                        .fontWeight(.medium)
                }
            }

            // Save feedback messages
            if let error = saveError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            if showingSaveSuccess {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Configuration saved successfully")
                        .font(.callout)
                        .foregroundColor(.green)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            // Encryption Passphrase Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(accentColor.current)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Encryption Passphrase")
                            .font(.headline)

                        if FileEncryption.shared.hasPassphrase() {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Passphrase is set")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Required for backup encryption")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    Spacer()

                    VariantButton(
                        FileEncryption.shared.hasPassphrase() ? "Change Passphrase" : "Set Passphrase",
                        variant: FileEncryption.shared.hasPassphrase() ? .secondary : .primary,
                        action: { showingPassphrasePrompt = true }
                    )
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accentColor.current.opacity(0.2), lineWidth: 1)
                )
            }

            // S3 Configuration Section
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundColor(accentColor.current)
                    Text("AWS S3 Configuration")
                        .font(.headline)
                }

                // Two columns with fixed width inputs
                VStack(spacing: 16) {
                    // Row 1: S3 Bucket & S3 Path
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("S3 Bucket")
                                .font(.callout)
                                .fontWeight(.medium)
                            TextField("my-devdash-backups", text: $s3Bucket)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 300)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("S3 Path Prefix")
                                .font(.callout)
                                .fontWeight(.medium)
                            TextField("devdash-backups/", text: $s3Path)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 300)
                        }

                        Spacer()
                    }

                    // Row 2: AWS Vault Profile & AWS Region
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AWS Vault Profile")
                                .font(.callout)
                                .fontWeight(.medium)
                            AWSVaultProfilePicker(selectedProfile: $selectedProfile, selectedRegion: $selectedRegion)
                                .frame(width: 300)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("AWS Region")
                                .font(.callout)
                                .fontWeight(.medium)
                            TextField("us-east-1", text: $selectedRegion)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 300)
                        }

                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accentColor.current.opacity(0.2), lineWidth: 1)
            )

            // Action buttons
            HStack(spacing: 12) {
                Spacer()

                VariantButton(
                    "Cancel",
                    icon: "xmark",
                    variant: .secondary,
                    action: {
                        saveError = nil
                        showingSaveSuccess = false
                        loadConfig()
                        lockConfig()
                    }
                )

                VariantButton(
                    "Save Configuration",
                    icon: "checkmark",
                    variant: .primary,
                    action: saveConfig
                )
                .disabled(s3Bucket.isEmpty || s3Path.isEmpty || selectedProfile.isEmpty || selectedRegion.isEmpty || !FileEncryption.shared.hasPassphrase())
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.current.opacity(0.2), lineWidth: 1)
        )
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

    // MARK: - Error Details View

    private var errorDetailsView: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundColor(.red)

                Text("Backup Errors")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()
            }

            Divider()

            // Error list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(backupManager.status.failedModules) { moduleStatus in
                        VStack(alignment: .leading, spacing: 8) {
                            // Module name
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(moduleStatus.moduleName)
                                    .font(.headline)
                            }

                            // Error message
                            if let error = moduleStatus.errorMessage {
                                Text(error)
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 300)

            // Close button
            HStack {
                Spacer()
                VariantButton(
                    "Close",
                    variant: .secondary,
                    action: { showingErrorDetails = false }
                )
            }
        }
        .padding(30)
        .frame(width: 500)
    }

    // MARK: - Actions

    private func loadConfig() {
        if let config = backupManager.config {
            s3Bucket = config.s3Bucket
            s3Path = config.s3Path
            selectedProfile = config.awsProfile
            selectedRegion = config.awsRegion
        }
    }

    private func saveConfig() {
        // Clear previous messages
        saveError = nil
        showingSaveSuccess = false

        // Validate
        guard !s3Bucket.isEmpty else {
            saveError = "S3 Bucket is required"
            return
        }

        guard !s3Path.isEmpty else {
            saveError = "S3 Path is required"
            return
        }

        guard !selectedProfile.isEmpty else {
            saveError = "AWS Vault Profile is required"
            return
        }

        guard !selectedRegion.isEmpty else {
            saveError = "AWS Region is required"
            return
        }

        guard FileEncryption.shared.hasPassphrase() else {
            saveError = "Encryption passphrase must be set before saving"
            return
        }

        // Save config
        let config = BackupConfig(
            s3Bucket: s3Bucket.trimmingCharacters(in: .whitespaces),
            s3Path: s3Path.trimmingCharacters(in: .whitespaces),
            awsProfile: selectedProfile.trimmingCharacters(in: .whitespaces),
            awsRegion: selectedRegion.trimmingCharacters(in: .whitespaces)
        )
        backupManager.saveConfig(config)

        // Show success message
        showingSaveSuccess = true

        // Auto-close after 1.5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                showingSaveSuccess = false
                lockConfig()
            }
        }
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
    @Binding var selectedRegion: String
    @ObservedObject private var manager = AWSVaultManagerState.shared.manager

    var body: some View {
        Picker("", selection: $selectedProfile) {
            Text("Select Profile").tag("")
            ForEach(manager.profiles) { profile in
                Text(profile.name).tag(profile.name)
            }
        }
        .labelsHidden()
        .onChange(of: selectedProfile) { oldValue, newValue in
            // Auto-fill region from selected profile
            if let profile = manager.profiles.first(where: { $0.name == newValue }),
               let region = profile.region, !region.isEmpty {
                selectedRegion = region
            }
        }
    }
}
