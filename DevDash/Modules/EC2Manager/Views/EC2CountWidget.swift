//
//  EC2CountWidget.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct EC2CountWidget: View {
    @ObservedObject private var manager = EC2ManagerState.shared.manager

    var totalInstances: Int {
        manager.groups.reduce(0) { $0 + $1.instances.count }
    }

    var body: some View {
        StatCard(
            icon: "cloud.fill",
            label: "EC2 Instances",
            value: "\(totalInstances)",
            color: .orange
        )
    }
}
