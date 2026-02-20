//
//  OutputViewDataSource.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import Foundation

/// Protocol for objects that provide output data for CommandOutputView
protocol OutputViewDataSource: ObservableObject {
    var logs: String { get }
    var errors: [LogEntry] { get }
    var warnings: [LogEntry] { get }

    func clearErrors()
    func clearWarnings()
}
