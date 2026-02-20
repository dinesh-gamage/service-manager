//
//  AlertQueue.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation
import SwiftUI
import Combine

/// Alert queue that manages showing multiple alerts sequentially
@MainActor
class AlertQueue: ObservableObject {

    /// Represents a single alert in the queue
    struct AlertItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let dismissButtonText: String

        init(title: String, message: String, dismissButtonText: String = "OK") {
            self.title = title
            self.message = message
            self.dismissButtonText = dismissButtonText
        }
    }

    @Published private(set) var items: [AlertItem] = []

    /// The current alert to display (first in queue)
    var current: AlertItem? {
        items.first
    }

    /// Add an alert to the queue
    /// - Parameters:
    ///   - title: Alert title
    ///   - message: Alert message
    ///   - dismissButtonText: Dismiss button text (default: "OK")
    func enqueue(title: String, message: String, dismissButtonText: String = "OK") {
        let alert = AlertItem(title: title, message: message, dismissButtonText: dismissButtonText)
        items.append(alert)
    }

    /// Remove the current alert from queue (called when user dismisses)
    func dequeue() {
        if !items.isEmpty {
            items.removeFirst()
        }
    }

    /// Clear all alerts
    func clear() {
        items.removeAll()
    }
}

/// View modifier to attach alert queue to a view
struct AlertQueueModifier: ViewModifier {
    @ObservedObject var queue: AlertQueue

    func body(content: Content) -> some View {
        content
            .alert(item: Binding(
                get: { queue.current },
                set: { if $0 == nil { queue.dequeue() } }
            )) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(alert.dismissButtonText))
                )
            }
    }
}

extension View {
    /// Attach an alert queue to this view
    /// - Parameter queue: The AlertQueue to use
    /// - Returns: View with alert queue attached
    func alertQueue(_ queue: AlertQueue) -> some View {
        self.modifier(AlertQueueModifier(queue: queue))
    }
}
