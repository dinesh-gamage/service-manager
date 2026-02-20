//
//  AppTheme.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI
import Combine

// MARK: - App Theme

struct AppTheme {
    // MARK: - Basic Colors

    /// Clear/transparent color
    static let clearColor = Color.clear

    /// Secondary text/UI color
    static let secondaryColor = Color.secondary

    // MARK: - Colors (as opacity values)

    /// Background opacity for hovered list items
    static let itemHoverBackground: Double = 0.08

    /// Icon background opacity (normal state)
    static let itemIconBackground: Double = 0.1

    /// Icon background opacity (hovered state)
    static let itemIconBackgroundHover: Double = 0.2

    /// Toolbar background color
    static let toolbarBackground = Color.secondary.opacity(0.1)

    // MARK: - Status Colors

    /// Running/active state color (pastel green)
    static let statusRunning = Color.green.opacity(0.5)

    /// Stopped/inactive state color (pastel red)
    static let statusStopped = Color.red.opacity(0.5)

    /// Warning state color (pastel orange)
    static let statusWarning = Color.orange.opacity(0.5)

    /// Success color for actions (semi-transparent)
    static let successColor = Color.green.opacity(0.7)

    /// Error color for actions (semi-transparent)
    static let errorColor = Color.red.opacity(0.7)

    /// Warning color for alerts (semi-transparent)
    static let warningColor = Color.orange.opacity(0.7)

    // MARK: - Background Colors

    /// Log/list background color
    static let logBackground = Color.black.opacity(0.05)

    /// Error background color
    static let errorBackground = Color.red.opacity(0.05)

    /// Warning background color
    static let warningBackground = Color.orange.opacity(0.05)

    /// Info background color
    static let infoBackground = Color.blue.opacity(0.1)

    /// Search field background
    static let searchBackground = Color.white.opacity(0.5)

    /// Search field border
    static let searchBorder = Color.gray.opacity(0.3)

    /// Shadow color for elevated elements
    static let shadowColor = Color.black.opacity(0.1)

    /// Badge background (semi-transparent)
    static let badgeBackground = Color.green.opacity(0.2)

    /// Badge text color
    static let badgeTextColor = Color.green.opacity(0.9)

    // MARK: - Gradient Colors

    /// Primary gradient start color
    static let gradientPrimary = Color.blue

    /// Primary gradient end color
    static let gradientSecondary = Color.purple

    // MARK: - Typography

    /// H1 - Largest heading (main app title)
    static let h1 = Font.system(size: 20, weight: .bold)

    /// H2 - Secondary heading (module names, detail titles)
    static let h2 = Font.system(size: 16, weight: .semibold)

    /// H3 - Tertiary heading (list items)
    static let h3 = Font.system(size: 12, weight: .medium)

    // MARK: - Layout

    /// Corner radius for list items
    static let itemCornerRadius: CGFloat = 4

    /// Vertical padding for list items
    static let itemVerticalPadding: CGFloat = 4

    /// Horizontal padding for list items
    static let itemHorizontalPadding: CGFloat = 6

    /// Background opacity for selected list items
    static let itemSelectedBackground: Double = 0.08

    /// Scale factor when hovering over items
    static let itemHoverScale: CGFloat = 1.02

    /// Animation duration for hover effects
    static let animationDuration: Double = 0.15

    // MARK: - Action Buttons

    /// Size for action button icons
    static let actionButtonSize: CGFloat = 12

    /// Spacing between action buttons
    static let actionButtonSpacing: CGFloat = 6

    // MARK: - Button Interactions

    /// Scale factor when button is pressed
    static let buttonPressedScale: CGFloat = 0.95

    /// Background opacity when button is hovered
    static let buttonHoverBackground: Double = 0.12

    /// Background opacity when button is pressed
    static let buttonPressedBackground: Double = 0.2

    // MARK: - Current Module Accent Color

    @MainActor
    class AccentColor: ObservableObject {
        static let shared = AccentColor()

        @Published var current: Color = .blue

        private init() {}

        func set(_ color: Color) {
            current = color
        }
    }
}
