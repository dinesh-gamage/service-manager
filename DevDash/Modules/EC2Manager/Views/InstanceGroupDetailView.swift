//
//  InstanceGroupDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct InstanceGroupDetailView: View {
    @ObservedObject var manager: InstanceGroupManager
    let group: InstanceGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(group.name)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 16) {
                    Label("Region: \(group.region)", systemImage: "globe")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("Profile: \(group.awsProfile)", systemImage: "key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Divider()

            // Instance Table
            Table(group.instances) {
                TableColumn("Name") { instance in
                    Text(instance.name)
                        .font(.body)
                }
                .width(min: 100, ideal: 120, max: 200)

                TableColumn("Instance ID") { instance in
                    Text(instance.instanceId)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .width(min: 150, ideal: 180, max: 250)

                TableColumn("Last Known IP") { instance in
                    if let ip = instance.lastKnownIP {
                        Text(ip)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
                .width(min: 120, ideal: 150, max: 200)

                TableColumn("Last Fetched") { instance in
                    if let date = instance.lastFetched {
                        Text(date, style: .relative)
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
                    if manager.isFetching[instance.id] == true {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button("Fetch IP") {
                            manager.fetchInstanceIP(group: group, instance: instance)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .width(min: 90, ideal: 90, max: 90)
            }
            .padding()
        }
    }
}
