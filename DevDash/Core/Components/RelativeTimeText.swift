//
//  RelativeTimeText.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

/// Displays relative time (e.g., "5 min ago", "2 hours ago") with refresh interval of 1 hour
/// Uses .task modifier for proper lifecycle management and automatic cancellation
struct RelativeTimeText: View {
    let date: Date

    @State private var relativeTime: String = ""

    var body: some View {
        Text(relativeTime)
            .task {
                // Initial update
                updateRelativeTime()

                // Refresh every hour using async/await
                // Task is automatically cancelled when view disappears
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_600_000_000_000) // 1 hour
                    if !Task.isCancelled {
                        updateRelativeTime()
                    }
                }
            }
    }

    private func updateRelativeTime() {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        relativeTime = formatter.localizedString(for: date, relativeTo: Date())
    }
}
