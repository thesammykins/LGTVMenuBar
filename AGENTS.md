# AGENTS.md - LGTVMenuBar

## Build & Test Commands
```bash
cd LGTVMenuBar
swift build                                    # Build the project
swift test                                     # Run all tests
swift test --filter TVConfigurationTests       # Run single test suite
swift test --filter "initWithAllProperties"    # Run single test by name
```

## Versioning & Release Process

When pushing a new build:

1. **Update Info.plist** (`Sources/LGTVMenuBar/Info.plist`):
   - Increment `CFBundleVersion` (build number) - always increment by 1
   - Update `CFBundleShortVersionString` (semantic version: MAJOR.MINOR.PATCH)
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

4. **Verify GitHub Actions workflow** triggers for the new tag (builds DMG)

**Example:**
```bash
# Bump from 1.1.2 (build 8) to 1.1.3 (build 9) for a bugfix
# Edit Info.plist: CFBundleVersion=9, CFBundleShortVersionString=1.1.3
git add Sources/LGTVMenuBar/Info.plist
git commit -m "chore: bump version to 1.1.3 (build 9)"
git tag v1.1.3
git push origin main
git push origin v1.1.3
```

## Code Style
- **Swift 6.0** with strict concurrency (`Sendable`, `@MainActor`)
- **macOS 15+** target, SwiftUI for UI
- **Testing**: Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **Imports**: Foundation first, then system frameworks, then local modules
- **Types**: Use `public` for protocols/models, `final class` for services, `struct` for data
- **Protocols**: Define in `Protocols/` with `Protocol` suffix, mark `Sendable`
- **Errors**: Domain-specific enums conforming to `Error`, `Equatable`, `LocalizedError`
- **Naming**: PascalCase types, camelCase properties/methods, descriptive test names
- **Mocks**: Place in `Tests/.../Mocks/`, prefix with `Mock`, include `reset()` method
- **Docs**: Use `///` doc comments for public APIs, `// MARK: -` for sections
- **Async**: Use `async/await`, `CheckedContinuation` for callbacks, `Task.sleep` for delays
