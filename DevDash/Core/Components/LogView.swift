//
//  LogView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct LogView: View {
    let logs: String

    @State private var shouldAutoScroll = true
    @State private var searchText = ""

    // Memoized search results — only recomputed when logs or searchText actually change
    @State private var matchCount: Int = 0
    @State private var highlightedText: AttributedString? = nil

    // Debounce timer for search
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))

                TextField("Search in output...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Text("\(matchCount) match\(matchCount == 1 ? "" : "es")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.infoBackground)
                        .cornerRadius(4)

                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(10)
            .background(AppTheme.searchBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppTheme.searchBorder, lineWidth: 1)
            )
            .padding(8)

            // Logs with highlighting
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if searchText.isEmpty {
                            Text(logs)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        } else if let attr = highlightedText {
                            Text(attr)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }

                        // Invisible anchor at bottom
                        AppTheme.clearColor
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.logBackground)
                .onChange(of: logs) { oldValue, newValue in
                    if shouldAutoScroll && searchText.isEmpty {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    if !searchText.isEmpty {
                        debouncedSearch()
                    }
                }
                .onChange(of: searchText) { _, _ in
                    debouncedSearch()
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func debouncedSearch() {
        // Cancel previous search task
        searchDebounceTask?.cancel()

        // Schedule new search after 300ms delay
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                recomputeSearch()
            }
        }
    }

    private func recomputeSearch() {
        guard !searchText.isEmpty else {
            matchCount = 0
            highlightedText = nil
            return
        }
        let lowercasedText = logs.lowercased()
        let lowercasedSearch = searchText.lowercased()
        var count = 0
        var attributed = AttributedString(logs)
        var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex

        while let matchRange = lowercasedText.range(of: lowercasedSearch, range: searchRange) {
            count += 1
            if let lb = AttributedString.Index(matchRange.lowerBound, within: attributed),
               let ub = AttributedString.Index(matchRange.upperBound, within: attributed) {
                attributed[lb..<ub].backgroundColor = .yellow.opacity(0.5)
            }
            searchRange = matchRange.upperBound..<lowercasedText.endIndex
        }

        matchCount = count
        highlightedText = attributed
    }
}
