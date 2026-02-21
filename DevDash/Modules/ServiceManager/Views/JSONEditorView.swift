//
//  JSONEditorView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI
import Combine

struct JSONEditorView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: ServiceManager

    @State private var jsonText: String = ""
    @State private var errorMessage: String?
    @State private var isValidJSON: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Error banner
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding()
                    .background(AppTheme.errorBackground)
                }

                // JSON Editor
                PlainTextEditor(text: $jsonText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: jsonText) { oldValue, newValue in
                        validateJSON()
                    }
            }
            .navigationTitle("Edit Services JSON")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveJSON()
                    }
                    .disabled(!isValidJSON)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            loadJSON()
        }
    }

    func loadJSON() {
        let configs = manager.services.map { $0.config }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        if let jsonData = try? encoder.encode(configs),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            jsonText = jsonString
        }
    }

    func validateJSON() {
        guard let jsonData = jsonText.data(using: .utf8) else {
            errorMessage = "Invalid text encoding"
            isValidJSON = false
            return
        }

        do {
            let _ = try JSONDecoder().decode([ServiceConfig].self, from: jsonData)
            errorMessage = nil
            isValidJSON = true
        } catch {
            errorMessage = "Invalid JSON: \(error.localizedDescription)"
            isValidJSON = false
        }
    }

    func saveJSON() {
        guard let jsonData = jsonText.data(using: .utf8),
              let configs = try? JSONDecoder().decode([ServiceConfig].self, from: jsonData) else {
            return
        }

        // Replace all services with new ones
        // This is a private workaround for JSON editor - normally wouldn't directly access internals
        // but JSONEditor needs to replace everything at once
        for config in configs {
            if manager.getRuntime(id: config.id) == nil {
                manager.addService(config)
            } else {
                if let existingRuntime = manager.getRuntime(id: config.id) {
                    manager.updateService(existingRuntime, with: config)
                }
            }
        }

        // Remove services that are no longer in the JSON
        let newIds = Set(configs.map { $0.id })
        let existingIds = Set(manager.services.map { $0.id })
        let idsToRemove = existingIds.subtracting(newIds)

        for idToRemove in idsToRemove {
            if let index = manager.servicesList.firstIndex(where: { $0.id == idToRemove }) {
                manager.deleteService(at: IndexSet(integer: index))
            }
        }

        dismiss()
    }
}
