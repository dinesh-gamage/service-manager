//
//  ModuleSidebarList.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

// MARK: - List Item Icon

enum ListItemIcon {
    case status(color: Color)
    case image(systemName: String, color: Color)
    case none
}


// MARK: - List Item Action

struct ListItemAction {
    let icon: String
    let variant: ComponentVariant
    let tooltip: String
    let action: () -> Void

    init(icon: String, variant: ComponentVariant = .primary, tooltip: String, action: @escaping () -> Void) {
        self.icon = icon
        self.variant = variant
        self.tooltip = tooltip
        self.action = action
    }
}

// MARK: - Toolbar Button Config

struct ToolbarButtonConfig {
    let icon: String
    let variant: ComponentVariant
    let help: String
    let action: () -> Void

    init(icon: String, variant: ComponentVariant = .primary, help: String, action: @escaping () -> Void) {
        self.icon = icon
        self.variant = variant
        self.help = help
        self.action = action
    }
}

// MARK: - Empty State Config

struct EmptyStateConfig {
    let icon: String
    let title: String
    let subtitle: String
    let buttonText: String?
    let buttonIcon: String?
    let buttonAction: (() -> Void)?

    init(icon: String, title: String, subtitle: String, buttonText: String? = nil, buttonIcon: String? = nil, buttonAction: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.buttonText = buttonText
        self.buttonIcon = buttonIcon
        self.buttonAction = buttonAction
    }
}

// MARK: - Module Sidebar List Item

struct ModuleSidebarListItem: View {
    let icon: ListItemIcon
    let title: String
    let subtitle: String?
    let badge: Badge?
    let actions: [ListItemAction]
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovering = false
    @ObservedObject var accentColor = AppTheme.AccentColor.shared

    init(icon: ListItemIcon, title: String, subtitle: String? = nil, badge: Badge? = nil, actions: [ListItemAction] = [], isSelected: Bool, onTap: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.actions = actions
        self.isSelected = isSelected
        self.onTap = onTap
    }

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            switch icon {
            case .status(let color):
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            case .image(let systemName, let color):
                Image(systemName: systemName)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 20, height: 20)
            case .none:
                EmptyView()
            }

            // Title and subtitle
            VStack(alignment: .leading, spacing: subtitle != nil ? 4 : 0) {
                Text(title)
                    .font(AppTheme.h3)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Badge
            if let badge = badge {
                badge
            }

            // Action buttons (only render when hovering)
            if !actions.isEmpty && isHovering {
                HStack(spacing: AppTheme.actionButtonSpacing) {
                    ForEach(actions.indices, id: \.self) { index in
                        VariantButton(
                            icon: actions[index].icon,
                            variant: actions[index].variant,
                            tooltip: actions[index].tooltip,
                            action: actions[index].action
                        )
                    }
                }
            }
        }
        .frame(minHeight: 30)
        .padding(.vertical, AppTheme.itemVerticalPadding)
        .padding(.horizontal, AppTheme.itemHorizontalPadding)
        .contentShape(Rectangle())
        .listRowBackground(
            RoundedRectangle(cornerRadius: AppTheme.itemCornerRadius)
                .fill((isSelected || isHovering) ? accentColor.current.opacity(AppTheme.itemSelectedBackground) : AppTheme.clearColor)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Module Sidebar List

struct ModuleSidebarList<Item: Identifiable>: View {
    let toolbarButtons: [ToolbarButtonConfig]
    let items: [Item]
    let emptyState: EmptyStateConfig
    let selectedItem: Binding<Item?>
    let itemContent: (Item, Bool) -> ModuleSidebarListItem

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            if !toolbarButtons.isEmpty {
                HStack(spacing: 12) {
                    ForEach(toolbarButtons.indices, id: \.self) { index in
                        VariantButton(
                            icon: toolbarButtons[index].icon,
                            variant: toolbarButtons[index].variant,
                            tooltip: toolbarButtons[index].help,
                            action: toolbarButtons[index].action
                        )
                    }

                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(AppTheme.toolbarBackground)

                Divider()
            }

            // Content
            if items.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: emptyState.icon)
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text(emptyState.title)
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text(emptyState.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let buttonText = emptyState.buttonText,
                       let buttonAction = emptyState.buttonAction {
                        Button(action: buttonAction) {
                            if let buttonIcon = emptyState.buttonIcon {
                                Label(buttonText, systemImage: buttonIcon)
                            } else {
                                Text(buttonText)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // List
                List {
                    ForEach(items) { item in
                        itemContent(item, selectedItem.wrappedValue?.id as? Item.ID == item.id)
                    }
                }
                .listStyle(.plain)
                .id(AppTheme.AccentColor.shared.current)
            }
        }
    }
}
