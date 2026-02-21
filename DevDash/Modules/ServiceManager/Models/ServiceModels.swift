//
//  ServiceModels.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation

// MARK: - Prerequisite Command

struct PrerequisiteCommand: Codable, Identifiable {
    let id: UUID
    var command: String
    var delay: Int
    var isRequired: Bool

    init(id: UUID = UUID(), command: String, delay: Int = 0, isRequired: Bool = false) {
        self.id = id
        self.command = command
        self.delay = delay
        self.isRequired = isRequired
    }
}

// MARK: - Service Configuration

struct ServiceConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var command: String
    var workingDirectory: String
    var port: Int?
    var environment: [String: String]
    var prerequisites: [PrerequisiteCommand]?
    var checkCommand: String?
    var stopCommand: String?
    var restartCommand: String?
    var maxLogLines: Int?

    init(id: UUID = UUID(), name: String, command: String, workingDirectory: String, port: Int? = nil, environment: [String: String] = [:], prerequisites: [PrerequisiteCommand]? = nil, checkCommand: String? = nil, stopCommand: String? = nil, restartCommand: String? = nil, maxLogLines: Int? = 1000) {
        self.id = id
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.port = port
        self.environment = environment
        self.prerequisites = prerequisites
        self.checkCommand = checkCommand
        self.stopCommand = stopCommand
        self.restartCommand = restartCommand
        self.maxLogLines = maxLogLines
    }
}

// MARK: - Service Action

enum ServiceAction: Equatable {
    case starting
    case stopping
    case restarting
    case killingAndRestarting
}

// MARK: - Service Info (Lightweight ViewModel)

struct ServiceInfo: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let isRunning: Bool
    let isExternallyManaged: Bool
    let hasPortConflict: Bool
    let processingAction: ServiceAction?
    let port: Int?
    let workingDirectory: String
    let command: String
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let lineNumber: Int
    let timestamp: Date
    let type: LogType
    var stackTrace: [String]?

    enum LogType {
        case error
        case warning
    }
}
