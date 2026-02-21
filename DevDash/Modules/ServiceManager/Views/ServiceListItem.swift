//
//  ServiceListItem.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct ServiceListItem: View {
    let serviceInfo: ServiceInfo
    let isSelected: Bool
    var onDelete: () -> Void
    var onEdit: () -> Void

    @State private var isHovering = false
    @State private var isEditHovering = false
    @State private var isDeleteHovering = false
    @ObservedObject var accentColor = AppTheme.AccentColor.shared

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(serviceInfo.isRunning ? AppTheme.statusRunning : AppTheme.statusStopped)
                .frame(width: 8, height: 8)

            Text(serviceInfo.name)
                .font(AppTheme.h3)

            Spacer()

            HStack(spacing: AppTheme.actionButtonSpacing) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: AppTheme.actionButtonSize))
                        .foregroundColor(accentColor.current)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isEditHovering ? accentColor.current.opacity(AppTheme.buttonHoverBackground) : AppTheme.clearColor)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isEditHovering = hovering
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: AppTheme.actionButtonSize))
                        .foregroundColor(AppTheme.errorColor)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isDeleteHovering ? AppTheme.errorColor.opacity(AppTheme.buttonHoverBackground) : AppTheme.clearColor)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isDeleteHovering = hovering
                }
            }
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .padding(.vertical, AppTheme.itemVerticalPadding)
        .padding(.horizontal, AppTheme.itemHorizontalPadding)
        .contentShape(Rectangle())
        .listRowBackground(
            RoundedRectangle(cornerRadius: AppTheme.itemCornerRadius)
                .fill((isSelected || isHovering) ? accentColor.current.opacity(AppTheme.itemSelectedBackground) : AppTheme.clearColor)
        )
        // .listRowInsets(EdgeInsets())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
