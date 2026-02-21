//
//  EC2Models.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation

// MARK: - SSH Configuration

struct SSHConfig: Codable, Hashable {
    var username: String
    var keyPath: String
    var customOptions: String

    init(username: String = "ubuntu", keyPath: String = "", customOptions: String = "") {
        self.username = username
        self.keyPath = keyPath
        self.customOptions = customOptions
    }
}

// MARK: - SSH Tunnel

struct SSHTunnel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var localPort: Int
    var remoteHost: String
    var remotePort: Int

    init(id: UUID = UUID(), name: String, localPort: Int, remoteHost: String, remotePort: Int) {
        self.id = id
        self.name = name
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }
}

// MARK: - EC2 Instance

struct EC2Instance: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var instanceId: String
    var lastKnownIP: String?
    var lastFetched: Date?
    var fetchError: String?
    var sshConfig: SSHConfig?
    var tunnels: [SSHTunnel]

    init(id: UUID = UUID(), name: String, instanceId: String, lastKnownIP: String? = nil, lastFetched: Date? = nil, fetchError: String? = nil, sshConfig: SSHConfig? = nil, tunnels: [SSHTunnel] = []) {
        self.id = id
        self.name = name
        self.instanceId = instanceId
        self.lastKnownIP = lastKnownIP
        self.lastFetched = lastFetched
        self.fetchError = fetchError
        self.sshConfig = sshConfig
        self.tunnels = tunnels
    }

    // Custom decoding for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        instanceId = try container.decode(String.self, forKey: .instanceId)
        lastKnownIP = try container.decodeIfPresent(String.self, forKey: .lastKnownIP)
        lastFetched = try container.decodeIfPresent(Date.self, forKey: .lastFetched)
        fetchError = try container.decodeIfPresent(String.self, forKey: .fetchError)
        // Optional fields for backward compatibility
        sshConfig = try container.decodeIfPresent(SSHConfig.self, forKey: .sshConfig)
        tunnels = try container.decodeIfPresent([SSHTunnel].self, forKey: .tunnels) ?? []
    }
}

// MARK: - Instance Group

struct InstanceGroup: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var region: String
    var awsProfile: String
    var instances: [EC2Instance]
    var sshConfig: SSHConfig?

    init(id: UUID = UUID(), name: String, region: String, awsProfile: String, instances: [EC2Instance] = [], sshConfig: SSHConfig? = nil) {
        self.id = id
        self.name = name
        self.region = region
        self.awsProfile = awsProfile
        self.instances = instances
        self.sshConfig = sshConfig
    }

    // Custom decoding for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        region = try container.decode(String.self, forKey: .region)
        awsProfile = try container.decode(String.self, forKey: .awsProfile)
        instances = try container.decode([EC2Instance].self, forKey: .instances)
        // Optional field for backward compatibility
        sshConfig = try container.decodeIfPresent(SSHConfig.self, forKey: .sshConfig)
    }
}
