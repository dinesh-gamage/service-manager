//
//  AWSVaultManagerModule.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI
import Combine

struct AWSVaultManagerModule: DevDashModule {
    let id = "aws-vault-manager"
    let name = "AWS Vault Profiles"
    let icon = "key.horizontal.fill"
    let description = "Manage AWS Vault profiles"
    let accentColor = Color.orange

    func makeSidebarView() -> AnyView {
        AnyView(AWSVaultManagerSidebarView())
    }

    func makeDetailView() -> AnyView {
        AnyView(AWSVaultManagerDetailView())
    }

    // MARK: - Backup Support

    var backupFileName: String {
        "aws-vault-profiles.json"
    }

    func exportForBackup() async throws -> Data {
        let manager = AWSVaultManagerState.shared.manager
        var exportData: [[String: Any]] = []

        for profile in manager.profiles {
            var profileData: [String: Any] = [
                "id": profile.id.uuidString,
                "name": profile.name,
                "createdAt": profile.createdAt.timeIntervalSince1970,
                "lastModified": profile.lastModified.timeIntervalSince1970
            ]

            if let region = profile.region { profileData["region"] = region }
            if let desc = profile.description { profileData["description"] = desc }

            // Try to retrieve credentials from keychain
            if let creds = try? manager.retrieveCredentialsFromKeychain(profileName: profile.name) {
                profileData["accessKeyId"] = creds.accessKeyId
                profileData["secretAccessKey"] = creds.secretAccessKey
            }

            exportData.append(profileData)
        }

        let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
        return jsonData
    }
}

// MARK: - Shared State

@MainActor
class AWSVaultManagerState: ObservableObject {
    static let shared = AWSVaultManagerState()

    let alertQueue = AlertQueue()
    let toastQueue = ToastQueue()
    @Published var manager: AWSVaultManager
    @Published var selectedProfile: AWSVaultProfile?

    // UI State
    @Published var showingAddProfile = false
    @Published var showingEditProfile = false
    @Published var profileToEdit: AWSVaultProfile?
    @Published var profileToDelete: AWSVaultProfile?
    @Published var showingDeleteConfirmation = false
    @Published var deleteConfirmationText = ""
    @Published var showingHealthCheck = false
    @Published var healthCheckResult: AWSVaultManager.KeychainHealthStatus?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.manager = AWSVaultManager(alertQueue: alertQueue, toastQueue: toastQueue)

        // Forward manager changes to state
        manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }

    // MARK: - Helper Methods

    func copyToClipboard(_ text: String, fieldName: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        toastQueue.enqueue(message: "\(fieldName) copied to clipboard")
    }
}

// MARK: - Sidebar View

struct AWSVaultManagerSidebarView: View {
    @ObservedObject var state = AWSVaultManagerState.shared

    var body: some View {
        ModuleSidebarList(
            toolbarButtons: [
                ToolbarButtonConfig(icon: "plus.circle", help: "Add Profile") {
                    state.showingAddProfile = true
                },
                ToolbarButtonConfig(icon: "arrow.triangle.2.circlepath", help: "Sync from aws-vault") {
                    Task {
                        let count = await state.manager.syncFromAWSVault()
                        if count > 0 {
                            state.toastQueue.enqueue(message: "Synced \(count) new profile\(count == 1 ? "" : "s") from aws-vault")
                        } else {
                            state.toastQueue.enqueue(message: "No new profiles found")
                        }
                    }
                },
                ToolbarButtonConfig(icon: "stethoscope", help: "Check Keychain Health") {
                    Task {
                        let result = await state.manager.checkKeychainHealth()
                        state.healthCheckResult = result
                        state.showingHealthCheck = true
                    }
                },
                ToolbarButtonConfig(icon: "square.and.arrow.down", help: "Import Profiles") {
                    state.manager.importProfiles()
                },
                ToolbarButtonConfig(icon: "square.and.arrow.up", help: "Export Profiles") {
                    state.manager.exportProfiles()
                }
            ],
            items: state.manager.profiles,
            emptyState: EmptyStateConfig(
                icon: "key.horizontal",
                title: "No AWS Vault Profiles",
                subtitle: "Add a profile to get started",
                buttonText: "Add Profile",
                buttonIcon: "plus",
                buttonAction: { state.showingAddProfile = true }
            ),
            selectedItem: $state.selectedProfile
        ) { profile, isSelected in
            return ModuleSidebarListItem(
                icon: .image(systemName: "key.horizontal.fill", color: .accentColor),
                title: profile.name,
                subtitle: profile.region,
                badge: nil,
                actions: [
                    ListItemAction(icon: "pencil", variant: .primary, tooltip: "Edit") {
                        state.profileToEdit = profile
                        state.showingEditProfile = true
                    },
                    ListItemAction(icon: "trash", variant: .danger, tooltip: "Delete") {
                        state.profileToDelete = profile
                        state.showingDeleteConfirmation = true
                        state.deleteConfirmationText = ""
                    }
                ],
                isSelected: isSelected,
                onTap: { state.selectedProfile = profile }
            )
        }
        .sheet(isPresented: $state.showingAddProfile) {
            AddAWSVaultProfileView(manager: state.manager)
        }
        .sheet(isPresented: $state.showingEditProfile, onDismiss: {
            // Refresh selected profile after edit
            if let profileId = state.profileToEdit?.id {
                state.selectedProfile = state.manager.profiles.first(where: { $0.id == profileId })
            }
            state.profileToEdit = nil
        }) {
            if let profile = state.profileToEdit {
                EditAWSVaultProfileView(manager: state.manager, profile: profile)
            }
        }
        .alertQueue(state.alertQueue)
        .alert("Delete Profile", isPresented: $state.showingDeleteConfirmation) {
            TextField("Type 'confirm'", text: $state.deleteConfirmationText)
            Button("Cancel", role: .cancel) {
                state.profileToDelete = nil
                state.deleteConfirmationText = ""
            }
            Button("Delete", role: .destructive) {
                if let profile = state.profileToDelete {
                    let profileName = profile.name
                    Task {
                        await state.manager.deleteProfile(profile)
                        if state.selectedProfile?.id == profile.id {
                            state.selectedProfile = nil
                        }
                        state.toastQueue.enqueue(message: "'\(profileName)' deleted")
                        state.profileToDelete = nil
                        state.deleteConfirmationText = ""
                    }
                }
            }
            .disabled(state.deleteConfirmationText.lowercased() != "confirm")
        } message: {
            if let profile = state.profileToDelete {
                Text("This will remove '\(profile.name)' from both DevDash and aws-vault. Type 'confirm' to proceed.")
            }
        }
        .alert("Keychain Health Check", isPresented: $state.showingHealthCheck) {
            if let result = state.healthCheckResult {
                if result.hasVersionMismatch || (!result.canAccess && result.keychainExists) {
                    Button("Recreate Keychain") {
                        Task {
                            let (success, message) = await state.manager.recreateKeychainWithMigration()
                            if success {
                                state.toastQueue.enqueue(message: message)
                            } else {
                                state.alertQueue.enqueue(title: "Error", message: message)
                            }
                            state.healthCheckResult = nil
                        }
                    }
                }
                Button("OK", role: .cancel) {
                    state.healthCheckResult = nil
                }
            } else {
                Button("OK", role: .cancel) {
                    state.healthCheckResult = nil
                }
            }
        } message: {
            if let result = state.healthCheckResult {
                if result.isHealthy {
                    if !result.keychainExists {
                        Text(result.errorMessage ?? "Keychain not created yet")
                    } else {
                        Text("✅ AWS Vault keychain is healthy!\n\n• Keychain exists\n• In search list\n• Access working\n• No version mismatches")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.errorMessage ?? "Unknown issue")

                        if let recommendation = result.recommendation {
                            Text("\n\(recommendation)")
                        }
                    }
                }
            }
        }
        .onAppear {
            AppTheme.AccentColor.shared.set(.orange)
        }
    }
}

// MARK: - Detail View

struct AWSVaultManagerDetailView: View {
    @ObservedObject var state = AWSVaultManagerState.shared

    var body: some View {
        if let profile = state.selectedProfile {
            ProfileDetailView(profile: profile)
                .id(profile.id)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)

                Text("Select a Profile")
                    .font(.title2)
                    .foregroundColor(.secondary)

                Text("Choose a profile from the sidebar to view details")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

