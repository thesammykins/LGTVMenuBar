# AGENTS.md - LGTVMenuBar

## Project Snapshot
- **Platform**: macOS 15+
- **Language**: Swift 6.x with strict concurrency
- **UI**: SwiftUI menu bar app
- **Tests**: Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **Packaging**: DMG via `scripts/build-dmg.sh`

## Build, Test, Lint
```bash
# Build
swift build

# Run all tests
swift test

# Run a suite or single test (SwiftPM filter regex)
swift test --filter TVConfigurationTests
swift test --filter "initWithAllProperties"

# List tests (useful for filter patterns)
swift test --list-tests
```

Notes:
- `swift test --filter` accepts `<test-target>.<test-case>` or `<test-target>.<test-case>/<test>`.
- No explicit lint tool in this repo; compiler warnings/errors are the gate.

## DMG Build (Release Packaging)
```bash
# Build a universal (arm64 + x86_64) release and create a DMG
./scripts/build-dmg.sh

# Clean build + DMG
./scripts/build-dmg.sh --clean
```

Operational notes:
- The DMG script performs ad-hoc signing; Accessibility permission must be re-granted after each build.
- Release artifacts are written to `release/`.

## Versioning & Release Process
When pushing a new build:

1. **Update Info.plist** (`Sources/LGTVMenuBar/Info.plist`):
   - Increment `CFBundleVersion` (build number) by 1.
   - Update `CFBundleShortVersionString` (semver: MAJOR.MINOR.PATCH).
     - PATCH: bug fixes, minor changes
     - MINOR: new features, non-breaking changes
     - MAJOR: breaking changes

2. **Commit version changes**:
   ```bash
   git add Sources/LGTVMenuBar/Info.plist
   git commit -m "chore: bump version to X.Y.Z (build N)"
   ```

3. **Create and push git tag**:
   ```bash
   git tag vX.Y.Z
   git push origin main
   git push origin vX.Y.Z
   ```

4. **Verify GitHub Actions workflow** triggers for the new tag (DMG build + release)

Example:
```bash
# Bump from 1.1.2 (build 8) to 1.1.3 (build 9) for a bugfix
# Edit Info.plist: CFBundleVersion=9, CFBundleShortVersionString=1.1.3
git add Sources/LGTVMenuBar/Info.plist
git commit -m "chore: bump version to 1.1.3 (build 9)"
git tag v1.1.3
git push origin main
git push origin v1.1.3
```

## Code Style & Conventions

Imports:
- Order: Foundation first, then system frameworks (e.g., OSLog, Observation), then local modules.

Formatting:
- Use `// MARK: -` to segment major sections.
- Keep property/documentation blocks grouped and consistent.
- Favor clear, self-documenting names over comments.

Types & Access:
- Use `struct` for models/value types.
- Use `final class` for services/controllers.
- Use `public` for shared protocols/models.
- Keep mutable state `private(set)` unless mutation is required externally.

Protocols:
- Place in `Sources/LGTVMenuBar/Protocols/`.
- Suffix with `Protocol` and mark `Sendable` when used across concurrency boundaries.

Naming:
- Types: PascalCase.
- Properties/methods: camelCase.
- Tests: descriptive names that read like behavior.

Errors:
- Use domain-specific enums conforming to `Error`, `Equatable`, `LocalizedError`.
- Prefer user-facing `errorDescription` strings for UI/diagnostics.

Concurrency:
- Use `async/await` and structured concurrency.
- Use `@MainActor` for UI-bound state/services.
- Use `CheckedContinuation` for callback bridging.
- Use `Task.sleep` for async delays.

Tests & Mocks:
- Use Swift Testing (`import Testing`).
- Group tests with `@Suite`, name tests with `@Test("...")`.
- Use `#expect` for assertions.
- Mocks live in `Tests/LGTVMenuBarTests/Mocks/` with `Mock` prefix.
- Include `reset()` methods in mocks to clear captured state.

Documentation:
- Use `///` doc comments for public APIs.
- Avoid excess comments; explain WHY when behavior is non-obvious.

## Cursor / Copilot Rules
- No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` found in this repo.

## Verification Checklist
```bash
swift build
swift test
swift test --filter TVConfigurationTests
./scripts/build-dmg.sh
```
