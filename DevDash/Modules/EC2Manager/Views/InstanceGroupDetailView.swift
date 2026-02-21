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

                // Conditional: Show output panel OR instance table
                if showingOutput,
                   let instance = instanceOutputToView,
                   let outputViewModel = manager.instanceOutputs[instance.id] {
                    // Output panel with custom title
                    CommandOutputView(dataSource: outputViewModel) {
                        Button(action: {
                            showingOutput = false
                            instanceOutputToView = nil
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.caption)
                                Text("\(instance.name) Output")
                                    .font(.headline)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
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

                TableColumn("Actions") { instance in
                    HStack(spacing: 6) {
                        if manager.isFetching[instance.id] == true {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            VariantButton(icon: "arrow.down.circle", variant: .primary, tooltip: "Fetch IP") {
                                manager.fetchInstanceIP(group: group, instance: instance)
                            }
                        }

                        if manager.isRestarting[instance.id] == true {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            VariantButton(icon: "power.circle", variant: .danger, tooltip: "Restart Instance") {
                                state.selectedGroupForInstance = group
                                state.instanceToRestart = instance
                                state.restartConfirmationText = ""
                                state.showingRestartInstanceConfirmation = true
                            }
                        }

                        if manager.isCheckingHealth[instance.id] == true {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            VariantButton(icon: "stethoscope", variant: .primary, tooltip: "Health Check") {
                                state.healthCheckInstance = instance
                                manager.checkInstanceHealth(group: group, instance: instance) { healthData in
                                    state.healthCheckData = healthData
                                    state.showingHealthCheckResults = true
                                }
                            }
                        }

                        // View Health Check button (only if health data exists)
                        if manager.instanceHealthData[instance.id] != nil {
                            VariantButton(icon: "chart.bar.doc.horizontal", variant: .secondary, tooltip: "View Health Check") {
                                state.healthCheckInstance = instance
                                state.healthCheckData = manager.instanceHealthData[instance.id]
                                state.showingHealthCheckResults = true
                            }
                        }

                        // View Output button (only if output exists)
                        if manager.instanceOutputs[instance.id] != nil {
                            VariantButton(icon: "terminal", variant: .secondary, tooltip: "View Output") {
                                instanceOutputToView = instance
                                showingOutput = true
                            }
                        }
                    }
                }
                .width(min: 200, ideal: 200, max: 200)

                TableColumn("") { instance in
                    HStack(spacing: 6) {
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
                .width(min: 80, ideal: 80, max: 80)
                    }
                    .padding()
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
        .alert("Restart Instance", isPresented: $state.showingRestartInstanceConfirmation) {
            TextField("Type 'confirm' to restart", text: $state.restartConfirmationText)
            Button("Cancel", role: .cancel) {
                state.instanceToRestart = nil
                state.selectedGroupForInstance = nil
                state.restartConfirmationText = ""
            }
            Button("Restart", role: .destructive) {
                if let selectedGroup = state.selectedGroupForInstance,
                   let instance = state.instanceToRestart {
                    manager.restartInstance(group: selectedGroup, instance: instance)
                    state.instanceToRestart = nil
                    state.selectedGroupForInstance = nil
                    state.restartConfirmationText = ""
                }
            }
            .disabled(state.restartConfirmationText.lowercased() != "confirm")
        } message: {
            if let instance = state.instanceToRestart {
                Text("This will stop and restart '\(instance.name)' (\(instance.instanceId)). The instance will be temporarily unavailable.\n\nType 'confirm' to proceed.")
            }
        }
        .sheet(isPresented: $state.showingHealthCheckResults) {
            if let instance = state.healthCheckInstance {
                HealthCheckResultsView(instance: instance, healthData: state.healthCheckData)
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

// MARK: - Health Check Results View

struct HealthCheckResultsView: View {
    @Environment(\.dismiss) var dismiss
    let instance: EC2Instance
    let healthData: [String: Any]?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let data = healthData,
                       let statuses = data["InstanceStatuses"] as? [[String: Any]],
                       let status = statuses.first {

                        // Instance State
                        if let instanceState = status["InstanceState"] as? [String: Any] {
                            HealthCheckSection(title: "Instance State") {
                                HealthCheckRow(label: "State", value: instanceState["Name"] as? String ?? "—")
                                HealthCheckRow(label: "Code", value: "\(instanceState["Code"] as? Int ?? 0)")
                            }
                        }

                        // System Status
                        if let systemStatus = status["SystemStatus"] as? [String: Any] {
                            HealthCheckSection(title: "System Status") {
                                HealthCheckRow(label: "Status", value: systemStatus["Status"] as? String ?? "—")

                                if let details = systemStatus["Details"] as? [[String: Any]] {
                                    ForEach(details.indices, id: \.self) { index in
                                        let detail = details[index]
                                        if let name = detail["Name"] as? String,
                                           let detailStatus = detail["Status"] as? String {
                                            HealthCheckRow(label: name, value: detailStatus)
                                        }
                                    }
                                }
                            }
                        }

                        // Instance Status
                        if let instanceStatus = status["InstanceStatus"] as? [String: Any] {
                            HealthCheckSection(title: "Instance Status") {
                                HealthCheckRow(label: "Status", value: instanceStatus["Status"] as? String ?? "—")

                                if let details = instanceStatus["Details"] as? [[String: Any]] {
                                    ForEach(details.indices, id: \.self) { index in
                                        let detail = details[index]
                                        if let name = detail["Name"] as? String,
                                           let detailStatus = detail["Status"] as? String {
                                            HealthCheckRow(label: name, value: detailStatus)
                                        }
                                    }
                                }
                            }
                        }

                        // Events
                        if let events = status["Events"] as? [[String: Any]], !events.isEmpty {
                            HealthCheckSection(title: "Events") {
                                ForEach(events.indices, id: \.self) { index in
                                    let event = events[index]
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let code = event["Code"] as? String {
                                            Text(code)
                                                .font(.callout)
                                                .fontWeight(.medium)
                                        }
                                        if let description = event["Description"] as? String {
                                            Text(description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if let notBefore = event["NotBefore"] as? String {
                                            Text("Not Before: \(notBefore)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)

                                    if index < events.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }

                        // Availability Zone
                        if let az = status["AvailabilityZone"] as? String {
                            HealthCheckSection(title: "Location") {
                                HealthCheckRow(label: "Availability Zone", value: az)
                            }
                        }

                    } else {
                        // No data or error
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)

                            Text("No Health Data Available")
                                .font(.title3)
                                .fontWeight(.medium)

                            Text("The health check did not return valid data. Check the output logs for details.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Health Check: \(instance.name)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct HealthCheckSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(12)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
        }
    }
}

struct HealthCheckRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)

            Text(value)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(statusColor(for: value))

            Spacer()
        }
    }

    private func statusColor(for value: String) -> Color {
        let normalized = value.lowercased()
        if normalized == "ok" || normalized == "passed" || normalized == "running" {
            return .green
        } else if normalized == "impaired" || normalized == "insufficient-data" || normalized.contains("fail") {
            return .red
        } else if normalized == "initializing" || normalized == "pending" {
            return .orange
        }
        return .primary
    }
}
