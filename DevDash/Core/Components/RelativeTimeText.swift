//
//  RelativeTimeText.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

/// Displays relative time (e.g., "5 min ago", "2 hours ago") with refresh interval of 1 hour
/// This prevents unnecessary updates every second like the default .relative style
struct RelativeTimeText: View {
    let date: Date

    @State private var relativeTime: String = ""
    @State private var timer: Timer?

    var body: some View {
        Text(relativeTime)
            .onAppear {
                updateRelativeTime()
                // Refresh every hour (3600 seconds)
                timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
                    updateRelativeTime()
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }

    private func updateRelativeTime() {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        relativeTime = formatter.localizedString(for: date, relativeTo: Date())
    }
}
