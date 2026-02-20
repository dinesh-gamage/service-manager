//
//  ModuleDetailHeader.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

// MARK: - Metadata Row

struct MetadataRow {
    let icon: String
    let label: String
    let value: String?
    let copyable: Bool
    let monospaced: Bool

    init(icon: String, label: String, value: String? = nil, copyable: Bool = false, monospaced: Bool = false) {
        self.icon = icon
        self.label = label
        self.value = value
        self.copyable = copyable
        self.monospaced = monospaced
    }
}

// MARK: - Module Detail Header

struct ModuleDetailHeader<ActionContent: View, StatusContent: View>: View {
    let title: String
    let actionButtons: () -> ActionContent
    let statusContent: () -> StatusContent
    let metadata: [MetadataRow]

    init(
        title: String,
        metadata: [MetadataRow] = [],
        @ViewBuilder actionButtons: @escaping () -> ActionContent = { EmptyView() },
        @ViewBuilder statusContent: @escaping () -> StatusContent = { EmptyView() }
    ) {
        self.title = title
        self.metadata = metadata
        self.actionButtons = actionButtons
        self.statusContent = statusContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and action buttons
            HStack {
                Text(title)
                    .font(AppTheme.h2)

                Spacer()

                // Action buttons
                actionButtons()

                // Status content (badges, indicators)
                statusContent()
            }

            // Metadata rows
            if !metadata.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(metadata.indices, id: \.self) { index in
                        let row = metadata[index]

                        if let value = row.value {
                            if row.copyable {
                                HStack(spacing: 8) {
                                    Image(systemName: row.icon)
                                        .foregroundColor(.secondary)
                                        .frame(width: 16)

                                    InlineCopyableText(value, monospaced: row.monospaced)
                                }
                                .font(.caption)
                            } else {
                                Label("\(row.label): \(value)", systemImage: row.icon)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Label(row.label, systemImage: row.icon)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// Convenience initializer for simple headers (no status content)
extension ModuleDetailHeader where StatusContent == EmptyView {
    init(
        title: String,
        metadata: [MetadataRow] = [],
        @ViewBuilder actionButtons: @escaping () -> ActionContent
    ) {
        self.title = title
        self.metadata = metadata
        self.actionButtons = actionButtons
        self.statusContent = { EmptyView() }
    }
}

// Convenience initializer for minimal headers (no actions or status)
extension ModuleDetailHeader where ActionContent == EmptyView, StatusContent == EmptyView {
    init(
        title: String,
        metadata: [MetadataRow] = []
    ) {
        self.title = title
        self.metadata = metadata
        self.actionButtons = { EmptyView() }
        self.statusContent = { EmptyView() }
    }
}
