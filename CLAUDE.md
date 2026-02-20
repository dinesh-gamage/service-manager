# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DevDash is a native macOS application built with SwiftUI for managing local development workflows. It provides:
1. **Service Management** - Start/stop local development services, view logs, track errors/warnings, handle port conflicts
2. **EC2 Instance IP Tracking** - Fetch and cache public IPs for AWS EC2 instances organized by region/environment groups

## Architecture

### Single-File Architecture
The entire application logic is in `DevDash/ContentView.swift` (~2000 lines). Key components:

**EC2 Models:**
- **EC2Instance** (lines 15-29): Instance name, ID, cached IP, last fetch timestamp
- **InstanceGroup** (lines 31-45): Regional grouping with AWS profile, region, and instances list
- **InstanceGroupManager** (lines 728-838): Manages EC2 groups, fetches IPs via `aws-vault exec` + AWS CLI

**Service Models:**
- **ServiceConfig** (lines 50-90): Codable model representing service configuration (name, command, working directory, port, environment variables)
- **ServiceRuntime** (lines 109-724): ObservableObject managing process lifecycle, log streaming, error/warning parsing, port conflict detection
- **ServiceManager** (lines 840-970): Data layer handling persistence (UserDefaults), import/export (JSON), CRUD operations

**Views:**
- **ContentView** (lines 972-1117): Main split view with dual-section sidebar (Services + EC2 Instances)
- **ServiceDetailView** (lines 1163-1357): Service control panel with logs, errors, warnings
- **InstanceGroupDetailView** (lines 1912-1997): EC2 instance table with IP fetch functionality
- **LogView** (lines 1478-1631): Search-enabled log viewer with debouncing and syntax highlighting

### EC2 Instance Management
Instance groups managed via `InstanceGroupManager`:
- **aws-vault Integration**: Uses `aws-vault exec {profile}` for AWS credential management
- **IP Fetching**: Runs `aws ec2 describe-instances` via AWS CLI asynchronously (Task.detached)
- **Persistence**: Stores groups and last known IPs in UserDefaults with key "instanceGroups"
- **Default Groups**: Lucy (ap-southeast-1), Sydney (ap-southeast-2), Canvas (ap-southeast-1)
- **UI**: Table view showing instance name, ID, cached IP, last fetch time, and fetch button

### Process Management
Services run as shell processes using `/bin/zsh`. The app:
- Streams stdout/stderr via Pipe with live readability handler
- Uses ring buffer for logs (fixed-size, proactive trimming at maxLogLines)
- Parses logs line-by-line for errors/warnings with configurable patterns
- Detects stack traces following error lines
- Uses `lsof` to detect port conflicts
- Can kill conflicting processes and restart

### Log Parsing & Performance
Pattern-based detection:
- Error patterns: "error", "fail", "exception", "panic", "traceback", etc.
- Warning patterns: "warning", "deprecated", "caution", etc.
- Automatic stack trace collection after errors
- LogEntry model stores message, line number, timestamp, type, and optional stack trace
- **Optimizations**: Debounced search (300ms), lazy virtualized rendering, ring buffer storage

## Development Commands

This is a standard Xcode project. No build scripts, tests, or linters are configured.

**Build & Run:**
Open `DevDash.xcodeproj` in Xcode and use Cmd+R to build and run.

**Platform:**
macOS only (uses AppKit for file panels)

**Requirements:**
- macOS 13.0+ (Ventura)
- aws-vault installed and configured with profiles
- AWS CLI v2 installed

## Data Storage

**Services:**
- Persisted to `UserDefaults` with key "services" as JSON-encoded array of `ServiceConfig`
- Import/Export uses JSON format via `NSSavePanel`/`NSOpenPanel`

**EC2 Instance Groups:**
- Persisted to `UserDefaults` with key "instanceGroups" as JSON-encoded array of `InstanceGroup`
- Default groups auto-created on first launch: Lucy, Sydney, Canvas

## Key Behaviors

**Services:**
- Services can only run if ports are free (checked via `lsof`)
- Log parsing happens in real-time as output arrives
- Search in logs highlights matches with yellow background
- Auto-scroll disabled when searching logs
- Import replaces services with matching names, adds new ones

**EC2 Instances:**
- IP fetches run asynchronously (no UI blocking)
- Last known IP and fetch timestamp cached locally
- Manual fetch only (no auto-refresh)
- aws-vault prompts for credentials if session expired
