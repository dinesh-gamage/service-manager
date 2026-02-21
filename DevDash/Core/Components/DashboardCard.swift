//
//  DashboardCard.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct DashboardCard<Content: View>: View {
    let title: String
    let moduleName: String
    let moduleIcon: String
    let accentColor: Color
    let onModuleTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: moduleIcon)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(accentColor.opacity(0.1))

            // Content area
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accentColor.opacity(0.1))

            // Footer
            Button(action: onModuleTap) {
                HStack {
                    Text(moduleName)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accentColor.opacity(0.4))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .cornerRadius(12)
        .shadow(color: AppTheme.shadowColor, radius: 4, y: 2)
    }
}
