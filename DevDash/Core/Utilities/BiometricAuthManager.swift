//
//  BiometricAuthManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation
import LocalAuthentication
import Combine
import AppKit

enum BiometricAuthError: Error, LocalizedError {
    case notAvailable
    case authenticationFailed
    case userCancelled
    case systemCancelled
    case passcodeNotSet
    case biometricNotEnrolled
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available"
        case .authenticationFailed:
            return "Authentication failed"
        case .userCancelled:
            return "Authentication was cancelled"
        case .systemCancelled:
            return "System cancelled authentication"
        case .passcodeNotSet:
            return "Passcode is not set on this device"
        case .biometricNotEnrolled:
            return "No biometric data enrolled"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

@MainActor
class BiometricAuthManager: ObservableObject {
    static let shared = BiometricAuthManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var biometricType: LABiometryType = .none

    private var context = LAContext()
    private var sessionStartTime: Date?
    private var isAuthenticating = false  // Track if authentication is in progress

    private init() {
        checkBiometricType()
        setupSessionInvalidation()
    }

    // MARK: - Biometric Availability

    private func checkBiometricType() {
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            biometricType = context.biometryType
        } else {
            biometricType = .none
        }
    }

    var isDevicePasswordAvailable: Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    var biometricTypeName: String {
        switch biometricType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Device Password"
        @unknown default:
            return "Biometric"
        }
    }

    // MARK: - Authentication

    /// Authenticate user with biometric or device password
    func authenticate(reason: String = "Authenticate to access credentials") async throws {
        // Check if already authenticated in this session
        if isAuthenticated {
            return
        }

        // Reset context to avoid reuse issues
        context = LAContext()
        context.localizedCancelTitle = "Cancel"

        // Always use deviceOwnerAuthentication on macOS for better UX
        // This automatically uses Touch ID if available, with password fallback
        let policy: LAPolicy = .deviceOwnerAuthentication

        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            if let error = error {
                throw mapLAError(error)
            }
            throw BiometricAuthError.notAvailable
        }

        // Set flag before authentication starts
        isAuthenticating = true

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)

            if success {
                isAuthenticated = true
                sessionStartTime = Date()
            } else {
                isAuthenticating = false  // Clear flag on failure
                throw BiometricAuthError.authenticationFailed
            }

            isAuthenticating = false  // Clear flag on success
        } catch let laError as LAError {
            isAuthenticating = false  // Clear flag on error
            throw mapLAError(laError)
        } catch {
            isAuthenticating = false  // Clear flag on error
            throw BiometricAuthError.unknown(error)
        }
    }

    /// Verify authentication is still valid for this session
    func verifyAuthentication(reason: String = "Authenticate to access credentials") async throws {
        if isAuthenticated {
            return
        }
        try await authenticate(reason: reason)
    }

    /// Invalidate current session
    func invalidateSession() {
        // Don't invalidate if authentication is in progress
        // This prevents the auth dialog from being cancelled when it takes focus
        if isAuthenticating {
            return
        }

        isAuthenticated = false
        sessionStartTime = nil
        context.invalidate()
    }

    // MARK: - Session Management

    private func setupSessionInvalidation() {
        // Invalidate session when app goes to background
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateSession()
        }

        // Invalidate session when app terminates
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateSession()
        }
    }

    // MARK: - Error Mapping

    private func mapLAError(_ error: Error) -> BiometricAuthError {
        guard let laError = error as? LAError else {
            return .unknown(error)
        }

        switch laError.code {
        case .authenticationFailed:
            return .authenticationFailed
        case .userCancel:
            return .userCancelled
        case .systemCancel:
            return .systemCancelled
        case .passcodeNotSet:
            return .passcodeNotSet
        case .biometryNotEnrolled:
            return .biometricNotEnrolled
        default:
            return .unknown(error)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
