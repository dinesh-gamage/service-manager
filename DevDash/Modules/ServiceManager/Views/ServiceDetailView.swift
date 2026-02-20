//
//  ServiceDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct ServiceDetailView: View {
    @ObservedObject var service: ServiceRuntime

    var body: some View {
        ServiceOutputPanel(
            title: service.config.name,
            metadata: buildMetadata(),
            dataSource: service,
            actionButtons: {
                HStack {
                    if service.isRunning {
                        if service.isExternallyManaged {
                            Badge("Running outside DevDash", icon: "exclamationmark.triangle", variant: .warning)
                        }

                        VariantButton("Stop", variant: .danger, isLoading: service.processingAction == .stopping) {
                            service.stop()
                        }
                        .disabled(service.processingAction != nil)

                        VariantButton("Restart", variant: .warning, isLoading: service.processingAction == .restarting) {
                            service.restart()
                        }
                        .disabled(service.processingAction != nil)

                        if service.isExternallyManaged {
                            VariantButton("Kill & Start", variant: .danger, isLoading: service.processingAction == .stopping) {
                                service.stop()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    service.start()
                                }
                            }
                            .disabled(service.processingAction != nil)
                        }
                    } else if service.hasPortConflict {
                        Badge("Port \(service.config.port ?? 0) in use (PID: \(service.conflictingPID ?? 0))", icon: "exclamationmark.triangle", variant: .warning)

                        VariantButton("Kill & Restart", variant: .danger, isLoading: service.processingAction == .killingAndRestarting) {
                            service.killAndRestart()
                        }
                        .disabled(service.processingAction != nil)
                    } else {
                        VariantButton("Start", icon: "play.fill", variant: .primary, isLoading: service.processingAction == .starting) {
                            service.start()
                        }
                        .disabled(service.processingAction != nil)
                    }

                    VariantButton(icon: "arrow.clockwise", variant: .secondary, tooltip: "Check service status") {
                        Task { await service.checkStatus() }
                    }
                }
            },
            statusContent: {
                HStack(spacing: 12) {
                    // Status indicator
                    Circle()
                        .fill(service.isRunning ? AppTheme.statusRunning : AppTheme.statusStopped)
                        .frame(width: 12, height: 12)

                    Text(service.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        )
        .task {
            await service.checkStatus()
        }
    }

    private func buildMetadata() -> [MetadataRow] {
        var rows: [MetadataRow] = []

        // Command (copyable)
        rows.append(MetadataRow(
            icon: "terminal",
            label: "Command",
            value: service.config.command,
            copyable: true
        ))

        // Directory (copyable)
        rows.append(MetadataRow(
            icon: "folder",
            label: "Directory",
            value: service.config.workingDirectory,
            copyable: true
        ))

        // Port (optional)
        if let port = service.config.port {
            rows.append(MetadataRow(
                icon: "network",
                label: "Port",
                value: "\(port)"
            ))
        }

        // Environment (optional)
        if !service.config.environment.isEmpty {
            rows.append(MetadataRow(
                icon: "gearshape",
                label: "Environment",
                value: service.config.environment.keys.joined(separator: ", ")
            ))
        }

        // Prerequisites (optional)
        if let prereqs = service.config.prerequisites, !prereqs.isEmpty {
            rows.append(MetadataRow(
                icon: "list.bullet.clipboard",
                label: "Prerequisites",
                value: "\(prereqs.count) command(s)"
            ))
        }

        return rows
    }
}
