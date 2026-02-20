//
//  ErrorWarningListView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct ErrorWarningListView: View {
    let entries: [LogEntry]
    let type: LogEntry.LogType

    @State private var expandedEntries: Set<UUID> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(type == .error ? "❌" : "⚠️")
                                .font(.body)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Line \(entry.lineNumber)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Text(entry.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text(entry.message)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)

                                // Stack trace toggle button
                                if let stackTrace = entry.stackTrace, !stackTrace.isEmpty {
                                    Button(action: {
                                        if expandedEntries.contains(entry.id) {
                                            expandedEntries.remove(entry.id)
                                        } else {
                                            expandedEntries.insert(entry.id)
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: expandedEntries.contains(entry.id) ? "chevron.down" : "chevron.right")
                                                .font(.caption)
                                            Text("Stack Trace (\(stackTrace.count) lines)")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 4)
                                }
                            }
                        }
                        .padding(8)

                        // Expandable stack trace
                        if let stackTrace = entry.stackTrace,
                           !stackTrace.isEmpty,
                           expandedEntries.contains(entry.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(stackTrace.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                        .padding(.leading, 32)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                        }
                    }
                    .background(type == .error ? AppTheme.errorBackground : AppTheme.warningBackground)
                    .cornerRadius(6)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.logBackground)
    }
}
