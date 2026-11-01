# Silicium

A native macOS hardware monitor that turns your Apple Silicon Mac into an interactive 3D view. Explore the chip, CPU cores, GPU, memory, storage, battery, network, and power supply, then select a component to inspect its live metrics and health indicators.

Built with **Swift 6, SwiftUI, RealityKit, Swift Charts, and SQLite through GRDB**. The project targets Apple Silicon Macs running macOS 26 or later, with an initial focus on the MacBook Air M5.

> Silicium is under active development. Sensor availability depends on the Mac and macOS version. The 3D model is an educational representation, and health scores are software heuristics rather than hardware diagnostics.

## Features

- **Interactive 3D hardware view:** select components, inspect the chip, switch camera views, and separate the model into layers with the exploded view.
- **Live monitoring:** CPU load, GPU activity, memory pressure and swap, disk capacity and throughput, network traffic, battery condition, temperatures, and power readings where available.
- **Menu bar access:** check an overall health score and open the main window from the menu bar. Closing the main window keeps the monitor running.
- **Component details:** live charts, historical metrics, explanations, and process information.
- **Local alerts:** notifications for conditions such as sustained heat, memory pressure, low disk space, or battery wear.
- **Local history:** SQLite storage with one-minute aggregates retained for seven days and fifteen-minute aggregates retained for thirty days.
- **Optional on-device explanations:** uses Apple's Foundation Models framework when available on the device.

## Requirements

- An Apple Silicon Mac.
- macOS 26 or later.
- Xcode 26 or later, selected as the active developer directory.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project.
- [Homebrew](https://brew.sh) for the installation commands below.

Blender is only needed to regenerate the 3D model. The repository already includes the USDZ resource and app icons.

## Build and run

```sh
git clone https://github.com/yassineeljal/silicium.git
cd silicium
brew install xcodegen
xcodegen generate
open Silicium.xcodeproj
```

In Xcode, choose the **Silicium** scheme and **My Mac** destination, then run the app. Use the Silicium menu bar icon to open the hardware view.

Alternatively, build and launch from the terminal:

```sh
xcodebuild -project Silicium.xcodeproj \
  -scheme Silicium \
  -configuration Debug \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build

open build/Build/Products/Debug/Silicium.app
```

The first build downloads the GRDB Swift package dependency. No developer team is configured in the project; signing and notarization for distribution require your own configuration.

The generated `Silicium.xcodeproj` and build outputs are ignored by Git. After changing `project.yml`, run `xcodegen generate` again.

## Tests and CI

Run the package tests:

```sh
swift test --package-path SiliciumKit
```

The tests cover health scoring, sensor readings, history aggregation and retention, and UI navigation state. Sensor tests run against the current machine; available readings can vary by hardware.

The [GitHub Actions workflow](.github/workflows/ci.yml) runs the tests and builds the app in Release mode on macOS 26. It also runs SwiftLint as an advisory check.

## Architecture

| Location | Responsibility |
| --- | --- |
| `App/` | App entry point, menu bar lifecycle, notifications, resources, and debug commands. |
| `SiliciumKit/Sources/SiliciumShared/` | Shared snapshots, component identifiers, health reports, and formatting. |
| `SiliciumKit/Sources/SiliciumSensors/` | Hardware samplers and isolated IOReport/SMC access. |
| `SiliciumKit/Sources/CSMC/` | C bridge for SMC access. |
| `SiliciumKit/Sources/SiliciumCore/` | Sensor coordination, metric buffers, health scoring, and alerts. |
| `SiliciumKit/Sources/SiliciumStorage/` | GRDB-backed SQLite history and retention. |
| `SiliciumKit/Sources/SiliciumUI/` | SwiftUI views, charts, scene controls, and RealityKit rendering. |
| `SiliciumKit/Sources/silicium-probe/` | Command-line sensor inspection tool. |
| `tools/` | Blender model generation and app icon generation. |
| `project.yml` | XcodeGen project definition. |

The data flows from hardware samplers through `SensorHub`, health and alert evaluation, local history, and the UI. Sampling frequency adapts to foreground activity and power conditions. Failed or unsupported readings are shown as unavailable.

## Privacy and local data

Silicium does not require an account, an API key, or administrator privileges. Monitoring and history processing happen locally; the application does not implement a telemetry upload service.

History is stored at:

```text
~/Library/Application Support/Silicium/history.sqlite
```

Preferences are stored through macOS user defaults. The app reads process information and the foreground application name to provide context. Diagnostic output can contain machine-specific readings and process details; review it before sharing.

## Sensor inspection

Run these commands from the repository root:

```sh
# Print a sampled snapshot and sensor availability.
swift run --package-path SiliciumKit silicium-probe

# Inspect IOReport channels.
swift run --package-path SiliciumKit silicium-probe channels

# Inspect SMC temperature keys.
swift run --package-path SiliciumKit silicium-probe smc
```

## 3D model and visual verification

The app loads the bundled `App/Resources/Silicium.usdz` model, with procedural RealityKit geometry as a fallback. It uses `ARView` for mouse navigation, ray-based picking, and Metal bloom post-processing.

To regenerate the model with Blender (the existing resource was generated with Blender 5.2):

```sh
blender -b -P tools/blender/build_model.py -- App/Resources/Silicium.usdz
```

After a Debug build, validate the model or produce renders:

```sh
build/Build/Products/Debug/Silicium.app/Contents/MacOS/Silicium --verify-model
build/Build/Products/Debug/Silicium.app/Contents/MacOS/Silicium --render /tmp/silicium.png
build/Build/Products/Debug/Silicium.app/Contents/MacOS/Silicium --render /tmp/silicium-gpu.png --select gpu
build/Build/Products/Debug/Silicium.app/Contents/MacOS/Silicium --snapshot-ui /tmp/silicium-interface.png -hasOnboarded YES
```

See the [model generation documentation](tools/blender/README.md) for the naming contract, layer structure, visual references, and interaction checks. That document is currently in French.

## Current limitations

- Intel Macs, Windows, and Linux are outside the current scope.
- Some readings rely on private, undocumented IOReport and SMC interfaces. Availability and interpretation can change between hardware and macOS releases.
- SMC temperature groups are inferred from key prefixes and still need validation under load.
- The model is inspired by hardware teardown photographs and uses an educational layout; it is not a dimensionally accurate M5 board or a repair guide.
- Sparkle updates, WidgetKit, and App Intents from the original engineering plan are not implemented.
- The repository provides source builds; a signed and notarized release distribution is not configured.

The original French engineering plan is included in the repository. It describes intended scope and targets; the implemented code and the limitations above describe the current project.
