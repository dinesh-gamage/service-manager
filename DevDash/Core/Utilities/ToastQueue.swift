//
//  ToastQueue.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation
import SwiftUI
import Combine

/// Toast queue for non-blocking success notifications that auto-dismiss
@MainActor
class ToastQueue: ObservableObject {

    /// Represents a single toast notification
    struct ToastItem: Identifiable {
        let id = UUID()
        let message: String
        let icon: String?
        let duration: TimeInterval

        init(message: String, icon: String? = "checkmark.circle.fill", duration: TimeInterval = 3.0) {
            self.message = message
            self.icon = icon
            self.duration = duration
        }
    }

    @Published private(set) var items: [ToastItem] = []

    /// The current toast to display (first in queue)
    var current: ToastItem? {
        items.first
    }

    private var dismissTask: Task<Void, Never>?

    /// Add a toast to the queue
    /// - Parameters:
    ///   - message: Toast message
    ///   - icon: SF Symbol icon name (default: checkmark.circle.fill)
    ///   - duration: How long to show the toast in seconds (default: 3.0)
    func enqueue(message: String, icon: String? = "checkmark.circle.fill", duration: TimeInterval = 3.0) {
        let toast = ToastItem(message: message, icon: icon, duration: duration)
        items.append(toast)

        // Start auto-dismiss timer if this is the first item
        if items.count == 1 {
            scheduleAutoDismiss()
        }
    }

    /// Remove the current toast from queue
    func dequeue() {
        dismissTask?.cancel()
        if !items.isEmpty {
            items.removeFirst()
            // Schedule next toast if available
            if !items.isEmpty {
                scheduleAutoDismiss()
            }
        }
    }

    /// Clear all toasts
    func clear() {
        dismissTask?.cancel()
        items.removeAll()
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()

        guard let currentToast = current else { return }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(currentToast.duration * 1_000_000_000))
            if !Task.isCancelled {
                dequeue()
            }
        }
    }
}

/// Toast view component
struct ToastView: View {
    let toast: ToastQueue.ToastItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let icon = toast.icon {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .semibold))
            }

            Text(toast.message)
                .font(.body)
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 300)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.85))
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
    }
}

/// View modifier to attach toast queue to a view
struct ToastQueueModifier: ViewModifier {
    @ObservedObject var queue: ToastQueue

    func body(content: Content) -> some View {
        ZStack(alignment: .topTrailing) {
            content

            if let currentToast = queue.current {
                ToastView(toast: currentToast, onDismiss: {
                    queue.dequeue()
                })
                .padding(.top, 12)
                .padding(.trailing, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: queue.current?.id)
                .zIndex(1000)
            }
        }
    }
}

extension View {
    /// Attach a toast queue to this view
    /// - Parameter queue: The ToastQueue to use
    /// - Returns: View with toast queue attached
    func toastQueue(_ queue: ToastQueue) -> some View {
        self.modifier(ToastQueueModifier(queue: queue))
    }
}
