//
//  ProfileDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct ProfileDetailView: View {
    let profile: AWSVaultProfile

    @ObservedObject private var state = AWSVaultManagerState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with metadata
                ModuleDetailHeader(
                    title: profile.name,
                    metadata: [
                        MetadataRow(icon: "globe", label: "Region", value: profile.region, copyable: true),
                        MetadataRow(icon: "calendar", label: "Created", value: profile.createdAt.formatted(date: .abbreviated, time: .shortened)),
                        MetadataRow(icon: "clock", label: "Modified", value: profile.lastModified.formatted(date: .abbreviated, time: .shortened))
                    ],
                    actionButtons: {
                        HStack(spacing: 12) {
                            VariantButton("Edit", icon: "pencil", variant: .primary) {
                                state.profileToEdit = profile
                                state.showingEditProfile = true
                            }
                        }
                    }
                )

                Divider()

                // Description
                if let description = profile.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Description", systemImage: "note.text")
                            .font(AppTheme.h3)
                            .foregroundColor(.secondary)

                        Text(description)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}
