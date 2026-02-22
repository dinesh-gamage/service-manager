//
//  ProcessEnvironment.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation
import SwiftUI

/// Manages process environment variables, particularly resolving the user's actual shell PATH
/// macOS GUI apps don't inherit the user's shell PATH from .zshrc/.zprofile
/// This utility discovers and caches the user's PATH on first access
class ProcessEnvironment {
    static let shared = ProcessEnvironment()

    private var cachedUserPath: String?
    private let lock = NSLock()

    private init() {}

    /// Get the user's actual PATH from their login shell
    /// This is cached after first access for performance
    private func getUserPath() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedUserPath {
            return cached
        }

        // Discover PATH by running a login shell
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "echo $PATH"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            // Explicitly close pipe to release file handle immediately
            try? pipe.fileHandleForReading.close()

            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                cachedUserPath = path
                return path
            }
        } catch {
            // Ensure pipe is closed even on error
            try? pipe.fileHandleForReading.close()
            // Fall back to ProcessInfo if discovery fails
        }

        // Fallback: use ProcessInfo's PATH (will be limited to system defaults)
        let fallbackPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        cachedUserPath = fallbackPath
        return fallbackPath
    }

    /// Get environment dictionary with user's actual PATH and optional additional variables
    /// - Parameter additionalVars: Optional dictionary of additional environment variables to merge
    /// - Returns: Environment dictionary suitable for Process.environment
    func getEnvironment(additionalVars: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = getUserPath()

        // Merge additional variables (these override any existing)
        for (key, value) in additionalVars {
            env[key] = value
        }

        return env
    }

    /// Get environment dictionary with AWS vault credentials for a specific profile
    /// This method retrieves cached session credentials from aws-vault
    /// Prompts for keychain password only once per app session
    /// - Parameters:
    ///   - profile: AWS profile name to use for credentials
    ///   - region: AWS region (optional)
    /// - Returns: Environment dictionary with AWS credentials, or base environment if session fetch fails
    @MainActor
    func getEnvironment(withAWSProfile profile: String, region: String? = nil) async -> [String: String] {
        // Get session credentials from vault manager
        if let session = await AWSVaultServerManager.shared.getSession(for: profile, region: region) {
            var awsEnv: [String: String] = [
                "AWS_ACCESS_KEY_ID": session.accessKeyId,
                "AWS_SECRET_ACCESS_KEY": session.secretAccessKey,
                "AWS_SESSION_TOKEN": session.sessionToken
            ]

            if let region = session.region {
                awsEnv["AWS_REGION"] = region
                awsEnv["AWS_DEFAULT_REGION"] = region
            }

            return getEnvironment(additionalVars: awsEnv)
        }

        // Fallback to base environment if session fetch failed
        return getEnvironment()
    }
}
