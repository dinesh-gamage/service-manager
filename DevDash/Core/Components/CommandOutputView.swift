//
//  CommandOutputView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct CommandOutputView<DataSource: OutputViewDataSource>: View {
    @ObservedObject var dataSource: DataSource

    @State private var showingErrors = false
    @State private var showingWarnings = false
    @State private var searchText = ""

    init(dataSource: DataSource) {
        self.dataSource = dataSource
    }

    var body: some View {
        VStack(spacing: 0) {
            // Single compact header row: Label | Search | Badges
            HStack(spacing: 12) {
                // Left: Output label with back button (when viewing errors/warnings)
                if showingErrors || showingWarnings {
                    Button(action: {
                        showingErrors = false
                        showingWarnings = false
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.caption)
                            Text(showingErrors ? "Errors" : "Warnings")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Output")
                        .font(.headline)
                }

                Spacer()

                // Right: Search box (only when viewing output, not errors/warnings)
                if !showingErrors && !showingWarnings {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))

                        TextField("Search in output...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                            .help("Clear search")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.clearColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppTheme.searchBorder, lineWidth: 1)
                    )
                    .frame(maxWidth: 300)
                        .cornerRadius(4)

                }

                // Right: Error/Warning badges
                HStack(spacing: 8) {
                    // Error badges
                    if !dataSource.errors.isEmpty {
                        HStack(spacing: 6) {
                            Button(action: { showingErrors = true; showingWarnings = false }) {
                                Badge("\(dataSource.errors.count)", icon: "xmark.circle", variant: .danger)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .frame(height: 12)

                            VariantButton(icon: "xmark.circle.fill", variant: .danger, tooltip: "Clear all errors") {
                                dataSource.clearErrors()
                                showingErrors = false
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.errorBackground)
                        .cornerRadius(8)
                    }

                    // Warning badges
                    if !dataSource.warnings.isEmpty {
                        HStack(spacing: 6) {
                            Button(action: { showingWarnings = true; showingErrors = false }) {
                                Badge("\(dataSource.warnings.count)", icon: "exclamationmark.triangle", variant: .warning)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .frame(height: 12)

                            VariantButton(icon: "xmark.circle.fill", variant: .warning, tooltip: "Clear all warnings") {
                                dataSource.clearWarnings()
                                showingWarnings = false
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.warningBackground)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.clearColor.opacity(0.3))

            Divider()

            // Content views
            if showingErrors {
                ErrorWarningListView(entries: dataSource.errors, type: .error)
            } else if showingWarnings {
                ErrorWarningListView(entries: dataSource.warnings, type: .warning)
            } else {
                LogView(logs: dataSource.logs, searchText: $searchText)
            }
        }
    }
}
