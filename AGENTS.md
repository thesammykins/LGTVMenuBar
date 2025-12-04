# AGENTS.md - LGTVMenuBar

## Build & Test Commands
```bash
cd LGTVMenuBar
swift build                                    # Build the project
swift test                                     # Run all tests
swift test --filter TVConfigurationTests       # Run single test suite
swift test --filter "initWithAllProperties"    # Run single test by name
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
