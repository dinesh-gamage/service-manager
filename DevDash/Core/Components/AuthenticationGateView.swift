//
//  AuthenticationGateView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-22.
//

import SwiftUI

struct AuthenticationGateView: View {
    @ObservedObject private var authManager = BiometricAuthManager.shared
    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Blurred background
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            // Auth card
            VStack(spacing: 24) {
                // Icon
                Image(systemName: errorMessage != nil ? "exclamationmark.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.linearGradient(
                        colors: errorMessage != nil ? [.red, .orange] : [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                // Title and description
                VStack(spacing: 8) {
                    Text(errorMessage != nil ? "Authentication Failed" : "Authentication Required")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(errorMessage != nil ? "Please try again to access DevDash" : "Authenticate to access DevDash")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .multilineTextAlignment(.center)
                }

                // Authenticate button
                VariantButton(
                    errorMessage != nil ? "Try Again" : "Authenticate",
                    icon: authManager.biometricTypeName == "Touch ID" ? "touchid" : (authManager.biometricTypeName == "Face ID" ? "faceid" : "lock.fill"),
                    variant: .primary,
                    isLoading: isAuthenticating
                ) {
                    authenticate()
                }
                .disabled(isAuthenticating)

                // Using text
                if errorMessage == nil {
                    Text("Using \(authManager.biometricTypeName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(32)
            .frame(width: 450)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            )
        }
        .onAppear {
            // Auto-trigger authentication on appear only if not already authenticated
            if !authManager.isAuthenticated {
                authenticate()
            }
        }
    }

    private func authenticate() {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        errorMessage = nil

        Task {
            do {
                try await authManager.authenticate(reason: "Authenticate to access DevDash")
                // Authentication successful - gate will auto-dismiss via authManager.isAuthenticated
                await MainActor.run {
                    isAuthenticating = false
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false

                    // Set error message based on error type
                    if let bioError = error as? BiometricAuthError {
                        switch bioError {
                        case .userCancelled:
                            errorMessage = "Authentication cancelled"
                        case .authenticationFailed:
                            errorMessage = "Authentication failed - incorrect credentials"
                        case .notAvailable:
                            errorMessage = "Biometric authentication not available"
                        case .biometricNotEnrolled:
                            errorMessage = "No biometric data enrolled"
                        case .passcodeNotSet:
                            errorMessage = "Passcode not set on this device"
                        case .systemCancelled:
                            errorMessage = "Authentication was cancelled by the system"
                        case .unknown(let underlyingError):
                            errorMessage = underlyingError.localizedDescription
                        }
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
