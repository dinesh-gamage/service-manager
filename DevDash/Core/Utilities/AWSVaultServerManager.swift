//
//  AWSVaultServerManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-22.
//

import Foundation
import AppKit
import Combine

/// Manages aws-vault credential session caching
/// Uses session credentials from aws-vault to reduce keychain prompts
/// Credentials are cached per-profile and refreshed when expired
@MainActor
class AWSVaultServerManager: ObservableObject {
    static let shared = AWSVaultServerManager()

    /// Cached credential session for a profile
    struct CredentialSession {
        let accessKeyId: String
        let secretAccessKey: String
        let sessionToken: String
        let expiration: Date
        let region: String?
    }

    @Published private(set) var activeSessions: [String: CredentialSession] = [:]
    @Published private(set) var sessionErrors: [String: String] = [:]

    // Track if we've already prompted for keychain for a profile this app session
    private var hasPromptedForProfile: Set<String> = []

    private init() {
        setupTerminationHandler()
    }

    // MARK: - Session Management

    /// Get or create a credential session for a profile
    /// This will prompt for keychain password only once per app session
    /// - Parameters:
    ///   - profile: AWS profile name
    ///   - region: AWS region (optional)
    /// - Returns: Credential session if successful, nil otherwise
    func getSession(for profile: String, region: String? = nil) async -> CredentialSession? {
        // Check if we have a valid cached session
        if let session = activeSessions[profile], session.expiration > Date() {
            return session
        }

        // Clear previous errors
        sessionErrors.removeValue(forKey: profile)

        // Fetch new session from aws-vault
        return await fetchNewSession(for: profile, region: region)
    }

    /// Fetch new session credentials from aws-vault
    private func fetchNewSession(for profile: String, region: String?) async -> CredentialSession? {
        return await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")

                // Use aws-vault to export credentials as JSON
                var command = "aws-vault exec \(profile) --json"
                if let region = region {
                    command += " --region \(region)"
                }

                process.arguments = ["-l", "-c", command]
                process.environment = await ProcessEnvironment.shared.getEnvironment()

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if process.terminationStatus == 0, !outputData.isEmpty {
                        // Parse JSON output
                        if let json = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any],
                           let accessKeyId = json["AccessKeyId"] as? String,
                           let secretAccessKey = json["SecretAccessKey"] as? String,
                           let sessionToken = json["SessionToken"] as? String,
                           let expiration = json["Expiration"] as? String {

                            // Parse expiration date (ISO 8601 format)
                            let isoFormatter = ISO8601DateFormatter()
                            let expirationDate = isoFormatter.date(from: expiration) ?? Date().addingTimeInterval(3600)

                            let session = CredentialSession(
                                accessKeyId: accessKeyId,
                                secretAccessKey: secretAccessKey,
                                sessionToken: sessionToken,
                                expiration: expirationDate,
                                region: json["Region"] as? String ?? region
                            )

                            await MainActor.run {
                                self.activeSessions[profile] = session
                                self.hasPromptedForProfile.insert(profile)
                            }

                            continuation.resume(returning: session)
                        } else {
                            await MainActor.run {
                                self.sessionErrors[profile] = "Failed to parse credentials from aws-vault"
                            }
                            continuation.resume(returning: nil)
                        }
                    } else {
                        await MainActor.run {
                            self.sessionErrors[profile] = errorOutput.isEmpty ? "Failed to retrieve credentials" : errorOutput
                        }
                        continuation.resume(returning: nil)
                    }
                } catch {
                    await MainActor.run {
                        self.sessionErrors[profile] = "Process error: \(error.localizedDescription)"
                    }
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Clear session for a profile
    /// - Parameter profile: AWS profile name
    func clearSession(for profile: String) {
        activeSessions.removeValue(forKey: profile)
        sessionErrors.removeValue(forKey: profile)
        hasPromptedForProfile.remove(profile)
    }

    /// Clear all sessions
    func clearAllSessions() {
        activeSessions.removeAll()
        sessionErrors.removeAll()
        hasPromptedForProfile.removeAll()
    }

    // MARK: - Cleanup

    private func setupTerminationHandler() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.clearAllSessions()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
