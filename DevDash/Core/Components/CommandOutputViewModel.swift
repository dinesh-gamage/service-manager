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

    /// Set logs directly and re-parse
    func setLogs(_ content: String) {
        logs = content
        parseLogs()
    }

    /// Parse current logs and update errors/warnings
    func parseLogs() {
        let (parsedErrors, parsedWarnings) = LogParser.parse(logs)
        errors = parsedErrors
        warnings = parsedWarnings
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
