//
//  BackupStatus.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation

/// Status of a single module's backup
struct ModuleBackupStatus: Codable, Identifiable {
    let id: String  // Module ID
    let moduleName: String
    var success: Bool
    var timestamp: Date?
    var errorMessage: String?

    var displayStatus: String {
        if success {
            return "Success"
        } else if let error = errorMessage {
            return "Failed: \(error)"
        } else {
            return "Not backed up"
        }
    }
}

/// Overall backup status tracking
struct BackupStatus: Codable {
    var lastBackupDate: Date?
    var moduleStatuses: [ModuleBackupStatus]

    var successfulModules: [ModuleBackupStatus] {
        moduleStatuses.filter { $0.success }
    }

    var failedModules: [ModuleBackupStatus] {
        moduleStatuses.filter { !$0.success && $0.errorMessage != nil }
    }

    var notBackedUpModules: [ModuleBackupStatus] {
        moduleStatuses.filter { !$0.success && $0.errorMessage == nil }
    }

    var hasAnyBackup: Bool {
        return lastBackupDate != nil
    }

    init() {
        self.lastBackupDate = nil
        self.moduleStatuses = []
    }
}
