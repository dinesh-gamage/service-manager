//
//  SettingsModule.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI
import Combine

struct SettingsModule: DevDashModule {
    let id = "settings"
    let name = "Settings"
    let icon = "gearshape.fill"
    let description = "Backup and configuration"
    let accentColor = Color.blue

    func makeSidebarView() -> AnyView {
        AnyView(SettingsSidebarView())
    }

    func makeDetailView() -> AnyView {
        AnyView(SettingsDetailView())
    }

    // MARK: - Backup Support (not applicable for settings)

    var backupFileName: String {
        "settings.json"
    }

    func exportForBackup() async throws -> Data {
        // Settings module doesn't need backup
        return Data()
    }
}

// MARK: - Shared State

@MainActor
class SettingsState: ObservableObject {
    static let shared = SettingsState()

    @Published var selectedCategory: String? = "About"

    private init() {}
}

// MARK: - Sidebar View

struct SettingsSidebarView: View {
    @ObservedObject var state = SettingsState.shared

    // Define setting categories as simple items
    let categories: [SettingCategory] = [
        SettingCategory(id: "About", name: "About", icon: "info.circle"),
        SettingCategory(id: "Backup", name: "Backup", icon: "arrow.triangle.2.circlepath")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar (empty for now)
            HStack(spacing: 12) {
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(AppTheme.toolbarBackground)

            Divider()

            // Settings Categories List
            List {
                ForEach(categories) { category in
                    ModuleSidebarListItem(
                        icon: .image(systemName: category.icon, color: .blue),
                        title: category.name,
                        subtitle: nil,
                        badge: nil,
                        actions: [],
                        isSelected: state.selectedCategory == category.id,
                        onTap: {
                            state.selectedCategory = category.id
                        }
                    )
                }
            }
            .listStyle(.plain)
        }
        .onAppear {
            AppTheme.AccentColor.shared.set(.blue)
        }
    }
}

// MARK: - Setting Category Model

struct SettingCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
}

// MARK: - Detail View

struct SettingsDetailView: View {
    @ObservedObject var state = SettingsState.shared

    var body: some View {
        switch state.selectedCategory {
        case "About":
            AboutDetailView()
        case "Backup":
            BackupDetailView()
        default:
            // Empty state
            VStack(spacing: 16) {
                Image(systemName: "gearshape")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)

                Text("Select a Setting")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - About Detail View

struct AboutDetailView: View {
    @ObservedObject private var accentColor = AppTheme.AccentColor.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("About DevDash")
                    .font(AppTheme.h1)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // App Icon and Name
                    HStack(spacing: 24) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 80))
                            .foregroundColor(accentColor.current)
                            .frame(width: 100, height: 100)
                            .background(accentColor.current.opacity(0.1))
                            .cornerRadius(16)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("DevDash")
                                .font(.system(size: 32, weight: .bold))

                            Text("Local Development Workflow Manager")
                                .font(.title3)
                                .foregroundColor(.secondary)

                            Text("Version 1.0.0")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    Divider()

                    // Description
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What is DevDash?")
                            .font(.headline)

                        Text("DevDash is a native macOS application designed to streamline your local development workflows. It provides a centralized interface to manage development services, track AWS resources, and securely store credentials.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Features
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Key Features")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {
                            FeatureRow(
                                icon: "play.circle.fill",
                                title: "Service Management",
                                description: "Start, stop, and monitor local development services with real-time logs and error tracking"
                            )

                            FeatureRow(
                                icon: "cloud.fill",
                                title: "EC2 Instance Tracking",
                                description: "Fetch and cache public IPs for AWS EC2 instances across regions"
                            )

                            FeatureRow(
                                icon: "key.fill",
                                title: "Credentials Manager",
                                description: "Securely store credentials using Apple Keychain with biometric authentication"
                            )

                            FeatureRow(
                                icon: "lock.shield.fill",
                                title: "Encrypted Backups",
                                description: "Backup your data to AWS S3 with AES-256-GCM encryption"
                            )
                        }
                    }

                    Divider()

                    // Developer Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Developer")
                            .font(.headline)

                        HStack(spacing: 8) {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(accentColor.current)
                            Text("Built with ❤️ using SwiftUI")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Feature Row Component

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    @ObservedObject private var accentColor = AppTheme.AccentColor.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(accentColor.current)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
