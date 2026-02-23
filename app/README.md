# OpenCamera - macOS App

A modern macOS application using a **workspace + SPM package** architecture for clean separation between app shell and feature code.

## Project Architecture

```
OpenCamera/
├── OpenCamera.xcworkspace/              # Open this file in Xcode
├── OpenCamera.xcodeproj/                # App shell project
├── OpenCamera/                          # App target (minimal)
│   ├── Assets.xcassets/                # App-level assets (icons, colors)
│   ├── OpenCameraApp.swift              # App entry point
│   ├── OpenCamera.entitlements          # App sandbox settings
│   └── OpenCamera.xctestplan            # Test configuration
├── OpenCameraPackage/                   # 🚀 Primary development area
│   ├── Package.swift                   # Package configuration
│   ├── Sources/OpenCameraFeature/       # Your feature code
│   └── Tests/OpenCameraFeatureTests/    # Unit tests
└── OpenCameraUITests/                   # UI automation tests
```

## Key Architecture Points

### Workspace + SPM Structure
- **App Shell**: `OpenCamera/` contains minimal app lifecycle code
- **Feature Code**: `OpenCameraPackage/Sources/OpenCameraFeature/` is where most development happens
- **Separation**: Business logic lives in the SPM package, app target just imports and displays it

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

### App Sandbox
The app is sandboxed by default with basic file access permissions. Modify `OpenCamera.entitlements` to add capabilities as needed.

## Development Notes

### Code Organization
Most development happens in `OpenCameraPackage/Sources/OpenCameraFeature/` - organize your code as you prefer.

### Public API Requirements
Types exposed to the app target need `public` access:
```swift
public struct SettingsView: View {
    public init() {}
    
    public var body: some View {
        // Your view code
    }
}
```

### Adding Dependencies
Edit `OpenCameraPackage/Package.swift` to add SPM dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "OpenCameraFeature",
        dependencies: ["SomePackage"]
    ),
]
```

### Test Structure
- **Unit Tests**: `OpenCameraPackage/Tests/OpenCameraFeatureTests/` (Swift Testing framework)
- **UI Tests**: `OpenCameraUITests/` (XCUITest framework)
- **Test Plan**: `OpenCamera.xctestplan` coordinates all tests

## Configuration

### XCConfig Build Settings
Build settings are managed through **XCConfig files** in `Config/`:
- `Config/Shared.xcconfig` - Common settings (bundle ID, versions, deployment target)
- `Config/Debug.xcconfig` - Debug-specific settings  
- `Config/Release.xcconfig` - Release-specific settings
- `Config/Tests.xcconfig` - Test-specific settings

### App Sandbox & Entitlements
The app is sandboxed by default with basic file access. Edit `OpenCamera/OpenCamera.entitlements` to add capabilities:
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<!-- Add other entitlements as needed -->
```

## macOS-Specific Features

### Window Management
Add multiple windows and settings panels:
```swift
@main
struct OpenCameraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        Settings {
            SettingsView()
        }
    }
}
```

### Asset Management
- **App-Level Assets**: `OpenCamera/Assets.xcassets/` (app icon with multiple sizes, accent color)
- **Feature Assets**: Add `Resources/` folder to SPM package if needed

### SPM Package Resources
To include assets in your feature package:
```swift
.target(
    name: "OpenCameraFeature",
    dependencies: [],
    resources: [.process("Resources")]
)
```

## Notes

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted macOS development workflows.