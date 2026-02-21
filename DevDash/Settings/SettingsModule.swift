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
    let accentColor = Color.purple

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

    @Published var selectedCategory: String? = "Backup"

    private init() {}
}

// MARK: - Sidebar View

struct SettingsSidebarView: View {
    @ObservedObject var state = SettingsState.shared

    // Define setting categories as simple items
    let categories: [SettingCategory] = [
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
                        icon: .image(systemName: category.icon, color: .purple),
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
            AppTheme.AccentColor.shared.set(.purple)
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
        if state.selectedCategory == "Backup" {
            BackupDetailView()
        } else {
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
