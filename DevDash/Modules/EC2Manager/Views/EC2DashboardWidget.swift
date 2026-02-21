//
//  EC2DashboardWidget.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI
import AppKit

struct EC2DashboardWidget: View {
    let onModuleTap: () -> Void
    @ObservedObject private var manager = EC2ManagerState.shared.manager
    @ObservedObject private var toastQueue = EC2ManagerState.shared.toastQueue

    var allInstances: [(group: InstanceGroup, instance: EC2Instance)] {
        manager.groups.flatMap { group in
            group.instances.map { (group: group, instance: $0) }
        }
    }

    var body: some View {
        DashboardCard(
            title: "EC2 Instances",
            moduleName: "EC2 Manager",
            moduleIcon: "cloud.fill",
            accentColor: .orange,
            onModuleTap: onModuleTap
        ) {
            if allInstances.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cloud")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No instances configured")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(allInstances, id: \.instance.id) { item in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.group.name)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(item.instance.name)
                                        .font(.callout)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if let ip = item.instance.lastKnownIP {
                                    Text(ip)
                                        .font(.caption)
                                        .monospaced()
                                        .foregroundColor(.secondary)

                                    VariantButton(icon: "doc.on.doc", variant: .secondary, tooltip: "Copy IP") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(ip, forType: .string)
                                        toastQueue.enqueue(message: "IP copied: \(ip)")
                                    }
                                } else {
                                    Text("—")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .trailing)
                                }

                                VariantButton(icon: "arrow.down.circle", variant: .primary, tooltip: "Fetch IP", isLoading: manager.isFetching[item.instance.id] == true) {
                                    manager.fetchInstanceIP(group: item.group, instance: item.instance)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            if item.instance.id != allInstances.last?.instance.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
    }
}
