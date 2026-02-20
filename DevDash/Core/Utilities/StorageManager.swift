//
//  StorageManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation

/// Generic UserDefaults storage manager for Codable types
class StorageManager {
    static let shared = StorageManager()

    private init() {}

    /// Save array of Codable items to UserDefaults
    /// - Parameters:
    ///   - items: Array of items to save
    ///   - key: UserDefaults key
    /// - Returns: True if save succeeded, false otherwise
    @discardableResult
    func save<T: Codable>(_ items: [T], forKey key: String) -> Bool {
        guard let encoded = try? JSONEncoder().encode(items) else {
            return false
        }
        UserDefaults.standard.set(encoded, forKey: key)
        return true
    }

    /// Load array of Codable items from UserDefaults
    /// - Parameter key: UserDefaults key
    /// - Returns: Array of items, or nil if not found or decode failed
    func load<T: Codable>(forKey key: String) -> [T]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([T].self, from: data) else {
            return nil
        }
        return decoded
    }

    /// Remove data for key
    /// - Parameter key: UserDefaults key
    func remove(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
