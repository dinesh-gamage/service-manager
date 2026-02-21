//
//  ServiceCountWidget.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI
import Combine

struct ServiceCountWidget: View {
    @ObservedObject private var manager = ServiceManagerState.shared.manager
    @State private var updateTrigger = 0

    var runningCount: Int {
        manager.services.filter { $0.isRunning }.count
    }

    var stoppedCount: Int {
        manager.services.filter { !$0.isRunning }.count
    }

    var body: some View {
        StatCard(
            icon: "server.rack",
            label: "Services",
            value: "\(runningCount)/\(manager.services.count)",
            color: .blue,
            // subtitle: "\(stoppedCount) stopped"
        )
        .task {
            manager.checkAllServices()
        }
        .onReceive(servicesPublisher) { _ in
            updateTrigger += 1
        }
        .id(updateTrigger)
    }

    private var servicesPublisher: AnyPublisher<Void, Never> {
        let publishers = manager.services.map { service in
            service.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        }

        if publishers.isEmpty {
            return Just(()).eraseToAnyPublisher()
        }

        return Publishers.MergeMany(publishers).eraseToAnyPublisher()
    }
}
