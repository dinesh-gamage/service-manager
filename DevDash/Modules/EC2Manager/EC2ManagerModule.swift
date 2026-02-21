//
//  EC2ManagerModule.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI
import Combine

struct EC2ManagerModule: DevDashModule {
    let id = "ec2-manager"
    let name = "EC2 Manager"
    let icon = "cloud.fill"
    let description = "Track AWS EC2 instance IPs"
    let accentColor = Color.orange

    func makeSidebarView() -> AnyView {
        AnyView(EC2ManagerSidebarView())
    }

    func makeDetailView() -> AnyView {
        AnyView(EC2ManagerDetailView())
    }
}

// MARK: - Shared State

@MainActor
class EC2ManagerState: ObservableObject {
    static let shared = EC2ManagerState()

    let alertQueue = AlertQueue()
    let toastQueue = ToastQueue()
    @Published var manager: InstanceGroupManager
    @Published var selectedGroup: InstanceGroup?

    // Group management
    @Published var showingAddGroup = false
    @Published var showingEditGroup = false
    @Published var showingJSONEditor = false
    @Published var groupToEdit: InstanceGroup?
    @Published var groupToDelete: InstanceGroup?
    @Published var showingDeleteGroupConfirmation = false

    // Instance management
    @Published var showingAddInstance = false
    @Published var showingEditInstance = false
    @Published var selectedGroupForInstance: InstanceGroup?
    @Published var instanceToEdit: EC2Instance?
    @Published var instanceToDelete: EC2Instance?
    @Published var showingDeleteInstanceConfirmation = false
    @Published var instanceToRestart: EC2Instance?
    @Published var showingRestartInstanceConfirmation = false
    @Published var restartConfirmationText = ""

    private init() {
        self.manager = InstanceGroupManager(alertQueue: alertQueue, toastQueue: toastQueue)
    }
}

// MARK: - Sidebar View

struct EC2ManagerSidebarView: View {
    @ObservedObject var state = EC2ManagerState.shared

    var body: some View {
        ModuleSidebarList(
            toolbarButtons: [
                ToolbarButtonConfig(icon: "plus.circle", help: "Add Group") {
                    state.showingAddGroup = true
                },
                ToolbarButtonConfig(icon: "square.and.arrow.down", help: "Import Groups") {
                    state.manager.importGroups()
                },
                ToolbarButtonConfig(icon: "square.and.arrow.up", help: "Export Groups") {
                    state.manager.exportGroups()
                },
                ToolbarButtonConfig(icon: "curlybraces", help: "Edit JSON") {
                    state.showingJSONEditor = true
                }
            ],
            items: state.manager.groups,
            emptyState: EmptyStateConfig(
                icon: "cloud",
                title: "No Instance Groups",
                subtitle: "Add a group to get started",
                buttonText: "Add Group",
                buttonIcon: "plus",
                buttonAction: { state.showingAddGroup = true }
            ),
            selectedItem: $state.selectedGroup,
            refreshTrigger: state.manager.listRefreshTrigger
        ) { group, isSelected in
            let recentCount = group.instances.filter { $0.lastKnownIP != nil && $0.fetchError == nil }.count

            return ModuleSidebarListItem(
                icon: .none,
                title: group.name,
                subtitle: "\(group.region) • \(group.instances.count) instances",
                badge: recentCount > 0 ? Badge("\(recentCount)", variant: .primary) : nil,
                actions: [
                    ListItemAction(icon: "pencil", variant: .primary, tooltip: "Edit") {
                        state.groupToEdit = group
                        state.showingEditGroup = true
                    },
                    ListItemAction(icon: "trash", variant: .danger, tooltip: "Delete") {
                        state.groupToDelete = group
                        state.showingDeleteGroupConfirmation = true
                    }
                ],
                isSelected: isSelected,
                onTap: { state.selectedGroup = group }
            )
        }
        .sheet(isPresented: $state.showingAddGroup) {
            AddInstanceGroupView(manager: state.manager)
        }
        .sheet(isPresented: $state.showingEditGroup) {
            if let group = state.groupToEdit {
                EditInstanceGroupView(manager: state.manager, group: group)
            }
        }
        .sheet(isPresented: $state.showingJSONEditor) {
            InstanceGroupJSONEditorView(manager: state.manager)
        }
        .alertQueue(state.alertQueue)
        .alert("Delete Group", isPresented: $state.showingDeleteGroupConfirmation) {
            Button("Cancel", role: .cancel) {
                state.groupToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let group = state.groupToDelete,
                   let index = state.manager.groups.firstIndex(where: { $0.id == group.id }) {
                    let groupName = group.name
                    // Clear selection if deleting selected group
                    if state.selectedGroup == group {
                        state.selectedGroup = nil
                    }
                    state.manager.deleteGroup(at: IndexSet(integer: index))
                    state.toastQueue.enqueue(message: "'\(groupName)' deleted")
                    state.groupToDelete = nil
                }
            }
        } message: {
            if let group = state.groupToDelete {
                Text("Are you sure you want to delete '\(group.name)'? This will also delete all \(group.instances.count) instance(s) in this group.")
            }
        }
        .onAppear {
            AppTheme.AccentColor.shared.set(.orange)
        }
    }
}

// MARK: - Detail View

struct EC2ManagerDetailView: View {
    @ObservedObject var state = EC2ManagerState.shared

    var body: some View {
        if let group = state.selectedGroup {
            InstanceGroupDetailView(manager: state.manager, groupId: group.id)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "cloud")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)

                Text("Select an Instance Group")
                    .font(.title2)
                    .foregroundColor(.secondary)

                Text("Choose a group from the sidebar to view instances")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
