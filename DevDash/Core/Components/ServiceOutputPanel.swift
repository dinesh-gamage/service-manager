//
//  ServiceOutputPanel.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct ServiceOutputPanel<DataSource: OutputViewDataSource, ActionButtons: View, StatusContent: View>: View {
    let title: String
    let metadata: [MetadataRow]
    @ObservedObject var dataSource: DataSource
    let actionButtons: ActionButtons
    let statusContent: StatusContent

    init(
        title: String,
        metadata: [MetadataRow],
        dataSource: DataSource,
        @ViewBuilder actionButtons: () -> ActionButtons,
        @ViewBuilder statusContent: () -> StatusContent
    ) {
        self.title = title
        self.metadata = metadata
        self.dataSource = dataSource
        self.actionButtons = actionButtons()
        self.statusContent = statusContent()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with metadata, actions, and status
            ModuleDetailHeader(
                title: title,
                metadata: metadata,
                actionButtons: {
                    actionButtons
                },
                statusContent: {
                    statusContent
                }
            )

            Divider()

            // Output viewing area
            CommandOutputView(dataSource: dataSource)
        }
    }
}
