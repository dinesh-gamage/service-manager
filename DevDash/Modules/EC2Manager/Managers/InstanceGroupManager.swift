//
//  InstanceGroupManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class InstanceGroupManager: ObservableObject {
    @Published var groups: [InstanceGroup] = []
    @Published var isFetching: [UUID: Bool] = [:]

    init() {
        loadGroups()
    }

    func loadGroups() {
        if let data = UserDefaults.standard.data(forKey: "instanceGroups"),
           let decoded = try? JSONDecoder().decode([InstanceGroup].self, from: data) {
            groups = decoded
        } else {
            // Initialize with default groups from scripts
            groups = createDefaultGroups()
            saveGroups()
        }
    }

    func saveGroups() {
        if let encoded = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(encoded, forKey: "instanceGroups")
        }
    }

    func updateInstance(_ groupId: UUID, instanceId: UUID, ip: String, fetchedDate: Date) {
        if let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
           let instanceIndex = groups[groupIndex].instances.firstIndex(where: { $0.id == instanceId }) {
            groups[groupIndex].instances[instanceIndex].lastKnownIP = ip
            groups[groupIndex].instances[instanceIndex].lastFetched = fetchedDate
            saveGroups()
        }
    }

    func fetchInstanceIP(group: InstanceGroup, instance: EC2Instance) {
        isFetching[instance.id] = true

        Task.detached(priority: .userInitiated) {
            let command = "aws-vault exec \(group.awsProfile) -- aws ec2 describe-instances --instance-ids \(instance.instanceId) --region \(group.region) --query 'Reservations[0].Instances[0].PublicIpAddress' --output text"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty,
                   output != "None" {
                    await MainActor.run {
                        self.updateInstance(group.id, instanceId: instance.id, ip: output, fetchedDate: Date())
                        self.isFetching[instance.id] = false
                    }
                } else {
                    await MainActor.run {
                        self.isFetching[instance.id] = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isFetching[instance.id] = false
                }
            }
        }
    }

    private func createDefaultGroups() -> [InstanceGroup] {
        [
            InstanceGroup(
                name: "Lucy",
                region: "ap-southeast-1",
                awsProfile: "lucy-saas",
                instances: [
                    EC2Instance(name: "Web 1", instanceId: "i-0edf0988b5fb37d0e"),
                    EC2Instance(name: "Web 2", instanceId: "i-09881dd5fc0add898"),
                    EC2Instance(name: "Worker", instanceId: "i-0314f5ee633b387aa")
                ]
            ),
            InstanceGroup(
                name: "Sydney",
                region: "ap-southeast-2",
                awsProfile: "lucy-saas",
                instances: [
                    EC2Instance(name: "Web", instanceId: "i-09eee6ce3517cbf37"),
                    EC2Instance(name: "Worker", instanceId: "i-091a50f0fd4710385"),
                    EC2Instance(name: "DB", instanceId: "i-0c4619bfbc09067c6"),
                    EC2Instance(name: "Data Store", instanceId: "i-0cf272c5285040864")
                ]
            ),
            InstanceGroup(
                name: "Canvas",
                region: "ap-southeast-1",
                awsProfile: "lucy-saas",
                instances: [
                    EC2Instance(name: "Web 1", instanceId: "i-049df269560b96012"),
                    EC2Instance(name: "Web 2", instanceId: "i-0bfc23ce6ea6070fa"),
                    EC2Instance(name: "Worker", instanceId: "i-08e462a4548874297"),
                    EC2Instance(name: "DB", instanceId: "i-02ac691d49e45fe31")
                ]
            )
        ]
    }
}
