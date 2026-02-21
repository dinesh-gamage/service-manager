//
//  CredentialsCountWidget.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct CredentialsCountWidget: View {
    @ObservedObject private var manager = CredentialsManagerState.shared.manager

    var body: some View {
        StatCard(
            icon: "key.fill",
            label: "Credentials",
            value: "\(manager.credentials.count)",
            color: .green
        )
    }
}
