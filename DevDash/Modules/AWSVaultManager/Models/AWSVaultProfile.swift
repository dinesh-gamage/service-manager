//
//  AWSVaultProfile.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import Foundation

struct AWSVaultProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var region: String?
    var description: String?
    let createdAt: Date
    var lastModified: Date
    var awsVaultBinaryHash: String? // SHA256 hash of aws-vault binary used to create credentials

    init(id: UUID = UUID(), name: String, region: String? = nil, description: String? = nil, awsVaultBinaryHash: String? = nil) {
        self.id = id
        self.name = name
        self.region = region
        self.description = description
        self.createdAt = Date()
        self.lastModified = Date()
        self.awsVaultBinaryHash = awsVaultBinaryHash
    }
}
