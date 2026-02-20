//
//  EC2Models.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation

// MARK: - EC2 Instance

struct EC2Instance: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var instanceId: String
    var lastKnownIP: String?
    var lastFetched: Date?
    var fetchError: String?

    init(id: UUID = UUID(), name: String, instanceId: String, lastKnownIP: String? = nil, lastFetched: Date? = nil, fetchError: String? = nil) {
        self.id = id
        self.name = name
        self.instanceId = instanceId
        self.lastKnownIP = lastKnownIP
        self.lastFetched = lastFetched
        self.fetchError = fetchError
    }
}

// MARK: - Instance Group

struct InstanceGroup: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var region: String
    var awsProfile: String
    var instances: [EC2Instance]

    init(id: UUID = UUID(), name: String, region: String, awsProfile: String, instances: [EC2Instance] = []) {
        self.id = id
        self.name = name
        self.region = region
        self.awsProfile = awsProfile
        self.instances = instances
    }
}
