# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DevDash is a native macOS application built with SwiftUI for managing local development workflows. It provides:
1. **Service Management** - Start/stop local development services, view logs, track errors/warnings, handle port conflicts
2. **EC2 Instance IP Tracking** - Fetch and cache public IPs for AWS EC2 instances organized by region/environment groups
3. **Credentials Management** - Secure credential storage with Apple Keychain and biometric authentication

## Development Rules

**These rules override all other considerations:**

1. **Performance First** - This app must remain lightweight with zero performance impact. Prevent memory leaks, ensure proper garbage collection, and clean up all resources (processes, tasks, observers). Profile memory usage for any significant changes.

2. **No Guessing, No Patronizing** - If you don't know or are unsure about implementation details, say so explicitly. Do not make assumptions. Ask clarifying questions before proceeding.

3. **Keep it DRY** - Eliminate code duplication. Extract shared logic to Core utilities. Reuse existing components before creating new ones.

4. **User-Friendly & Intuitive** - Design simple, clear interfaces. Provide immediate visual feedback. Make actions reversible where possible. Minimize cognitive load.

## Architecture

### Modular System
The app uses a **module-based architecture** where each feature is an independent, self-contained module:

**Module Protocol** (`Core/Models/Module.swift`):
- **DevDashModule** (lines 13-25): Protocol defining module interface (id, name, icon, accentColor, sidebar/detail views)
- **ModuleRegistry** (lines 29-46): Singleton managing module registration and lookup

**Current Modules:**
- **ServiceManagerModule** (`Modules/ServiceManager/`) - Service lifecycle management
- **EC2ManagerModule** (`Modules/EC2Manager/`) - AWS EC2 instance IP tracking
- **CredentialsManagerModule** (`Modules/CredentialsManager/`) - Secure credential storage

### Directory Structure
```
DevDash/
├── Core/                     # Shared infrastructure
│   ├── Models/              # Module protocol, registry
│   ├── Components/          # Reusable UI (buttons, forms, logs, etc.)
│   ├── Theme/              # AppTheme, typography, colors
│   ├── Utilities/          # Helpers (LogParser, StorageManager, etc.)
│   └── Protocols/          # Shared interfaces
├── Modules/                 # Feature modules
│   ├── ServiceManager/
│   └── EC2Manager/
├── ContentView.swift        # Root navigation
└── DevDashApp.swift        # App entry + module registration
```

### Service Manager Module

Key components in `Modules/ServiceManager/`:

**ServiceManagerModule.swift**:
- **ServiceManagerState**: Singleton @ObservableObject managing module state, alerts, selected service
- **ServiceManagerSidebarView**: Toolbar + service list with add/edit/delete/import/export
- **ServiceManagerDetailView**: Detail pane showing selected service or empty state

**Models/ServiceModels.swift**:
- **ServiceConfig**: Codable config model (name, command, workingDir, port, env vars)

**Runtime/ServiceRuntime.swift**:
- **ServiceRuntime**: ObservableObject managing process lifecycle, log streaming, error/warning parsing
- Runs services as `/bin/zsh` processes with Pipe-based stdout/stderr streaming
- Ring buffer for logs with proactive trimming at maxLogLines
- Real-time log parsing for errors/warnings with stack trace detection

**Managers/ServiceManager.swift**:
- **ServiceManager**: Data layer handling persistence (UserDefaults), import/export (JSON), CRUD operations
- Stores services in UserDefaults with key "services"

**Views/**:
- **ServiceDetailView**: Control panel with start/stop, logs, errors, warnings tabs
- **ServiceListItem**: Sidebar list item with status indicators
- **AddServiceView, EditServiceView**: Forms for service CRUD
- **JSONEditorView**: Direct JSON editing with validation

### EC2 Manager Module

Key components in `Modules/EC2Manager/`:

**EC2ManagerModule.swift**:
- **EC2ManagerState**: Singleton managing groups, selected group, instance CRUD operations
- **EC2ManagerSidebarView**: Toolbar + instance group list with add/edit/delete/import/export
- **EC2ManagerDetailView**: Detail pane for selected group

**Models/EC2Models.swift**:
- **EC2Instance**: Instance name, ID, cached IP, last fetch timestamp, fetch error
- **InstanceGroup**: Regional grouping with AWS profile, region, instances list

**Managers/InstanceGroupManager.swift**:
- Manages EC2 groups with aws-vault integration via `aws-vault exec {profile}`
- Runs `aws ec2 describe-instances` asynchronously (Task.detached)
- Stores groups in UserDefaults with key "instanceGroups"
- Default groups: Lucy (ap-southeast-1), Sydney (ap-southeast-2), Canvas (ap-southeast-1)

**Views/**:
- **InstanceGroupDetailView**: Table showing instance name, ID, cached IP, last fetch time, fetch button
- **AddInstanceGroupView, EditInstanceGroupView**: Group CRUD forms
- **AddInstanceView, EditInstanceView**: Instance CRUD forms
- **InstanceGroupJSONEditorView**: Direct JSON editing

### Credentials Manager Module

Key components in `Modules/CredentialsManager/`:

**CredentialsManagerModule.swift**:
- **CredentialsManagerState**: Singleton managing credentials, auth state, revealed passwords/fields
- **CredentialsManagerSidebarView**: Category filter, search bar, credential list
- **CredentialsManagerDetailView**: Detail pane for selected credential

**Models/CredentialModels.swift**:
- **Credential**: Title, category, username, password (Keychain key), custom fields, notes
- **CredentialField**: Custom field with key, value, isSecret flag
- **CredentialCategory**: Predefined categories (Databases, API Keys, SSH, etc.)

**Managers/CredentialsManager.swift**:
- Manages credential CRUD operations
- Coordinates between UserDefaults (metadata) and Keychain (secrets)
- Import/Export functionality (metadata only, no passwords)
- Search and filter logic

**Views/**:
- **CredentialDetailView**: Shows credential with reveal/hide toggles and copy buttons
- **AddCredentialView**: Form for creating new credentials with password confirmation
- **EditCredentialView**: Form for editing credentials with optional password update
- **CredentialListItem**: Sidebar item with category icon and metadata

### Core Infrastructure

**Process Management** (ServiceRuntime):
- Services run as `/bin/zsh` processes
- Streams stdout/stderr via Pipe with live readability handler
- Ring buffer storage with fixed size and proactive trimming
- Pattern-based error/warning detection
- Automatic stack trace collection after errors
- Port conflict detection via `lsof`
- Process termination and restart capabilities

**Reusable UI Components** (`Core/Components/`):
- **VariantComponents**: Buttons with primary/danger/ghost variants
- **FormComponents**: Form fields, labels, text editors
- **ServiceOutputPanel**: Log viewer with search and error/warning tabs
- **LogView**: Virtualized log rendering with syntax highlighting
- **CopyableField**: One-click copy text fields
- **RelativeTimeText**: Auto-updating relative timestamps
- **ErrorWarningListView**: Shared error/warning list display
- **ModuleDetailHeader**: Standard header for module detail views
- **ModuleSidebarList**: Reusable sidebar list with toolbar

**Utilities** (`Core/Utilities/`):
- **LogParser**: Real-time error/warning detection with pattern matching
  - Error patterns: "error", "fail", "exception", "panic", "traceback", etc.
  - Warning patterns: "warning", "deprecated", "caution", etc.
  - Automatic stack trace collection after errors
- **ProcessEnvironment**: Shell environment variable resolution
- **StorageManager**: UserDefaults persistence layer with Codable support
- **ImportExportManager**: JSON import/export with file panels (NSSavePanel/NSOpenPanel)
- **AlertQueue**: Sequential alert presentation to prevent overlapping dialogs
- **KeychainManager**: Secure storage wrapper for Apple Keychain Services API
  - Save/retrieve/delete operations
  - Support for String and Data types
  - Error handling with KeychainError enum
- **BiometricAuthManager**: LocalAuthentication integration
  - Touch ID/Face ID/Password authentication
  - Session-based authentication caching
  - Session invalidation on app background/terminate
- **AWSVaultManager**: AWS vault profile management
  - Profile metadata storage (name, region, description)
  - Shell integration with aws-vault CLI
  - Async credential operations

**Theme System** (`Core/Theme/AppTheme.swift`):
- Centralized typography (h1, h2, h3, body, caption)
- Color palette with gradient support
- Responsive accent color switching per module

**Performance Optimizations**:
- Debounced search (300ms delay)
- Lazy virtualized log rendering
- Ring buffer storage for logs (fixed size, automatic trimming)
- Async operations for shell commands and AWS CLI calls
- Proper resource cleanup (processes, tasks, observers)

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
