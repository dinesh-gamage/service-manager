//
//  TunnelRow.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-22.
//

import SwiftUI

struct TunnelRow: View {
    let tunnel: SSHTunnel
    let instance: EC2Instance
    let group: InstanceGroup
    @ObservedObject var manager: InstanceGroupManager

    @State private var showingLogs = false

    var runtime: TunnelRuntime? {
        manager.getTunnelRuntime(tunnelId: tunnel.id)
    }

    var isConnected: Bool {
        runtime?.isConnected ?? false
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            // Tunnel info
            VStack(alignment: .leading, spacing: 4) {
                Text(tunnel.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text("127.0.0.1:\(tunnel.localPort)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .font(.system(.caption, design: .monospaced))

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("\(tunnel.remoteHost):\(tunnel.remotePort)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .font(.system(.caption, design: .monospaced))
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 6) {
                // Copy localhost address
                InlineCopyableText("localhost:\(tunnel.localPort)")

                // View logs button (only if runtime exists)
                if runtime != nil {
                    VariantButton(icon: "terminal", variant: .secondary, tooltip: "View Logs") {
                        showingLogs = true
                    }
                }

                // Start/Stop button
                if isConnected {
                    VariantButton("Stop", icon: "stop.fill", variant: .danger) {
                        manager.stopTunnel(tunnelId: tunnel.id)
                    }
                } else {
                    VariantButton("Start", icon: "play.fill", variant: .primary) {
                        manager.startTunnel(instance: instance, tunnel: tunnel, group: group)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .sheet(isPresented: $showingLogs) {
            if let runtime = runtime {
                TunnelLogsView(tunnel: tunnel, runtime: runtime)
            }
        }
    }

    private var statusColor: Color {
        if let runtime = runtime {
            if runtime.isConnected {
                return .green
            } else if runtime.connectionError != nil {
                return .red
            }
        }
        return .gray
    }
}

// MARK: - Tunnel Logs View

struct TunnelLogsView: View {
    @Environment(\.dismiss) var dismiss
    let tunnel: SSHTunnel
    @ObservedObject var runtime: TunnelRuntime

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Connection status
                    HStack {
                        Circle()
                            .fill(runtime.isConnected ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)

                        Text(runtime.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Error message if any
                    if let error = runtime.connectionError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)

                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }

                    // Logs
                    if runtime.logs.isEmpty {
                        Text("No logs yet")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        Text(runtime.logs)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom)
            }
            .navigationTitle("\(tunnel.name) Logs")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
