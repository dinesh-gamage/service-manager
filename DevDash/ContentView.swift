//
//  ContentView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var registry = ModuleRegistry.shared
    @State private var selectedModuleId: String?
    @State private var showingModuleList = true

    // Module toast queues
    @ObservedObject var serviceToastQueue = ServiceManagerState.shared.toastQueue
    @ObservedObject var ec2ToastQueue = EC2ManagerState.shared.toastQueue
    @ObservedObject var credentialsToastQueue = CredentialsManagerState.shared.toastQueue
    @ObservedObject var awsVaultToastQueue = AWSVaultManagerState.shared.toastQueue
    @ObservedObject var settingsToastQueue = SettingsState.shared.toastQueue

    var selectedModule: (any DevDashModule)? {
        guard let id = selectedModuleId else { return nil }
        return registry.getModule(byId: id)
    }

    var body: some View {
        NavigationSplitView {
            // Single unified sidebar
            VStack(spacing: 0) {
                // Persistent header - always visible
                HStack(spacing: 12) {
                    // Back button (only visible when in module view)
                    if !showingModuleList {
                        VariantButton(icon: "chevron.left", variant: .primary, tooltip: "Back to Modules") {
                            withAnimation {
                                showingModuleList = true
                                selectedModuleId = nil
                            }
                        }
                    }

                    // Logo, title, and subtitle grouped together
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            // DevDash logo
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.title3)
                                .foregroundStyle(.linearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))

                            Text("DevDash")
                                .font(AppTheme.h1)
                        }

                        Text("Developer Dashboard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [AppTheme.gradientPrimary.opacity(0.05), AppTheme.gradientSecondary.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                Divider()

                // Sidebar content
                if showingModuleList {
                    // Show module list
                    VStack(spacing: 0) {
                        List {
                            Section("Modules") {
                                ForEach(registry.modules.filter { $0.id != "settings" }, id: \.id) { module in
                                    Button(action: {
                                        withAnimation {
                                            selectedModuleId = module.id
                                            showingModuleList = false
                                        }
                                    }) {
                                        ModuleListItem(module: module)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowSeparator(.hidden)
                                }
                            }
                        }
                        .listStyle(.plain)

                        // Settings button at bottom
                        Divider()

                        if let settingsModule = registry.getModule(byId: "settings") {
                            HStack(spacing: 12) {
                                Image(systemName: settingsModule.icon)
                                    .font(.title3)
                                    .foregroundColor(settingsModule.accentColor)
                                    .frame(width: 32, height: 32)
                                    .background(settingsModule.accentColor.opacity(selectedModuleId == "settings" ? 0.2 : 0.1))
                                    .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(settingsModule.name)
                                        .font(.body)
                                        .fontWeight(.medium)

                                    Text(settingsModule.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedModuleId == "settings" ? settingsModule.accentColor.opacity(0.08) : AppTheme.clearColor)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation {
                                    selectedModuleId = "settings"
                                    showingModuleList = false
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                } else if let module = selectedModule {
                    // Module name section
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: module.icon)
                                .font(.title3)
                                .foregroundColor(module.accentColor)

                            Text(module.name)
                                .font(AppTheme.h2)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(module.accentColor.opacity(0.08))

                        Divider()

                        // Show selected module's sidebar content
                        module.makeSidebarView()
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            // Detail pane
            if let module = selectedModule {
                module.makeDetailView()
            } else {
                // Dashboard/Home view
                DashboardView(onSelectModule: { moduleId in
                    withAnimation {
                        selectedModuleId = moduleId
                        showingModuleList = false
                    }
                })
            }
        }
        .onChange(of: selectedModuleId) { oldValue, newValue in
            if newValue == "service-manager" {
                ServiceManagerState.shared.manager.checkAllServices()
            }
        }
        .toastQueue(serviceToastQueue)
        .toastQueue(ec2ToastQueue)
        .toastQueue(credentialsToastQueue)
        .toastQueue(awsVaultToastQueue)
        .toastQueue(settingsToastQueue)
    }
}

// MARK: - Module List Item

struct ModuleListItem: View {
    let module: any DevDashModule
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.title3)
                .foregroundColor(module.accentColor)
                .frame(width: 32, height: 32)
                .background(module.accentColor.opacity(isHovered ? 0.2 : 0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(module.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? module.accentColor.opacity(0.08) : AppTheme.clearColor)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    let onSelectModule: (String) -> Void
    @ObservedObject var registry = ModuleRegistry.shared
    @ObservedObject var serviceState = ServiceManagerState.shared
    @ObservedObject var ec2State = EC2ManagerState.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Compact header
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.title2)
                        .foregroundStyle(.linearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))

                    Text("Welcome back, \(NSFullUserName())")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                // Count Widgets
                HStack(spacing: 12) {
                    ServiceCountWidget()
                    EC2CountWidget()
                    CredentialsCountWidget()
                    AWSVaultCountWidget()
                }
                .padding(.horizontal, 20)

                // List Widgets
                HStack(alignment: .top, spacing: 20) {
                    // Service Manager Widget
                    ServiceDashboardWidget(
                        onModuleTap: { onSelectModule("service-manager") }
                    )

                    // EC2 Manager Widget
                    EC2DashboardWidget(
                        onModuleTap: { onSelectModule("ec2-manager") }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Module Card

struct ModuleCard: View {
    let module: any DevDashModule
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 16) {
                // Icon
                Image(systemName: module.icon)
                    .font(.system(size: 48))
                    .foregroundColor(module.accentColor)
                    .frame(width: 80, height: 80)
                    .background(
                        Circle()
                            .fill(module.accentColor.opacity(0.1))
                    )

                // Title and description
                VStack(spacing: 6) {
                    Text(module.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(module.description)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Action hint
                HStack(spacing: 4) {
                    Text("Open")
                        .font(.caption)
                        .fontWeight(.medium)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundColor(module.accentColor)
                .opacity(isHovered ? 1 : 0.7)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(
                        color: isHovered ? module.accentColor.opacity(0.3) : AppTheme.shadowColor,
                        radius: isHovered ? 12 : 6,
                        y: isHovered ? 6 : 3
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isHovered ? module.accentColor.opacity(0.3) : AppTheme.clearColor,
                        lineWidth: 2
                    )
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
