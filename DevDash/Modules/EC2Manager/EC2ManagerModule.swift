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
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Instance Groups")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.toolbarBackground)

            Divider()

            // Group list
            if state.manager.groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cloud")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Instance Groups")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Instance groups will appear here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $state.selectedGroup) {
                    ForEach(state.manager.groups) { group in
                        EC2GroupListItem(group: group)
                            .tag(group)
                    }
                }
                .listStyle(.sidebar)
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

// MARK: - EC2 Group List Item

struct EC2GroupListItem: View {
    let group: InstanceGroup
    @State private var isHovering = false
    @ObservedObject var accentColor = AppTheme.AccentColor.shared

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Label(group.region, systemImage: "globe")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("\(group.instances.count) instances", systemImage: "server.rack")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Show count of instances with recent IPs
            let recentCount = group.instances.filter { $0.lastKnownIP != nil }.count
            if recentCount > 0 {
                Text("\(recentCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AppTheme.badgeBackground)
                    .cornerRadius(10)
            }
        }
        .padding(.vertical, AppTheme.itemVerticalPadding)
        .padding(.horizontal, AppTheme.itemHorizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.itemCornerRadius)
                .fill(isHovering ? accentColor.current.opacity(AppTheme.itemHoverBackground) : AppTheme.clearColor)
        )
        .animation(.easeInOut(duration: AppTheme.animationDuration), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
