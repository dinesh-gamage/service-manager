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

    let alertQueue = AlertQueue()
    let toastQueue = ToastQueue()
    @Published var manager: ServiceManager
    @Published var selectedService: ServiceRuntime?
    @Published var showingAddService = false
    @Published var showingEditService = false
    @Published var showingJSONEditor = false
    @Published var serviceToEdit: ServiceRuntime?
    @Published var serviceToDelete: ServiceRuntime?
    @Published var showingDeleteConfirmation = false

    private init() {
        self.manager = ServiceManager(alertQueue: alertQueue, toastQueue: toastQueue)
    }
}

// MARK: - Sidebar View

struct ServiceManagerSidebarView: View {
    @ObservedObject var state = ServiceManagerState.shared

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                VariantButton(icon: "plus.circle", variant: .primary, tooltip: "Add Service") {
                    state.showingAddService = true
                }
                VariantButton(icon: "square.and.arrow.down", variant: .primary, tooltip: "Import Services") {
                    state.manager.importServices()
                }
                VariantButton(icon: "square.and.arrow.up", variant: .primary, tooltip: "Export Services") {
                    state.manager.exportServices()
                }
                VariantButton(icon: "curlybraces", variant: .primary, tooltip: "Edit JSON") {
                    state.showingJSONEditor = true
                }
                VariantButton(icon: "arrow.clockwise", variant: .primary, tooltip: "Refresh All") {
                    state.manager.checkAllServices()
                }
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(AppTheme.toolbarBackground)

            Divider()

            // List or empty state
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
                            isSelected: state.selectedService?.id == service.id,
                            onDelete: {
                                state.serviceToDelete = service
                                state.showingDeleteConfirmation = true
                            },
                            onEdit: {
                                state.serviceToEdit = service
                                state.showingEditService = true
                            }
                        )
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
        .alertQueue(state.alertQueue)
        .alert("Delete Service", isPresented: $state.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                state.serviceToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let service = state.serviceToDelete,
                   let index = state.manager.services.firstIndex(where: { $0.id == service.id }) {
                    let serviceName = service.config.name
                    // Clear selection if deleting selected service
                    if state.selectedService == service {
                        state.selectedService = nil
                    }
                    state.manager.deleteService(at: IndexSet(integer: index))
                    state.toastQueue.enqueue(message: "'\(serviceName)' deleted")
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
                .id(ObjectIdentifier(service))
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
