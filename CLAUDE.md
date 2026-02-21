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

5. **Event-Driven Architecture** - Follow the established event-driven pattern (detailed below). NEVER use manual refresh triggers or polling. Let SwiftUI's reactive system handle updates automatically.

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

### Event-Driven Architecture & State Management

**CRITICAL: This pattern must be followed for all modules to prevent performance issues.**

#### The Problem We Solved

Initial implementation had severe performance issues:
- **100% CPU usage** from infinite rendering loops
- **Constant re-renders** when observing objects with frequently updating properties (logs updating 10x/second)
- **UI not updating** when nested ObservableObject changes occurred
- **Manual refresh hacks** using `listRefreshTrigger = UUID()` and `objectWillChange.send()`

#### The Solution: Lightweight State Pattern with Event Forwarding

All modules now follow this architecture:

```
┌─────────────────────────────────────────────────────────┐
│ ModuleState (ObservableObject)                          │
│ - Singleton, holds UI state                             │
│ - Forwards manager.objectWillChange to self             │
│ - Views observe this                                     │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ Manager (ObservableObject)                              │
│ - Publishes LIGHTWEIGHT list (ServiceInfo, not Runtime) │
│ - Handles CRUD, persistence, import/export              │
│ - Private full objects (with logs, processes, etc.)     │
│ - Public lightweight snapshots for UI                   │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ Runtime/Heavy Objects (ObservableObject)                │
│ - Logs, processes, frequently updating data             │
│ - NOT exposed to list views                             │
│ - Fetched on-demand via manager.getRuntime(id)          │
│ - Only detail views observe these                       │
└─────────────────────────────────────────────────────────┘
```

#### Mandatory Rules

**DO:**

1. **Use Combine forwarding for nested ObservableObjects**:
   ```swift
   @MainActor
   class ModuleState: ObservableObject {
       @Published var manager: Manager
       private var cancellables = Set<AnyCancellable>()

       private init() {
           self.manager = Manager(...)

           // REQUIRED: Forward manager changes to state
           manager.objectWillChange.sink { [weak self] _ in
               self?.objectWillChange.send()
           }
           .store(in: &cancellables)
       }
   }
   ```

2. **Separate lightweight state from heavy runtime data**:
   ```swift
   // Lightweight - safe for list views
   struct ServiceInfo: Identifiable {
       let id: UUID
       let name: String
       let isRunning: Bool
       let port: Int?
       // NO logs, NO processes, NO frequently updating data
   }

   // Manager exposes lightweight list
   @MainActor
   class Manager: ObservableObject {
       @Published var servicesList: [ServiceInfo] = []
       private var runtimes: [UUID: ServiceRuntime] = [:]

       func getRuntime(id: UUID) -> ServiceRuntime? {
           return runtimes[id]
       }
   }
   ```

3. **Subscribe to runtime changes to auto-refresh list**:
   ```swift
   private func subscribeToRuntime(_ runtime: ServiceRuntime) {
       runtime.objectWillChange.sink { [weak self] _ in
           self?.refreshServicesList()
       }
       .store(in: &cancellables)
   }

   func refreshServicesList() {
       servicesList = runtimes.values.map { runtime in
           ServiceInfo(/* map only lightweight properties */)
       }
   }
   ```

4. **Let @Published trigger updates automatically** - Never manually call `objectWillChange.send()` in CRUD methods

5. **Use on-demand fetching for heavy data**:
   ```swift
   // In detail view
   if let runtime = manager.getRuntime(id: serviceInfo.id) {
       runtime.start()
   }
   ```

**DO NOT:**

1. ❌ **NEVER observe objects with frequently updating @Published properties in list views**:
   ```swift
   // WRONG - logs update 10x/second, causes constant re-renders
   struct ServiceRow: View {
       @ObservedObject var service: ServiceRuntime
   }

   // CORRECT - lightweight, stable data
   struct ServiceRow: View {
       let serviceInfo: ServiceInfo
       let manager: ServiceManager
   }
   ```

2. ❌ **NEVER use manual refresh triggers**:
   ```swift
   // WRONG
   @Published var listRefreshTrigger = UUID()

   func addItem() {
       items.append(newItem)
       listRefreshTrigger = UUID()  // ❌ Never do this
       objectWillChange.send()      // ❌ Never do this
   }

   // CORRECT
   func addItem() {
       items.append(newItem)  // ✓ @Published triggers update
   }
   ```

3. ❌ **NEVER create computed properties that recreate publishers**:
   ```swift
   // WRONG - infinite loop!
   var servicesPublisher: AnyPublisher<Void, Never> {
       manager.objectWillChange.eraseToAnyPublisher()
   }

   // CORRECT - use @ObservedObject
   @ObservedObject var manager: ServiceManager
   ```

4. ❌ **NEVER pass full runtime objects to list item views**:
   ```swift
   // WRONG
   ForEach(manager.services) { service in  // ❌ Full runtime
       ServiceRow(service: service)
   }

   // CORRECT
   ForEach(manager.servicesList) { serviceInfo in  // ✓ Lightweight
       ServiceRow(serviceInfo: serviceInfo, manager: manager)
   }
   ```

5. ❌ **NEVER forget to store Combine subscriptions**:
   ```swift
   // WRONG - subscription will be deallocated
   manager.objectWillChange.sink { _ in
       self?.objectWillChange.send()
   }

   // CORRECT
   manager.objectWillChange.sink { _ in
       self?.objectWillChange.send()
   }
   .store(in: &cancellables)  // ✓ Must store
   ```

#### Example: ServiceManager Architecture

**ServiceInfo (Lightweight)**:
```swift
struct ServiceInfo: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let isRunning: Bool
    let isExternallyManaged: Bool
    let hasPortConflict: Bool
    let processingAction: ServiceAction?
    let port: Int?
    let workingDirectory: String
    let command: String
}
```

**ServiceManager (Manager)**:
```swift
@MainActor
class ServiceManager: ObservableObject {
    @Published var servicesList: [ServiceInfo] = []  // Lightweight, public
    private var runtimes: [UUID: ServiceRuntime] = [:]  // Heavy, private
    private var cancellables = Set<AnyCancellable>()

    func getRuntime(id: UUID) -> ServiceRuntime?

    private func subscribeToRuntime(_ runtime: ServiceRuntime) {
        runtime.objectWillChange.sink { [weak self] _ in
            self?.refreshServicesList()
        }.store(in: &cancellables)
    }

    func refreshServicesList() {
        servicesList = runtimes.values.map { ServiceInfo(...) }
    }
}
```

**ServiceRuntime (Heavy Runtime)**:
```swift
@MainActor
class ServiceRuntime: ObservableObject {
    @Published var logs: String = ""  // Updates 10x/second
    @Published var isRunning: Bool = false
    // ... process, pipes, etc.
}
```

**ServiceManagerState (Module State)**:
```swift
@MainActor
class ServiceManagerState: ObservableObject {
    static let shared = ServiceManagerState()
    @Published var manager: ServiceManager
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.manager = ServiceManager(...)

        // Forward manager changes to state
        manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }
}
```

**Views**:
```swift
// List view - observes lightweight state
struct ServiceListItem: View {
    let serviceInfo: ServiceInfo  // Lightweight
    let manager: ServiceManager

    var body: some View {
        HStack {
            Text(serviceInfo.name)
            if serviceInfo.isRunning {
                Circle().fill(.green)
            }
        }
        .onTapGesture {
            // Fetch heavy data on-demand
            manager.getRuntime(id: serviceInfo.id)?.start()
        }
    }
}

// Detail view - can observe heavy runtime
struct ServiceDetailView: View {
    @ObservedObject var service: ServiceRuntime  // OK here

    var body: some View {
        ScrollView {
            Text(service.logs)  // Frequent updates OK in detail view
        }
    }
}
```

#### Performance Testing

Before committing any state management changes:

1. **Check CPU usage** with Activity Monitor or `htop`
2. **Test import/CRUD operations** - UI must update immediately
3. **Test with running services** - CPU should remain low
4. **Profile memory** - No leaks after operations

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
