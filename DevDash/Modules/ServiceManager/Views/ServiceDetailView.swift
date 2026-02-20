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
            VStack(alignment: .leading, spacing: 8) {
                Text(service.config.name)
                    .font(AppTheme.h2)

                // Action buttons
                HStack {
                    if service.isRunning {
                        if service.isExternallyManaged {
                            Text("Running outside DevDash")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        Button("Stop") {
                            service.stop()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button("Restart") {
                            service.restart()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        if service.isExternallyManaged {
                            Button("Kill & Start") {
                                service.stop()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    service.start()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                    } else if service.hasPortConflict {
                        Text("Port \(service.config.port ?? 0) in use (PID: \(service.conflictingPID ?? 0))")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Button("Kill & Restart") {
                            service.killAndRestart()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button("Start") {
                            service.start()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        Task { await service.checkStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Check service status")

                    Spacer()

                    // Error/Warning badges
                    if !service.errors.isEmpty {
                        HStack(spacing: 6) {
                            Button(action: { showingErrors = true; showingWarnings = false }) {
                                HStack(spacing: 4) {
                                    Text("❌")
                                    Text("\(service.errors.count)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .frame(height: 12)

                            Button(action: {
                                service.clearErrors()
                                showingErrors = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Clear all errors")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.errorBackground)
                        .cornerRadius(8)
                    }

                    if !service.warnings.isEmpty {
                        HStack(spacing: 6) {
                            Button(action: { showingWarnings = true; showingErrors = false }) {
                                HStack(spacing: 4) {
                                    Text("⚠️")
                                    Text("\(service.warnings.count)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .frame(height: 12)

                            Button(action: {
                                service.clearWarnings()
                                showingWarnings = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .foregroundColor(.orange.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Clear all warnings")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.warningBackground)
                        .cornerRadius(8)
                    }

                    Circle()
                        .fill(service.isRunning ? AppTheme.statusRunning : AppTheme.statusStopped)
                        .frame(width: 12, height: 12)

                    Text(service.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Divider()

                // Service info
                VStack(alignment: .leading, spacing: 4) {
                    Label("Command: \(service.config.command)", systemImage: "terminal")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("Directory: \(service.config.workingDirectory)", systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let port = service.config.port {
                        Label("Port: \(port)", systemImage: "network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !service.config.environment.isEmpty {
                        Label("Environment: \(service.config.environment.keys.joined(separator: ", "))", systemImage: "gearshape")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let prereqs = service.config.prerequisites, !prereqs.isEmpty {
                        Label("Prerequisites: \(prereqs.count) command(s)", systemImage: "list.bullet.clipboard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()

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
}
