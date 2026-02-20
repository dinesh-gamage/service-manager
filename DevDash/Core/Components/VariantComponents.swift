//
//  VariantComponents.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

// MARK: - Component Variant

enum ComponentVariant {
    case primary
    case danger
    case warning
    case secondary

    var color: Color {
        switch self {
        case .primary:
            return AppTheme.AccentColor.shared.current
        case .danger:
            return AppTheme.errorColor
        case .warning:
            return AppTheme.warningColor
        case .secondary:
            return AppTheme.secondaryColor
        }
    }

    var backgroundColor: Color {
        switch self {
        case .primary:
            return AppTheme.AccentColor.shared.current.opacity(0.2)
        case .danger:
            return AppTheme.errorBackground
        case .warning:
            return AppTheme.warningBackground
        case .secondary:
            return Color.gray.opacity(0.1)
        }
    }

    var hoverBackground: Color {
        switch self {
        case .primary:
            return AppTheme.AccentColor.shared.current.opacity(0.12)
        case .danger:
            return AppTheme.errorColor.opacity(0.12)
        case .warning:
            return AppTheme.warningColor.opacity(0.12)
        case .secondary:
            return Color.gray.opacity(0.12)
        }
    }
}

// MARK: - Badge

struct Badge: View {
    let text: String
    let icon: String?
    let variant: ComponentVariant

    @ObservedObject var accentColor = AppTheme.AccentColor.shared

    init(_ text: String, icon: String? = nil, variant: ComponentVariant = .primary) {
        self.text = text
        self.icon = icon
        self.variant = variant
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
            }
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(variant.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(variant.backgroundColor)
        .cornerRadius(10)
    }
}

// MARK: - Variant Button

struct VariantButton: View {
    let label: String?
    let icon: String?
    let variant: ComponentVariant
    let tooltip: String?
    let isLoading: Bool
    let action: () -> Void

    @ObservedObject var accentColor = AppTheme.AccentColor.shared
    @State private var isHovered = false

    // Icon-only button
    init(icon: String, variant: ComponentVariant = .primary, tooltip: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.label = nil
        self.icon = icon
        self.variant = variant
        self.tooltip = tooltip
        self.isLoading = isLoading
        self.action = action
    }

    // Labeled button (with optional icon)
    init(_ label: String, icon: String? = nil, variant: ComponentVariant = .primary, isLoading: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.variant = variant
        self.tooltip = nil
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        if let label = label {
            // Labeled button
            Button(action: action) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 13, height: 13)
                    } else if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                    }
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, icon != nil || isLoading ? 6 : 6)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(variant.color)
            .foregroundColor(.white)
            .cornerRadius(4)
            .disabled(isLoading)
            .opacity(isLoading ? 0.7 : 1.0)
        } else if let icon = icon {
            // Icon-only circular button
            Button(action: action) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 26, height: 26)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(variant.color)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(isHovered ? variant.hoverBackground : AppTheme.clearColor)
                        )
                }
            }
            .buttonStyle(.plain)
            .help(tooltip ?? "")
            .disabled(isLoading)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
}
