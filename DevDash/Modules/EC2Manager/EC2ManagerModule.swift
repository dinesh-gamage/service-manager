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

    @Published var manager = InstanceGroupManager()
    @Published var selectedGroup: InstanceGroup?

    private init() {}
}

// MARK: - Sidebar View

struct EC2ManagerSidebarView: View {
    @ObservedObject var state = EC2ManagerState.shared

    var body: some View {
        ModuleSidebarList(
            toolbarButtons: [],
            items: state.manager.groups,
            emptyState: EmptyStateConfig(
                icon: "cloud",
                title: "No Instance Groups",
                subtitle: "Instance groups will appear here"
            ),
            selectedItem: $state.selectedGroup
        ) { group, isSelected in
            let recentCount = group.instances.filter { $0.lastKnownIP != nil }.count

            return ModuleSidebarListItem(
                icon: .none,
                title: group.name,
                subtitle: "\(group.region) • \(group.instances.count) instances",
                badge: recentCount > 0 ? Badge("\(recentCount)", variant: .primary) : nil,
                actions: [],
                isSelected: isSelected,
                onTap: { state.selectedGroup = group }
            )
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
            InstanceGroupDetailView(manager: state.manager, group: group)
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
