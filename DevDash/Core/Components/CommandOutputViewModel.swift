//
//  CommandOutputViewModel.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class CommandOutputViewModel: ObservableObject, OutputViewDataSource {

    @Published var logs: String = ""
    @Published var errors: [LogEntry] = []
    @Published var warnings: [LogEntry] = []

    // Cache last parsed logs to avoid re-parsing same content
    private var lastParsedLogs: String = ""

    /// Initialize with optional initial logs
    init(logs: String = "") {
        self.logs = logs
        if !logs.isEmpty {
            parseLogs()
        }
    }

    /// Append new log content and re-parse
    func appendLog(_ content: String) {
        logs += content
        parseLogs()
    }

    /// Set logs directly and re-parse only if content changed
    func setLogs(_ content: String) {
        // Skip parsing if content hasn't changed
        guard content != lastParsedLogs else {
            // Still update logs in case it's observed elsewhere
            logs = content
            return
        }

        logs = content
        parseLogs()
    }

    /// Parse current logs and update errors/warnings
    func parseLogs() {
        // Skip if already parsed this exact content
        guard logs != lastParsedLogs else { return }

        let (parsedErrors, parsedWarnings) = LogParser.parse(logs)
        errors = parsedErrors
        warnings = parsedWarnings
        lastParsedLogs = logs
    }

    /// Clear all errors
    func clearErrors() {
        errors.removeAll()
    }

    /// Clear all warnings
    func clearWarnings() {
        warnings.removeAll()
    }

    /// Clear all logs, errors, and warnings
    func clearAll() {
        logs = ""
        errors.removeAll()
        warnings.removeAll()
    }
}
