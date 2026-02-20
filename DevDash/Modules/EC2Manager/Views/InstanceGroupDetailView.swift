//
//  InstanceGroupDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct InstanceGroupDetailView: View {
    @ObservedObject var manager: InstanceGroupManager
    @ObservedObject var state = EC2ManagerState.shared
    let groupId: UUID

    @State private var instanceOutputToView: EC2Instance? = nil
    @State private var showingOutput = false

    // Compute current group from manager's live data
    var group: InstanceGroup? {
        manager.groups.first(where: { $0.id == groupId })
    }

    var body: some View {
        if let group = group {
            ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 0) {
            // Header
            ModuleDetailHeader(
                title: group.name,
                metadata: [
                    MetadataRow(icon: "globe", label: "Region", value: group.region),
                    MetadataRow(icon: "key", label: "Profile", value: group.awsProfile)
                ],
                actionButtons: {
                    HStack(spacing: 12) {
                        VariantButton("Add Instance", icon: "plus", variant: .primary) {
                            state.selectedGroupForInstance = group
                            state.showingAddInstance = true
                        }

                        VariantButton("Edit Group", icon: "pencil", variant: .secondary) {
                            state.groupToEdit = group
                            state.showingEditGroup = true
                        }
                    }
                }
            )

            Divider()

            // Instance Table
            Table(group.instances) {
                TableColumn("Name") { instance in
                    Text(instance.name)
                        .font(.body)
                }
                .width(min: 100, ideal: 120, max: 200)

                TableColumn("Instance ID") { instance in
                    InlineCopyableText(instance.instanceId, monospaced: true)
                }
                .width(min: 150, ideal: 180, max: 250)

                TableColumn("Last Known IP") { instance in
                    if manager.isFetching[instance.id] == true {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Fetching...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let error = instance.fetchError {
                        Badge("Error", variant: .danger)
                            .help(error)
                    } else if let ip = instance.lastKnownIP {
                        InlineCopyableText(ip, monospaced: true)
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 120, ideal: 200, max: 300)

                TableColumn("Last Fetched") { instance in
                    if manager.isFetching[instance.id] == true {
                        Text("Fetching...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let date = instance.lastFetched {
                        RelativeTimeText(date: date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 80, ideal: 100, max: 120)

                TableColumn("") { instance in
                    HStack(spacing: 6) {
                        // View Output button (only if output exists)
                        if manager.instanceOutputs[instance.id] != nil {
                            VariantButton(icon: "eye", variant: .secondary, tooltip: "View Output") {
                                instanceOutputToView = instance
                                showingOutput = true
                            }
                        }

                        if manager.isFetching[instance.id] == true {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            VariantButton(icon: "arrow.clockwise", variant: .primary, tooltip: "Fetch IP") {
                                manager.fetchInstanceIP(group: group, instance: instance)
                            }
                        }

                        VariantButton(icon: "pencil", variant: .secondary, tooltip: "Edit Instance") {
                            state.selectedGroupForInstance = group
                            state.instanceToEdit = instance
                            state.showingEditInstance = true
                        }

                        VariantButton(icon: "trash", variant: .danger, tooltip: "Delete Instance") {
                            state.selectedGroupForInstance = group
                            state.instanceToDelete = instance
                            state.showingDeleteInstanceConfirmation = true
                        }
                    }
                }
                .width(min: 160, ideal: 160, max: 160)
            }
            .padding()
        }

                // Slide-over output panel
                if let instance = instanceOutputToView,
                   let outputViewModel = manager.instanceOutputs[instance.id] {
                    OutputSlideOver(
                        title: "\(instance.name) - Output",
                        dataSource: outputViewModel,
                        isPresented: $showingOutput
                    )
                }
            }
        .sheet(isPresented: $state.showingAddInstance) {
            if let selectedGroup = state.selectedGroupForInstance {
                AddInstanceView(manager: manager, group: selectedGroup)
            }
        }
        .sheet(isPresented: $state.showingEditInstance) {
            if let selectedGroup = state.selectedGroupForInstance,
               let instance = state.instanceToEdit {
                EditInstanceView(manager: manager, group: selectedGroup, instance: instance)
            }
        }
        .alert("Delete Instance", isPresented: $state.showingDeleteInstanceConfirmation) {
            Button("Cancel", role: .cancel) {
                state.instanceToDelete = nil
                state.selectedGroupForInstance = nil
            }
            Button("Delete", role: .destructive) {
                if let selectedGroup = state.selectedGroupForInstance,
                   let instance = state.instanceToDelete {
                    manager.deleteInstance(groupId: selectedGroup.id, instanceId: instance.id)
                    state.instanceToDelete = nil
                    state.selectedGroupForInstance = nil
                }
            }
        } message: {
            if let instance = state.instanceToDelete {
                Text("Are you sure you want to delete '\(instance.name)' (\(instance.instanceId))?")
            }
        }
        } else {
            // Fallback if group not found
            VStack {
                Text("Group not found")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
