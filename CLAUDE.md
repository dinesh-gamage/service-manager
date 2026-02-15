# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ServiceManager is a native macOS application built with SwiftUI that manages local development services. It provides a GUI to start/stop services, view logs, track errors/warnings, and handle port conflicts.

## Architecture

### Single-File Architecture
The entire application logic is in `ServiceManager/ContentView.swift` (~1200 lines). Key components:

- **ServiceConfig** (lines 16-32): Codable model representing service configuration (name, command, working directory, port, environment variables)
- **ServiceRuntime** (lines 52-354): ObservableObject managing process lifecycle, log streaming, error/warning parsing, port conflict detection
- **ServiceManager** (lines 358-471): Data layer handling persistence (UserDefaults), import/export (JSON), CRUD operations
- **Views** (lines 475-1191): SwiftUI views including ContentView (main split view), ServiceDetailView, LogView with search, AddServiceView, EditServiceView

### Process Management
Services run as shell processes using `/bin/zsh`. The app:
- Streams stdout/stderr via Pipe with live readability handler (lines 205-220)
- Parses logs line-by-line for errors/warnings with configurable patterns (lines 87-162)
- Detects stack traces following error lines (lines 100-113)
- Uses `lsof` to detect port conflicts (lines 249-284)
- Can kill conflicting processes and restart (lines 293-318)

### Log Parsing
Pattern-based detection (lines 116-161):
- Error patterns: "error", "fail", "exception", "panic", "traceback", etc.
- Warning patterns: "warning", "deprecated", "caution", etc.
- Automatic stack trace collection after errors
- LogEntry model stores message, line number, timestamp, type, and optional stack trace

## Development Commands

This is a standard Xcode project. No build scripts, tests, or linters are configured.

**Build & Run:**
Open `ServiceManager.xcodeproj` in Xcode and use Cmd+R to build and run.

**Platform:**
macOS only (uses AppKit for file panels)

## Data Storage

Service configurations are persisted to `UserDefaults` with key "services" as JSON-encoded array of `ServiceConfig`.

Import/Export uses JSON format via `NSSavePanel`/`NSOpenPanel` for file system access.

## Key Behaviors

- Services can only run if ports are free (checked via `lsof`)
- Log parsing happens in real-time as output arrives
- Search in logs highlights matches with yellow background
- Auto-scroll disabled when searching logs
- Import replaces services with matching names, adds new ones
