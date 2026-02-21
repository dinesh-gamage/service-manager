//
//  ServiceCountWidget.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct ServiceCountWidget: View {
    @ObservedObject private var manager = ServiceManagerState.shared.manager

    var runningCount: Int {
        manager.servicesList.filter { $0.isRunning }.count
    }

    var stoppedCount: Int {
        manager.servicesList.filter { !$0.isRunning }.count
    }

    var body: some View {
        StatCard(
            icon: "server.rack",
            label: "Services",
            value: "\(runningCount)/\(manager.servicesList.count)",
            color: .blue
            // subtitle: "\(stoppedCount) stopped"
        )
        .task {
            manager.checkAllServices()
        }
    }
}
