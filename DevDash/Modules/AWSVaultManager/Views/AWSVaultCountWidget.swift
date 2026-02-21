//
//  AWSVaultCountWidget.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct AWSVaultCountWidget: View {
    @ObservedObject private var manager = AWSVaultManagerState.shared.manager

    var body: some View {
        StatCard(
            icon: "person.badge.key.fill",
            label: "AWS Profiles",
            value: "\(manager.profiles.count)",
            color: .orange
        )
    }
}
