# macOS Accessibility Permissions for Unsigned Apps - 2025

**Research Date:** December 3, 2025  
**Primary Sources:** Apple Developer Documentation, HackTricks TCC Guide, Jano.dev Accessibility Guide, Stack Overflow discussions, GitHub issue reports  
**Relevant Versions:** macOS 15+ (Sequoia), TCC framework, Swift 6.0

## Executive Summary

macOS accessibility permissions for unsigned apps remain challenging in 2025 due to Apple's tightened security model. The core issue is that `AXIsProcessTrusted()` relies on multiple verification layers including bundle identifier, code signature, and TCC database entries. Unsigned apps face signature validation failures that prevent proper permission recognition even when manually added to System Settings. Workarounds exist but involve trade-offs between security and development convenience.

## Key Findings

- **Signature validation is mandatory**: TCC database stores both bundle ID AND code signature requirements
- **Unsigned apps fail silently**: `AXIsProcessTrusted()` returns false even when manually enabled
- **Ad-hoc signing provides partial relief**: Self-signed apps work better than unsigned but still face limitations
- **Location independence**: Apps don't need to be in `/Applications` but stable locations help
- **Bundle vs binary distinction**: System Settings tracks .app bundles, not individual executables

## Detailed Information

### 1. Why `AXIsProcessTrusted()` Returns False

The `AXIsProcessTrusted()` function performs multi-layer verification:

1. **Bundle Identifier Check**: Validates the app's CFBundleIdentifier
2. **Code Signature Verification**: Validates against stored `csreq` in TCC database
3. **Path Consistency**: Ensures app hasn't moved since permission granted
4. **Process Identity**: Verifies the running process matches the granted identity

For unsigned apps, step 2 fails because TCC stores a code signing requirement (`csreq`) that unsigned binaries cannot satisfy.

### 2. Known Issues with Unsigned/Ad-hoc Signed Apps

**Unsigned Apps:**
- Cannot satisfy any `csreq` validation in TCC database
- Manual System Settings addition creates database entries that immediately fail validation
- `AXIsProcessTrusted()` consistently returns false despite UI showing enabled

**Ad-hoc Signed Apps:**
- Better than unsigned but still problematic
- Each build generates different ad-hoc signatures
- TCC entries become invalid after each rebuild
- Requires manual re-authorization after each code change

### 3. Relationship Between Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Bundle Identifier│───▶│   TCC Database   │◀───│ Code Signature  │
│ (com.example.app)│    │ (access table)   │    │ (csreq field)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   System UI     │    │  AXIsProcessTrusted │◀───│  Running Process│
│ (Settings App)  │    │   Validation      │    │   Identity      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

**Key Relationships:**
- Bundle identifier is the primary key in TCC database
- Code signature (`csreq`) is stored as BLOB data for validation
- `AXIsProcessTrusted()` checks all three components match
- Changes to any component break the permission chain

### 4. Workarounds for Development

**Option 1: Developer ID Signing (Recommended)**
```bash
# Sign with Developer ID certificate
codesign --force --sign "Developer ID Application: Your Name" YourApp.app

# Verify signature
codesign -d -vv YourApp.app
```

**Option 2: Ad-hoc Signing with Stable Identity**
```bash
# Create consistent ad-hoc signature
codesign --force --sign "-" YourApp.app

# Use same identity across builds
codesign --force --sign "adhoc-identity" YourApp.app
```

**Option 3: Development Workflow with Reset**
```bash
# Reset permissions before each build
tccutil reset Accessibility com.yourapp.identifier

# Build and sign
swift build
codesign --force --sign "-" YourApp.app

# Manually re-authorize in System Settings
```

**Option 4: Terminal-based Development**
```bash
# Grant terminal accessibility permissions
# Run app from terminal to inherit permissions
./YourApp.app/Contents/MacOS/YourApp
```

### 5. Location Requirements

**No, apps don't need to be in `/Applications`** but:
- Stable locations prevent permission invalidation
- Moving apps breaks TCC entries (path-based validation)
- Development builds in `~/Library/Developer/Xcode/DerivedData/` change frequently
- Custom build locations provide more stability

**Recommended build location:**
```bash
# In Xcode build settings
CONFIGURATION_BUILD_DIR = $(PROJECT_DIR)/Build/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)
```

### 6. Bundle vs Binary Distinction

**System Settings tracks .app bundles only:**
- Adding individual executables doesn't create proper TCC entries
- Bundle identifier is required for proper permission tracking
- The `client_type` field in TCC database distinguishes bundle (0) vs binary (1)
- Accessibility permissions require bundle-based entries

**Correct approach:**
- Always add the complete `.app` bundle to Accessibility list
- Ensure proper `Info.plist` with bundle identifier
- Don't attempt to add individual binaries

### 7. Logging and Debugging

**Console.app Filtering:**
```
type:error
subsystem:com.apple.sandbox.reporting
category:violation
```

**Terminal Log Streaming:**
```bash
log stream --predicate \
'process == "tccd" OR process == "YourApp" OR process="sandboxd"'
```

**TCC Database Inspection:**
```bash
# Check if app is authorized (1=granted, 2=denied)
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
"SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client='com.yourapp.identifier';"

# View complete entry
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
"SELECT * FROM access WHERE service='kTCCServiceAccessibility' AND client='com.yourapp.identifier';"
```

**Code Signing Verification:**
```bash
# Check current signature
codesign -d -r- YourApp.app

# Extract and decode TCC csreq
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
"SELECT hex(csreq) FROM access WHERE client='com.yourapp.identifier';" | \
xxd -r -p | csreq -r- -t -
```

## Best Practices

### For Development
1. **Use Developer ID signing** for consistent identity across builds
2. **Set stable build locations** to prevent path-based invalidation
3. **Implement permission checking** with user-friendly prompts
4. **Reset TCC judiciously** using `tccutil reset Accessibility com.bundle.id`
5. **Document requirements** for users about manual authorization

### For Distribution
1. **Always sign with Developer ID** for proper TCC integration
2. **Include accessibility usage description** in `Info.plist`
3. **Provide clear user instructions** for permission authorization
4. **Test on clean systems** to verify permission workflow

## Considerations and Trade-offs

**Security vs Convenience:**
- Unsigned apps offer maximum convenience but zero reliability
- Developer ID signing provides best balance of security and functionality
- Ad-hoc signing works but requires frequent re-authorization

**Development Workflow Impact:**
- Manual authorization required after each unsigned build
- Automated testing becomes challenging without proper signing
- CI/CD pipelines need certificate management

**User Experience:**
- First-time users must manually authorize in System Settings
- Permission failures are often silent and confusing
- Clear error messages and instructions are essential

## Code Examples

### Permission Checking Implementation
```swift
import ApplicationServices

class AccessibilityManager {
    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    static func requestAccessibilityPermission() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
    }
    
    static func openAccessibilitySettings() {
        if let url = URL(string: 
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }
}
```

### Info.plist Configuration
```xml
<key>NSAccessibilityUsageDescription</key>
<string>This app needs accessibility permissions to capture media keys for system-wide control.</string>

<key>com.apple.security.accessibility</key>
<true/>
```

## References

- [Apple Developer Documentation - AXIsProcessTrusted](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions?language=objc)
- [HackTricks macOS TCC Guide](https://angelica.gitbook.io/hacktricks/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-tcc)
- [Jano.dev Accessibility Permission Guide](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)
- [macOS TCC Database Deep Dive](https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive)
- [Apple Developer Forums - TCC Issues](https://developer.apple.com/forums/tags/entitlements?page=4&sortBy=newest)

---

**Note:** This research focuses on macOS 15+ (Sequoia) and Swift 6.0 development environments. Some behaviors may vary on older macOS versions.