//
//  ImportExportManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// Errors that can occur during import
enum ImportError: Error, LocalizedError {
    case userCancelled
    case noFileSelected
    case fileReadFailed
    case jsonDecodeFailed
    case noItemsImported

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Import cancelled"
        case .noFileSelected:
            return "Failed to get file path."
        case .fileReadFailed:
            return "Failed to read file. Please check the file exists and is readable."
        case .jsonDecodeFailed:
            return "Failed to parse JSON. Please check the file format is correct."
        case .noItemsImported:
            return "No items were imported from the file."
        }
    }
}

/// Result of an import operation
struct ImportResult<T> {
    let items: [T]
    let newCount: Int
    let updatedCount: Int

    var message: String {
        if newCount > 0 && updatedCount > 0 {
            return "Imported \(newCount) new item(s) and updated \(updatedCount) existing item(s)."
        } else if newCount > 0 {
            return "Imported \(newCount) new item(s)."
        } else if updatedCount > 0 {
            return "Updated \(updatedCount) existing item(s)."
        } else {
            return "No changes made."
        }
    }
}

/// Generic import/export manager for JSON files
class ImportExportManager {
    static let shared = ImportExportManager()

    private init() {}

    /// Import items from JSON file with file picker
    /// - Parameters:
    ///   - type: Type of items to import
    ///   - title: Dialog title
    ///   - completion: Completion handler called on main thread with Result
    func importJSON<T: Codable>(
        _ type: T.Type,
        title: String = "Import",
        completion: @escaping (Result<[T], ImportError>) -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.title = title

        openPanel.begin { response in
            // User cancelled
            guard response == .OK else {
                DispatchQueue.main.async {
                    completion(.failure(.userCancelled))
                }
                return
            }

            // Get URL
            guard let url = openPanel.url else {
                DispatchQueue.main.async {
                    completion(.failure(.noFileSelected))
                }
                return
            }

            // Read file
            guard let jsonData = try? Data(contentsOf: url) else {
                DispatchQueue.main.async {
                    completion(.failure(.fileReadFailed))
                }
                return
            }

            // Decode JSON
            guard let decoded = try? JSONDecoder().decode([T].self, from: jsonData) else {
                DispatchQueue.main.async {
                    completion(.failure(.jsonDecodeFailed))
                }
                return
            }

            // Success - return on main thread
            DispatchQueue.main.async {
                completion(.success(decoded))
            }
        }
    }

    /// Export items to JSON file with file picker
    /// - Parameters:
    ///   - items: Items to export
    ///   - defaultFileName: Default filename for save dialog
    ///   - title: Dialog title
    ///   - completion: Optional completion handler called on main thread with Result
    func exportJSON<T: Codable>(
        _ items: [T],
        defaultFileName: String = "export.json",
        title: String = "Export",
        completion: ((Result<Void, ImportError>) -> Void)? = nil
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let jsonData = try? encoder.encode(items),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            DispatchQueue.main.async {
                completion?(.failure(.jsonDecodeFailed))
            }
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = defaultFileName
        savePanel.title = title

        savePanel.begin { response in
            guard response == .OK else {
                DispatchQueue.main.async {
                    completion?(.failure(.userCancelled))
                }
                return
            }

            guard let url = savePanel.url else {
                DispatchQueue.main.async {
                    completion?(.failure(.noFileSelected))
                }
                return
            }

            do {
                try jsonString.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    completion?(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion?(.failure(.fileReadFailed))
                }
            }
        }
    }
}
