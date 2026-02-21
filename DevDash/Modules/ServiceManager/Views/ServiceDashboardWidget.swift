//
//  ServiceDashboardWidget.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct ServiceDashboardWidget: View {
    let onModuleTap: () -> Void
    @ObservedObject private var manager = ServiceManagerState.shared.manager

    var body: some View {
        DashboardCard(
            title: "Services",
            moduleName: "Service Manager",
            moduleIcon: "gearshape.2.fill",
            accentColor: .blue,
            onModuleTap: onModuleTap
        ) {
            if manager.servicesList.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No services configured")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(manager.servicesList) { serviceInfo in
                            ServiceDashboardRow(serviceInfo: serviceInfo, manager: manager)

                            if serviceInfo.id != manager.servicesList.last?.id {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
        .task {
            manager.checkAllServices()
        }
    }
}

// MARK: - Service Dashboard Row

struct ServiceDashboardRow: View {
    let serviceInfo: ServiceInfo
    let manager: ServiceManager

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(serviceInfo.isRunning ? AppTheme.statusRunning : AppTheme.statusStopped)
                .frame(width: 8, height: 8)

            Text(serviceInfo.name)
                .font(.callout)
                .lineLimit(1)

            Spacer()

            if serviceInfo.isRunning {
                VariantButton(icon: "stop.fill", variant: .danger, tooltip: "Stop", isLoading: serviceInfo.processingAction == .stopping) {
                    manager.getRuntime(id: serviceInfo.id)?.stop()
                }
                .disabled(serviceInfo.processingAction != nil)
            } else {
                VariantButton(icon: "play.fill", variant: .primary, tooltip: "Start", isLoading: serviceInfo.processingAction == .starting) {
                    manager.getRuntime(id: serviceInfo.id)?.start()
                }
                .disabled(serviceInfo.processingAction != nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
