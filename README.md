# DevDash

A lightweight, modular macOS application for managing local development workflows.

## Features

- **Service Manager** - Start/stop local services, view logs, track errors/warnings, handle port conflicts
- **EC2 Manager** - Track AWS EC2 instance IPs with aws-vault integration

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
│   └── EC2Manager/
│       ├── EC2ManagerModule.swift        # Module definition + state
│       ├── Models/                       # EC2Instance, InstanceGroup
│       ├── Managers/                     # InstanceGroupManager
│       └── Views/                        # UI components
│
├── ContentView.swift         # Root navigation
└── DevDashApp.swift         # App entry point
```

### Creating a New Module

1. **Create module directory**: `Modules/YourModule/`
2. **Define module struct**:
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
3. **Create shared state**:
   ```swift
   @MainActor
   class YourModuleState: ObservableObject {
       static let shared = YourModuleState()
       // Your state properties
   }
   ```
4. **Register module** in `DevDashApp.swift`:
   ```swift
   ModuleRegistry.shared.register(YourModule())
   ```

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

1. **Lightweight** - No heavy dependencies, minimal memory footprint
2. **No memory leaks** - Proper cleanup of processes, tasks, and observers
3. **Efficient rendering** - Virtualized log views, debounced search, ring buffers
4. **Async operations** - Background tasks for shell commands and API calls
5. **Resource cleanup** - Terminate processes on service stop/app quit

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

1. **Performance First** - Keep the app lightweight with no performance impact, prevent memory leaks, ensure proper resource cleanup
2. **No Guessing** - If unsure about implementation details, ask clarifying questions
3. **DRY Principle** - Avoid code duplication, extract shared logic to utilities
4. **User-Friendly** - Design intuitive, simple interfaces with clear visual feedback

## License

Private project
