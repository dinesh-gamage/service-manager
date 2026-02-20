//
//  ServiceManagerModule.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI
import Combine

struct ServiceManagerModule: DevDashModule {
    let id = "service-manager"
    let name = "Service Manager"
    let icon = "gearshape.2.fill"
    let description = "Manage local development services"
    let accentColor = Color.blue

    func makeSidebarView() -> AnyView {
        AnyView(ServiceManagerSidebarView())
    }

    func makeDetailView() -> AnyView {
        AnyView(ServiceManagerDetailView())
    }
}

// MARK: - Shared State

@MainActor
class ServiceManagerState: ObservableObject {
    static let shared = ServiceManagerState()

    @Published var manager = ServiceManager()
    @Published var selectedService: ServiceRuntime?
    @Published var showingAddService = false
    @Published var showingEditService = false
    @Published var showingJSONEditor = false
    @Published var serviceToEdit: ServiceRuntime?
    @Published var serviceToDelete: ServiceRuntime?
    @Published var showingDeleteConfirmation = false

    private init() {}
}

// MARK: - Toolbar Button Helper

struct ToolbarButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false
    @ObservedObject var accentColor = AppTheme.AccentColor.shared

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(accentColor.current)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isHovered ? accentColor.current.opacity(0.12) : AppTheme.clearColor)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Sidebar View

struct ServiceManagerSidebarView: View {
    @ObservedObject var state = ServiceManagerState.shared

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Direct action buttons (left aligned)
                ToolbarButton(icon: "plus.circle", help: "Add Service") {
                    state.showingAddService = true
                }

                ToolbarButton(icon: "square.and.arrow.down", help: "Import Services") {
                    state.manager.importServices()
                }

                ToolbarButton(icon: "square.and.arrow.up", help: "Export Services") {
                    state.manager.exportServices()
                }

                ToolbarButton(icon: "curlybraces", help: "Edit JSON") {
                    state.showingJSONEditor = true
                }

                ToolbarButton(icon: "arrow.clockwise", help: "Refresh All") {
                    state.manager.checkAllServices()
                }

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(AppTheme.toolbarBackground)

            Divider()

            // Service list
            if state.manager.services.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Services")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Add a service to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { state.showingAddService = true }) {
                        Label("Add Service", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(state.manager.services) { service in
                        ServiceListItem(
                            service: service,
                            isSelected: state.selectedService == service,
                            onDelete: {
                                state.serviceToDelete = service
                                state.showingDeleteConfirmation = true
                            },
                            onEdit: {
                                state.serviceToEdit = service
                                state.showingEditService = true
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            state.selectedService = service
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $state.showingAddService) {
            AddServiceView(manager: state.manager)
        }
        .sheet(isPresented: $state.showingEditService) {
            if let service = state.serviceToEdit {
                EditServiceView(manager: state.manager, service: service)
            }
        }
        .sheet(isPresented: $state.showingJSONEditor) {
            JSONEditorView(manager: state.manager)
        }
        .alert("Import Complete", isPresented: $state.manager.showImportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let message = state.manager.importMessage {
                Text(message)
            }
        }
        .alert("Delete Service", isPresented: $state.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                state.serviceToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let service = state.serviceToDelete,
                   let index = state.manager.services.firstIndex(where: { $0.id == service.id }) {
                    // Clear selection if deleting selected service
                    if state.selectedService == service {
                        state.selectedService = nil
                    }
                    state.manager.deleteService(at: IndexSet(integer: index))
                    state.serviceToDelete = nil
                }
            }
        } message: {
            if let service = state.serviceToDelete {
                Text("Are you sure you want to delete '\(service.config.name)'? This action cannot be undone.")
            }
        }
        .onAppear {
            AppTheme.AccentColor.shared.set(.blue)
            state.manager.checkAllServices()
        }
    }
}

// MARK: - Detail View

struct ServiceManagerDetailView: View {
    @ObservedObject var state = ServiceManagerState.shared

    var body: some View {
        if let service = state.selectedService {
            ServiceDetailView(service: service)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)

                Text("Select a Service")
                    .font(.title2)
                    .foregroundColor(.secondary)

                Text("Choose a service from the sidebar to view details")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
