//
//  TerminalLauncher.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-22.
//

import Foundation
import AppKit

enum TerminalLauncherError: LocalizedError {
    case keyFileNotFound(path: String)
    case scriptExecutionFailed(message: String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .keyFileNotFound(let path):
            return "SSH key file not found at: \(path)"
        case .scriptExecutionFailed(let message):
            return "Failed to open terminal: \(message)"
        case .permissionDenied:
            return "Permission denied. Please grant DevDash permission in System Settings > Privacy & Security > Automation."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Go to System Settings > Privacy & Security > Automation, and enable Terminal for DevDash. The SSH command has been copied to your clipboard."
        default:
            return nil
        }
    }
}

class TerminalLauncher {

    /// Opens the system's default Terminal app with an SSH command
    /// - Parameters:
    ///   - host: The hostname or IP address to connect to
    ///   - username: The SSH username
    ///   - keyPath: Path to the SSH private key file
    ///   - customOptions: Additional SSH command options (optional)
    /// - Throws: TerminalLauncherError if validation fails or terminal launch fails
    static func openSSH(host: String, username: String, keyPath: String, customOptions: String = "") throws {
        // Validate SSH key file exists
        let expandedKeyPath = NSString(string: keyPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedKeyPath) else {
            throw TerminalLauncherError.keyFileNotFound(path: expandedKeyPath)
        }

        // Build SSH command
        var command = "ssh -i \"\(expandedKeyPath)\" \(username)@\(host)"
        if !customOptions.isEmpty {
            command += " \(customOptions)"
        }

        // Escape command for AppleScript (escape quotes and backslashes)
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // AppleScript to open Terminal with the SSH command
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        // Execute AppleScript
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)

            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0

                // Check for permission denied error (-1743 is "not authorized")
                if errorNumber == -1743 || errorMessage.contains("not authorized") {
                    // Copy SSH command to clipboard as fallback
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(command, forType: .string)
                    throw TerminalLauncherError.permissionDenied
                }

                throw TerminalLauncherError.scriptExecutionFailed(message: errorMessage)
            }
        } else {
            throw TerminalLauncherError.scriptExecutionFailed(message: "Failed to create AppleScript")
        }
    }
}
