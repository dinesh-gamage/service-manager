//
//  InstanceGroupJSONEditorView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI
import Combine

struct InstanceGroupJSONEditorView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: InstanceGroupManager

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
            .navigationTitle("Edit Instance Groups JSON")
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        if let jsonData = try? encoder.encode(manager.groups),
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
            let _ = try JSONDecoder().decode([InstanceGroup].self, from: jsonData)
            errorMessage = nil
            isValidJSON = true
        } catch {
            errorMessage = "Invalid JSON: \(error.localizedDescription)"
            isValidJSON = false
        }
    }

    func saveJSON() {
        guard let jsonData = jsonText.data(using: .utf8),
              let groups = try? JSONDecoder().decode([InstanceGroup].self, from: jsonData) else {
            return
        }

        // Replace all groups with new ones
        manager.groups = groups
        manager.saveGroups()
        manager.objectWillChange.send()

        dismiss()
    }
}
