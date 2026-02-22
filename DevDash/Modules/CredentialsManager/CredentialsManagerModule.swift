//
//  CredentialsManagerModule.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI
import Combine

struct CredentialsManagerModule: DevDashModule {
    let id = "credentials-manager"
    let name = "Credentials Manager"
    let icon = "key.fill"
    let description = "Secure credential storage"
    let accentColor = Color.green

    func makeSidebarView() -> AnyView {
        AnyView(CredentialsManagerSidebarView())
    }

    func makeDetailView() -> AnyView {
        AnyView(CredentialsManagerDetailView())
    }

    // MARK: - Backup Support

    var backupFileName: String {
        "credentials.json"
    }

    func exportForBackup() async throws -> Data {
        let manager = CredentialsManagerState.shared.manager
        let keychainManager = KeychainManager.shared
        let authManager = BiometricAuthManager.shared
        let authContext = authManager.getAuthenticatedContext()

        // Export with all secrets from Keychain using Codable format
        let exportData = try manager.credentials.map { credential -> ImportCredential in
            // Retrieve password from Keychain
            let password = try? keychainManager.retrieve(credential.passwordKeychainKey, context: authContext)

            // Retrieve access token if exists
            var accessToken: String?
            if let accessTokenKey = credential.accessTokenKeychainKey {
                accessToken = try? keychainManager.retrieve(accessTokenKey, context: authContext)
            }

            // Retrieve recovery codes if exists
            var recoveryCodes: String?
            if let recoveryCodesKey = credential.recoveryCodesKeychainKey {
                recoveryCodes = try? keychainManager.retrieve(recoveryCodesKey, context: authContext)
            }

            // Include all fields (including secret ones from Keychain)
            let fields = try credential.additionalFields.map { field -> ImportCredentialField in
                let value: String
                if field.isSecret {
                    // Retrieve secret value from Keychain
                    value = (try? keychainManager.retrieve(field.keychainKey, context: authContext)) ?? ""
                } else {
                    value = field.value
                }
                return ImportCredentialField(
                    key: field.key,
                    value: value,
                    isSecret: field.isSecret
                )
            }

            return ImportCredential(
                id: credential.id.uuidString,
                title: credential.title,
                category: credential.category,
                username: credential.username,
                url: credential.url,
                password: password,
                accessToken: accessToken,
                recoveryCodes: recoveryCodes,
                additionalFields: fields.isEmpty ? nil : fields,
                notes: credential.notes,
                createdAt: credential.createdAt.timeIntervalSince1970,
                lastModified: credential.lastModified.timeIntervalSince1970
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(exportData)
        return jsonData
    }
}

// MARK: - Shared State

@MainActor
class CredentialsManagerState: ObservableObject {
    static let shared = CredentialsManagerState()

    let alertQueue = AlertQueue()
    let toastQueue = ToastQueue()
    let authManager = BiometricAuthManager.shared
    @Published var manager: CredentialsManager
    @Published var selectedCredential: Credential?

    // UI State
    @Published var showingAddCredential = false
    @Published var showingEditCredential = false
    @Published var credentialToEdit: Credential?
    @Published var credentialToDelete: Credential?
    @Published var showingDeleteConfirmation = false

    // Search/Filter
    @Published var searchText = ""
    @Published var selectedCategory: String? = nil

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.manager = CredentialsManager(alertQueue: alertQueue, toastQueue: toastQueue)

        // Forward manager changes to state
        manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }

    // MARK: - Clipboard Operations

    func copyToClipboard(_ text: String, fieldName: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        toastQueue.enqueue(message: "\(fieldName) copied to clipboard")
    }

    var filteredCredentials: [Credential] {
        manager.filteredCredentials(searchText: searchText, category: selectedCategory)
    }
}

// MARK: - Sidebar View

struct CredentialsManagerSidebarView: View {
    @ObservedObject var state = CredentialsManagerState.shared

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                VariantButton(icon: "plus.circle", variant: .primary, tooltip: "Add Credential") {
                    state.showingAddCredential = true
                }
                VariantButton(icon: "square.and.arrow.down", variant: .primary, tooltip: "Import Credentials") {
                    state.manager.importCredentials()
                }
                VariantButton(icon: "square.and.arrow.up", variant: .primary, tooltip: "Export Credentials") {
                    state.manager.exportCredentials()
                }
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(AppTheme.toolbarBackground)

            Divider()

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryFilterButton(title: "All", isSelected: state.selectedCategory == nil) {
                        state.selectedCategory = nil
                    }

                    ForEach(CredentialCategory.all, id: \.self) { category in
                        CategoryFilterButton(title: category, isSelected: state.selectedCategory == category) {
                            state.selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search credentials...", text: $state.searchText)
                    .textFieldStyle(.plain)

                if !state.searchText.isEmpty {
                    Button(action: { state.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // List or empty state
            if state.filteredCredentials.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "key")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text(state.searchText.isEmpty && state.selectedCategory == nil ? "No Credentials" : "No Results")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if state.searchText.isEmpty && state.selectedCategory == nil {
                        Text("Add a credential to get started")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: { state.showingAddCredential = true }) {
                            Label("Add Credential", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(state.filteredCredentials) { credential in
                        CredentialListItem(
                            credential: credential,
                            isSelected: state.selectedCredential?.id == credential.id,
                            onTap: {
                                state.selectedCredential = credential
                            },
                            onDelete: {
                                state.credentialToDelete = credential
                                state.showingDeleteConfirmation = true
                            },
                            onEdit: {
                                state.credentialToEdit = credential
                                state.showingEditCredential = true
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $state.showingAddCredential) {
            AddCredentialView(manager: state.manager)
        }
        .sheet(isPresented: $state.showingEditCredential, onDismiss: {
            // Refresh selected credential after edit
            if let credentialId = state.credentialToEdit?.id {
                state.selectedCredential = state.manager.credentials.first(where: { $0.id == credentialId })
            }
            state.credentialToEdit = nil
        }) {
            if let credential = state.credentialToEdit {
                EditCredentialView(manager: state.manager, credential: credential)
            }
        }
        .alertQueue(state.alertQueue)
        .alert("Delete Credential", isPresented: $state.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                state.credentialToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let credential = state.credentialToDelete {
                    let credentialTitle = credential.title
                    if state.selectedCredential == credential {
                        state.selectedCredential = nil
                    }
                    state.manager.deleteCredential(credential)
                    state.toastQueue.enqueue(message: "'\(credentialTitle)' deleted")
                    state.credentialToDelete = nil
                }
            }
        } message: {
            if let credential = state.credentialToDelete {
                Text("Are you sure you want to delete '\(credential.title)'? This action cannot be undone.")
            }
        }
        .onAppear {
            AppTheme.AccentColor.shared.set(.green)
        }
    }
}

// MARK: - Detail View

struct CredentialsManagerDetailView: View {
    @ObservedObject var state = CredentialsManagerState.shared

    var body: some View {
        if let credential = state.selectedCredential {
            CredentialDetailView(credential: credential)
                .id(credential.id)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "key")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)

                Text("Select a Credential")
                    .font(.title2)
                    .foregroundColor(.secondary)

                Text("Choose a credential from the sidebar to view details")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Category Filter Button

struct CategoryFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Credential List Item

struct CredentialListItem: View {
    let credential: Credential
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let subtitle = [credential.category, credential.username]
            .compactMap { $0 }
            .joined(separator: " • ")

        return ModuleSidebarListItem(
            icon: .image(systemName: categoryIcon(credential.category), color: .accentColor),
            title: credential.title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            badge: nil,
            actions: [
                ListItemAction(icon: "pencil", variant: .primary, tooltip: "Edit", action: onEdit),
                ListItemAction(icon: "trash", variant: .danger, tooltip: "Delete", action: onDelete)
            ],
            isSelected: isSelected,
            onTap: onTap
        )
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case CredentialCategory.databases: return "cylinder.fill"
        case CredentialCategory.apiKeys: return "network"
        case CredentialCategory.ssh: return "terminal.fill"
        case CredentialCategory.websites: return "globe"
        case CredentialCategory.servers: return "server.rack"
        case CredentialCategory.applications: return "app.fill"
        default: return "key.fill"
        }
    }
}
