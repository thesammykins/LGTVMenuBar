<h1>
  <img src="icons/app_icon-macOS-Default-1024x1024@2x.png" alt="LGTVMenuBar icon" width="32" height="32" /> LGTVMenuBar
</h1>

A native macOS menu bar app for controlling LG WebOS TVs.

## Screenshots

| Menu bar (compact) | Menu bar (expanded) |
| --- | --- |
| <a href="images/menubar-small.png"><img src="images/menubar-small.png" alt="Menu bar compact" width="320" /></a><br><sub>Compact status view</sub> | <a href="images/menubar-expanded.png"><img src="images/menubar-expanded.png" alt="Menu bar expanded" width="320" /></a><br><sub>Expanded controls</sub> |

| General settings | Automation settings | Diagnostics |
| --- | --- | --- |
| <a href="images/general.png"><img src="images/general.png" alt="General settings" width="240" /></a><br><sub>Connection and input preferences</sub> | <a href="images/automation.png"><img src="images/automation.png" alt="Automation settings" width="240" /></a><br><sub>Wake/sleep and input rules</sub> | <a href="images/diagnostics.png"><img src="images/diagnostics.png" alt="Diagnostics" width="240" /></a><br><sub>Logging and export tools</sub> |

## Features

- **Wake-on-LAN**: Wake your TV when your Mac wakes
- **Auto Sleep**: Turn off TV when Mac sleeps (skips if watching different input)
- **Volume Control**: Weighted slider with resistance at high volumes
- **Input Switching**: Quick switch between HDMI, DisplayPort, USB-C inputs
- **Screen Control**: Turn screen on/off without powering down TV
- **PC Mode**: Auto-detect and set PC mode for reduced input lag
- **Media Keys**: Capture volume keys to control TV volume
- **Onboarding**: First-run setup wizard

## Requirements

- macOS 15.0+
- LG WebOS TV (2018 or newer recommended)
- TV and Mac on the same network

## Building

```bash
# Build the project
swift build

# Run tests
swift test

# Build a development DMG (ad-hoc signed)
./scripts/build-dmg.sh

# Build a local signed release without notarization
./scripts/build-dmg.sh --local-release

# Build a signed and notarized release
./scripts/build-dmg.sh --release
```

Notes:
- `./scripts/build-dmg.sh` produces an ad-hoc signed development build.
- `./scripts/build-dmg.sh --local-release` requires a local `Developer ID Application` certificate.
- `./scripts/build-dmg.sh --release` requires a local `Developer ID Application` certificate plus App Store Connect notary credentials.

## Installation

1. Download the latest DMG from Releases
2. Open the DMG and drag LGTVMenuBar to Applications
3. Launch LGTVMenuBar
4. Follow the onboarding wizard to connect your TV
5. Grant Accessibility permission when prompted (for media key capture)

## First Launch And Security

Official GitHub releases are `Developer ID` signed and notarized, so Gatekeeper should allow a normal first launch after you drag the app into `Applications`.

If you build the app locally with the default `./scripts/build-dmg.sh`, the output is only ad-hoc signed for development. That build is not notarized, and macOS may treat it differently from the official release artifacts.

For local ad-hoc builds:

1. Re-grant Accessibility permission after each rebuild.
2. If Gatekeeper still blocks the app, open the bundle from Finder once with **Open** to confirm the local build.

## Configuration

On first launch, the onboarding wizard will guide you through:

1. **TV Discovery**: Enter your TV's IP address and MAC address
2. **TV Pairing**: Accept the pairing prompt on your TV
3. **Preferences**: Configure wake/sleep behavior and preferred input
4. **Permissions**: Grant necessary system permissions

## Architecture

- **Swift 6.0** with strict concurrency
- **SwiftUI** for the menu bar popover UI
- **WebSocket** communication with LG WebOS API
- **Keychain** for secure pairing key storage

## Project Structure

```
Sources/LGTVMenuBar/
├── Models/          # Data models and enums
├── Protocols/       # Protocol definitions
├── Services/        # Business logic and API clients
└── Views/           # SwiftUI views

Tests/LGTVMenuBarTests/
├── Mocks/           # Mock implementations for testing
├── Services/        # Service integration tests
└── Unit/            # Unit tests
```

## License

MIT License - see [LICENSE](LICENSE) for details.
