//
//  CopyableField.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI
import AppKit
import LocalAuthentication

// MARK: - Copyable Field

struct CopyableField: View {
    let value: String
    let label: String?
    let isSecret: Bool
    let monospaced: Bool

    @State private var isHovered = false
    @State private var isRevealed = false
    @State private var showCopied = false

    init(_ value: String, label: String? = nil, isSecret: Bool = false, monospaced: Bool = false) {
        self.value = value
        self.label = label
        self.isSecret = isSecret
        self.monospaced = monospaced
    }

    var body: some View {
        HStack(spacing: 8) {
            // Label (if provided)
            if let label = label {
                Text(label)
                    .foregroundColor(.secondary)
            }

            // Value or masked value
            Group {
                if isSecret && !isRevealed {
                    Text("••••••••")
                        .font(monospaced ? .system(.body, design: .monospaced) : .body)
                } else {
                    Text(value)
                        .font(monospaced ? .system(.body, design: .monospaced) : .body)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            // Action buttons (visible on hover)
            HStack(spacing: 6) {
                // Reveal button (for secrets)
                if isSecret {
                    VariantButton(
                        icon: isRevealed ? "eye.slash" : "eye",
                        variant: .secondary,
                        tooltip: isRevealed ? "Hide" : "Reveal"
                    ) {
                        toggleReveal()
                    }
                    .opacity(isHovered ? 1 : 0)
                }

                // Copy button
                VariantButton(
                    icon: showCopied ? "checkmark" : "doc.on.doc",
                    variant: .secondary,
                    tooltip: showCopied ? "Copied!" : "Copy"
                ) {
                    copyToClipboard()
                }
                .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func toggleReveal() {
        if isRevealed {
            // Hide without authentication
            isRevealed = false
        } else {
            // Reveal with authentication
            authenticateAndReveal()
        }
    }

    private func authenticateAndReveal() {
        let context = LAContext()
        var error: NSError?

        // Check if biometric authentication is available
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Authenticate to reveal this secret"

            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                DispatchQueue.main.async {
                    if success {
                        isRevealed = true
                    }
                }
            }
        } else {
            // Fallback if authentication is not available
            isRevealed = true
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        // Show copied feedback
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }
}

// MARK: - Inline Copyable Text

/// A simple inline text view with copy button on hover (for use in tables and compact spaces)
struct InlineCopyableText: View {
    let text: String
    let monospaced: Bool

    @State private var isHovered = false
    @State private var showCopied = false

    init(_ text: String, monospaced: Bool = false) {
        self.text = text
        self.monospaced = monospaced
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)

            if isHovered {
                VariantButton(
                    icon: showCopied ? "checkmark" : "doc.on.doc",
                    variant: .secondary,
                    tooltip: showCopied ? "Copied!" : "Copy"
                ) {
                    copyToClipboard()
                }
                .scaleEffect(0.8)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }
}
