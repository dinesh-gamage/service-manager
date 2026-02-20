//
//  ServiceDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct ServiceDetailView: View {
    @ObservedObject var service: ServiceRuntime
    @State private var showingErrors = false
    @State private var showingWarnings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with actions
            ModuleDetailHeader(
                title: service.config.name,
                metadata: buildMetadata(),
                actionButtons: {
                    HStack {
                        if service.isRunning {
                            if service.isExternallyManaged {
                                Badge("Running outside DevDash", icon: "exclamationmark.triangle", variant: .warning)
                            }

                            VariantButton("Stop", variant: .danger) {
                                service.stop()
                            }

                            VariantButton("Restart", variant: .warning) {
                                service.restart()
                            }

                            if service.isExternallyManaged {
                                VariantButton("Kill & Start", variant: .danger) {
                                    service.stop()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        service.start()
                                    }
                                }
                            }
                        } else if service.hasPortConflict {
                            Badge("Port \(service.config.port ?? 0) in use (PID: \(service.conflictingPID ?? 0))", icon: "exclamationmark.triangle", variant: .warning)

                            VariantButton("Kill & Restart", variant: .danger) {
                                service.killAndRestart()
                            }
                        } else {
                            VariantButton("Start", icon: "play.fill", variant: .primary) {
                                service.start()
                            }
                        }

                        VariantButton(icon: "arrow.clockwise", variant: .secondary, tooltip: "Check service status") {
                            Task { await service.checkStatus() }
                        }
                    }
                },
                statusContent: {
                    HStack(spacing: 12) {
                        // Error/Warning badges
                        if !service.errors.isEmpty {
                            HStack(spacing: 6) {
                                Button(action: { showingErrors = true; showingWarnings = false }) {
                                    Badge("\(service.errors.count)", icon: "xmark.circle", variant: .danger)
                                }
                                .buttonStyle(.plain)

                                Divider()
                                    .frame(height: 12)

                                VariantButton(icon: "xmark.circle.fill", variant: .danger, tooltip: "Clear all errors") {
                                    service.clearErrors()
                                    showingErrors = false
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.errorBackground)
                            .cornerRadius(8)
                        }

                        if !service.warnings.isEmpty {
                            HStack(spacing: 6) {
                                Button(action: { showingWarnings = true; showingErrors = false }) {
                                    Badge("\(service.warnings.count)", icon: "exclamationmark.triangle", variant: .warning)
                                }
                                .buttonStyle(.plain)

                                Divider()
                                    .frame(height: 12)

                                VariantButton(icon: "xmark.circle.fill", variant: .warning, tooltip: "Clear all warnings") {
                                    service.clearWarnings()
                                    showingWarnings = false
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.warningBackground)
                            .cornerRadius(8)
                        }

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

            Divider()

            // Logs or Error/Warning List
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if showingErrors || showingWarnings {
                        Button(action: {
                            showingErrors = false
                            showingWarnings = false
                        }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back to Output")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading)
                    }

                    Text(showingErrors ? "Errors" : showingWarnings ? "Warnings" : "Output")
                        .font(.headline)
                        .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 8)

                if showingErrors {
                    ErrorWarningListView(entries: service.errors, type: .error)
                } else if showingWarnings {
                    ErrorWarningListView(entries: service.warnings, type: .warning)
                } else {
                    LogView(logs: service.logs)
                }
            }
        }
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
