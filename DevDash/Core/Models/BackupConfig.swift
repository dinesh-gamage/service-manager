//
//  BackupConfig.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation

/// Configuration for S3 backup
struct BackupConfig: Codable {
    var s3Bucket: String
    var s3Path: String  // Path prefix in bucket (e.g., "devdash-backups/")
    var awsProfile: String  // AWS vault profile name

    /// Validate configuration
    var isValid: Bool {
        return !s3Bucket.isEmpty && !s3Path.isEmpty && !awsProfile.isEmpty
    }

    /// Full S3 path for a backup file
    func s3FullPath(for fileName: String) -> String {
        let normalizedPath = s3Path.hasSuffix("/") ? s3Path : s3Path + "/"
        return "s3://\(s3Bucket)/\(normalizedPath)\(fileName)"
    }
}
