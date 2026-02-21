# DevDash

A lightweight, modular macOS application for managing local development workflows.

## Features

- **Service Manager** - Start/stop local services, view logs, track errors/warnings, handle port conflicts
- **EC2 Manager** - Track AWS EC2 instance IPs with aws-vault integration
- **Credentials Manager** - Secure credential storage with Apple Keychain and biometric authentication

## Architecture

### Modular System

DevDash uses a **module-based architecture** where each feature is an independent, self-contained module. This design promotes:
- **Separation of concerns** - Each module owns its models, views, managers, and state
- **Easy extensibility** - Add new features by creating new modules
- **Minimal coupling** - Modules communicate via shared protocols
- **Maintainability** - Changes are isolated to specific modules

### Module Structure

Each module implements the `DevDashModule` protocol:

```swift
protocol DevDashModule: Identifiable {
    var id: String { get }
    var name: String { get }
    var icon: String { get }
    var description: String { get }
    var accentColor: Color { get }

    func makeSidebarView() -> AnyView
    func makeDetailView() -> AnyView
}
```

Modules are registered with `ModuleRegistry` at app launch and rendered dynamically in the UI.

### Directory Organization

```
DevDash/
├── Core/
│   ├── Models/               # Module protocol, registry
│   ├── Components/           # Reusable UI components
│   ├── Theme/               # AppTheme, colors, typography
│   ├── Utilities/           # Helpers (LogParser, ProcessEnvironment, etc.)
│   └── Protocols/           # Shared interfaces
│
├── Modules/
│   ├── ServiceManager/
│   │   ├── ServiceManagerModule.swift    # Module definition + state
│   │   ├── Models/                       # ServiceConfig
│   │   ├── Runtime/                      # ServiceRuntime (process lifecycle)
│   │   ├── Managers/                     # ServiceManager (CRUD, persistence)
│   │   └── Views/                        # UI components
│   │
│   ├── EC2Manager/
│   │   ├── EC2ManagerModule.swift        # Module definition + state
│   │   ├── Models/                       # EC2Instance, InstanceGroup
│   │   ├── Managers/                     # InstanceGroupManager
│   │   └── Views/                        # UI components
│   │
│   └── CredentialsManager/
│       ├── CredentialsManagerModule.swift # Module definition + state
│       ├── Models/                        # Credential, CredentialField
│       ├── Managers/                      # CredentialsManager (CRUD, Keychain)
│       └── Views/                         # UI components
│
├── ContentView.swift         # Root navigation
└── DevDashApp.swift         # App entry point
```

### Event-Driven Architecture

**All modules follow a strict event-driven pattern to ensure zero performance impact.**

```
ModuleState (UI observes this)
    ↓ forwards objectWillChange
Manager (exposes lightweight list)
    ↓ subscribes to changes
Runtime (heavy data: logs, processes)
```

**Key Principles:**
1. **Lightweight State** - List views observe stable, lightweight data structures
2. **Event Forwarding** - Nested ObservableObjects forward changes via Combine
3. **On-Demand Fetching** - Heavy data (logs, processes) fetched only when needed
4. **Automatic Updates** - `@Published` properties trigger UI updates automatically
5. **No Manual Triggers** - Never use `listRefreshTrigger` or `objectWillChange.send()`

**Why This Matters:**
- ✅ **Low CPU Usage** - No constant re-renders from frequently updating logs
- ✅ **Instant UI Updates** - Changes propagate automatically via reactive system
- ✅ **Memory Efficient** - List views only hold minimal data
- ❌ **Without this pattern** - 100% CPU usage, infinite loops, UI not updating

See `CLAUDE.md` for detailed implementation rules and examples.

### Creating a New Module

**IMPORTANT: Follow the event-driven architecture pattern to avoid performance issues.**

1. **Create module directory**: `Modules/YourModule/`

2. **Define lightweight info struct** (if module has list of items):
   ```swift
   struct YourItemInfo: Identifiable, Equatable, Hashable {
       let id: UUID
       let name: String
       let status: String
       // Only stable, lightweight properties
       // NO logs, NO processes, NO frequently updating data
   }
   ```

3. **Create manager** (handles CRUD, persistence):
   ```swift
   @MainActor
   class YourManager: ObservableObject {
       @Published var itemsList: [YourItemInfo] = []  // Public lightweight
       private var runtimes: [UUID: YourRuntime] = [:]  // Private heavy
       private var cancellables = Set<AnyCancellable>()

       func getRuntime(id: UUID) -> YourRuntime? {
           return runtimes[id]
       }

       private func subscribeToRuntime(_ runtime: YourRuntime) {
           runtime.objectWillChange.sink { [weak self] _ in
               self?.refreshItemsList()
           }.store(in: &cancellables)
       }

       func refreshItemsList() {
           itemsList = runtimes.values.map { YourItemInfo(...) }
       }

       func addItem(_ item: YourItem) {
           let runtime = YourRuntime(item: item)
           subscribeToRuntime(runtime)
           runtimes[item.id] = runtime
           // @Published triggers update automatically - don't call objectWillChange.send()
       }
   }
   ```

4. **Create module state with event forwarding**:
   ```swift
   @MainActor
   class YourModuleState: ObservableObject {
       static let shared = YourModuleState()
       @Published var manager: YourManager
       private var cancellables = Set<AnyCancellable>()

       private init() {
           self.manager = YourManager(...)

           // REQUIRED: Forward manager changes to state
           manager.objectWillChange.sink { [weak self] _ in
               self?.objectWillChange.send()
           }.store(in: &cancellables)
       }
   }
   ```

5. **Define module struct**:
   ```swift
   struct YourModule: DevDashModule {
       let id = "your-module"
       let name = "Your Module"
       let icon = "star.fill"
       let description = "Module description"
       let accentColor = Color.green

       func makeSidebarView() -> AnyView {
           AnyView(YourModuleSidebarView())
       }

       func makeDetailView() -> AnyView {
           AnyView(YourModuleDetailView())
       }
   }
   ```

6. **Create list view** (observes lightweight state):
   ```swift
   struct YourItemRow: View {
       let itemInfo: YourItemInfo  // Lightweight
       let manager: YourManager

       var body: some View {
           HStack {
               Text(itemInfo.name)
               // Actions use manager.getRuntime(id) for heavy operations
           }
       }
   }
   ```

7. **Register module** in `DevDashApp.swift`:
   ```swift
   ModuleRegistry.shared.register(YourModule())
   ```

**Critical Rules:**
- ✅ Use Combine event forwarding for nested ObservableObjects
- ✅ Separate lightweight state (for lists) from heavy runtime data (for details)
- ✅ Let `@Published` trigger updates - NEVER manually call `objectWillChange.send()`
- ❌ NEVER observe objects with frequently updating properties in list views
- ❌ NEVER use manual refresh triggers like `listRefreshTrigger = UUID()`

### Available Modules

#### Service Manager
Manage local development services with full process lifecycle control:
- Start/stop services with shell command execution
- Real-time log streaming with error/warning detection
- Port conflict detection and resolution
- Search logs with syntax highlighting
- Import/Export service configurations

#### EC2 Manager
Track AWS EC2 instance public IPs organized by region/environment:
- aws-vault integration for credential management
- Async IP fetching via AWS CLI
- Regional grouping of instances
- Cached IP addresses with last fetch timestamps
- Import/Export instance group configurations

#### Credentials Manager
Secure credential storage with biometric authentication:
- **Security**: Apple Keychain for passwords, Touch ID/Face ID authentication
- **Organization**: Category-based organization (Databases, API Keys, SSH, etc.)
- **Flexibility**: Custom fields with text/secret type selection
- **Usability**: Search/filter, reveal/hide toggles, one-click copy
- **Session Auth**: Authentication cached for app session, invalidated on background
- **Import/Export**: Metadata only (passwords remain secure in Keychain)

### Core Components

**Reusable UI Components** (`Core/Components/`):
- `VariantComponents` - Buttons with primary/danger/ghost variants
- `FormComponents` - Form fields, labels, text editors
- `ServiceOutputPanel` - Log viewer with search and error/warning tabs
- `LogView` - Virtualized log rendering with syntax highlighting
- `CopyableField` - One-click copy text fields
- `RelativeTimeText` - Auto-updating relative timestamps

**Utilities** (`Core/Utilities/`):
- `LogParser` - Real-time error/warning detection with pattern matching
- `ProcessEnvironment` - Shell environment variable resolution
- `StorageManager` - UserDefaults persistence layer
- `ImportExportManager` - JSON import/export with file panels
- `AlertQueue` - Sequential alert presentation
- `KeychainManager` - Secure storage wrapper for Apple Keychain
- `BiometricAuthManager` - Touch ID/Face ID/Password authentication with session management
- `AWSVaultManager` - AWS vault profile management via CLI integration

**Theme System** (`Core/Theme/AppTheme.swift`):
- Centralized typography (h1, h2, h3, body, caption)
- Color palette with gradient support
- Responsive accent color switching per module

### Data Flow

1. **Modules** own their state via singleton `@ObservableObject` classes (e.g., `ServiceManagerState`)
2. **Managers** handle business logic (persistence, API calls, validation)
3. **Runtime classes** manage long-running operations (processes, AWS CLI calls)
4. **Views** observe state and trigger manager/runtime actions
5. **Core utilities** provide shared functionality without state

### Performance Principles

The app follows strict performance guidelines:

1. **Event-Driven Architecture** - All modules use lightweight state with Combine event forwarding (see above)
2. **No Observed Heavy Objects** - List views NEVER observe objects with frequently updating properties (logs, processes)
3. **Automatic Updates** - `@Published` properties trigger UI updates; NEVER use manual refresh triggers
4. **Lightweight State** - Separate read-only snapshots for lists from full runtime objects for details
5. **No memory leaks** - Proper cleanup of processes, tasks, observers, and Combine subscriptions
6. **Efficient rendering** - Virtualized log views, debounced search, ring buffers for logs
7. **Async operations** - Background tasks for shell commands and API calls (Task.detached)
8. **Resource cleanup** - Terminate processes on service stop/app quit

**Performance Testing Requirements:**
- CPU usage must remain low even with services running (test with Activity Monitor/htop)
- Import/CRUD operations must update UI immediately (no manual refresh needed)
- No memory leaks after operations (test with Instruments)

## Requirements

- macOS 13.0+ (Ventura)
- Xcode 14+
- aws-vault (for EC2 Manager module)
- AWS CLI v2 (for EC2 Manager module)

## Building

Open `DevDash.xcodeproj` in Xcode and press Cmd+R to build and run.

## Data Storage

- **Services**: `UserDefaults` key `"services"` (JSON array of `ServiceConfig`)
- **EC2 Groups**: `UserDefaults` key `"instanceGroups"` (JSON array of `InstanceGroup`)
- Import/Export uses JSON format via native file panels

## Development Rules

**These rules are mandatory and override all other considerations:**

1. **Performance First** - Keep the app lightweight with zero performance impact. Profile CPU and memory before committing changes. Test with running services and multiple operations.

2. **Event-Driven Architecture** - Follow the established pattern:
   - ✅ Use Combine event forwarding for nested ObservableObjects
   - ✅ Separate lightweight state from heavy runtime data
   - ✅ Let `@Published` trigger updates automatically
   - ❌ NEVER observe objects with frequently updating properties in list views
   - ❌ NEVER use manual refresh triggers (`listRefreshTrigger`, `objectWillChange.send()`)

3. **No Guessing, No Patronizing** - If unsure about implementation details, say so explicitly and ask clarifying questions. Do not make assumptions.

4. **DRY Principle** - Avoid code duplication. Extract shared logic to Core utilities. Reuse existing components.

5. **User-Friendly & Intuitive** - Design simple, clear interfaces with immediate visual feedback. Make actions reversible where possible.

**Before Creating New Modules:**
- Review `CLAUDE.md` Event-Driven Architecture section for detailed implementation rules
- Follow the exact pattern shown in ServiceManager, EC2Manager, CredentialsManager, AWSVaultManager
- Test CPU usage with Activity Monitor/htop after implementation

## License

Private project
