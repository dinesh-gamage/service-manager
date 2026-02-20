//
//  LogParser.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation

struct LogParser {

    // Static pattern arrays (public for reuse)
    static let errorPatterns: [String] = [
        "error", "err", "fatal", "fail", "failed", "failure",
        "exception", "panic", "critical", "severe", "cannot",
        "unable to", "not found", "invalid", "undefined",
        "traceback", "stacktrace"
    ]

    static let warningPatterns: [String] = [
        "warning", "warn", "deprecated", "obsolete", "caution",
        "notice", "should", "recommend", "may cause"
    ]

    // Pre-compiled regex for stack trace numeric-line detection
    static let stackTraceLineRegex = /^\s*\d+\s+/

    /// Parse logs and extract errors and warnings with stack traces
    /// - Parameter logs: The full log string to parse
    /// - Returns: Tuple of (errors, warnings) as arrays of LogEntry
    static func parse(_ logs: String) -> (errors: [LogEntry], warnings: [LogEntry]) {
        var errors: [LogEntry] = []
        var warnings: [LogEntry] = []

        var lineNumber = 0
        var collectingStackTrace = false
        var currentStackTrace: [String] = []

        let lines = logs.components(separatedBy: .newlines)

        for line in lines {
            lineNumber += 1
            let lowercased = line.lowercased()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines
            guard !trimmed.isEmpty else { continue }

            // Stack trace line patterns (indented, starts with "at ", frame info, etc.)
            let isStackTraceLine = line.hasPrefix("    ") ||
                                   line.hasPrefix("\t") ||
                                   trimmed.hasPrefix("at ") ||
                                   trimmed.contains("(") && trimmed.contains(")") && trimmed.contains(":") ||
                                   trimmed.hasPrefix("File ") ||
                                   trimmed.contains(stackTraceLineRegex)

            // If we're collecting a stack trace
            if collectingStackTrace {
                if isStackTraceLine && !trimmed.isEmpty {
                    currentStackTrace.append(trimmed)
                    continue
                } else {
                    // Stack trace ended, attach to last error
                    if !currentStackTrace.isEmpty, !errors.isEmpty {
                        errors[errors.count - 1].stackTrace = currentStackTrace
                    }
                    collectingStackTrace = false
                    currentStackTrace = []
                }
            }

            // Check for errors
            var foundError = false
            for pattern in errorPatterns {
                if lowercased.contains(pattern) {
                    let entry = LogEntry(
                        message: trimmed,
                        lineNumber: lineNumber,
                        timestamp: Date(),
                        type: .error,
                        stackTrace: nil
                    )
                    errors.append(entry)
                    collectingStackTrace = true
                    currentStackTrace = []
                    foundError = true
                    break
                }
            }

            if foundError { continue }

            // Check for warnings
            for pattern in warningPatterns {
                if lowercased.contains(pattern) {
                    let entry = LogEntry(
                        message: trimmed,
                        lineNumber: lineNumber,
                        timestamp: Date(),
                        type: .warning,
                        stackTrace: nil
                    )
                    warnings.append(entry)
                    break
                }
            }
        }

        // Attach any remaining stack trace to the last error
        if collectingStackTrace && !currentStackTrace.isEmpty && !errors.isEmpty {
            errors[errors.count - 1].stackTrace = currentStackTrace
        }

        return (errors, warnings)
    }
}
