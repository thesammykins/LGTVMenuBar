#!/bin/bash
#
# build-dmg.sh - Build LGTVMenuBar.app and create distributable DMG
#
# Usage: 
#   ./scripts/build-dmg.sh          # Build and create DMG
#   ./scripts/build-dmg.sh --clean  # Clean build first
#
# Requirements:
#   - Xcode Command Line Tools
#   - Swift 6.0+
#
# Output:
#   - release/LGTVMenuBar.app
#   - release/LGTVMenuBar-{VERSION}.dmg
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

APP_NAME="LGTVMenuBar"
BUNDLE_ID="com.thesammykins.lgtvmenubar"
VERSION="1.0.0"
MIN_MACOS="15.0"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/.build"
RELEASE_DIR="${PROJECT_DIR}/release"
APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
DMG_STAGING="${RELEASE_DIR}/dmg_staging"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${RELEASE_DIR}/${DMG_NAME}"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ $1" >&2
}

log_step() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

cleanup() {
    if [[ -d "${DMG_STAGING}" ]]; then
        rm -rf "${DMG_STAGING}"
    fi
}

trap cleanup EXIT

# =============================================================================
# Parse Arguments
# =============================================================================

CLEAN_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--clean] [--help]"
            echo ""
            echo "Options:"
            echo "  --clean    Clean build directory before building"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Main Build Process
# =============================================================================

cd "${PROJECT_DIR}"

log_step "Building ${APP_NAME} v${VERSION}"

# Clean if requested
if [[ "${CLEAN_BUILD}" == true ]]; then
    log_info "Cleaning build directory..."
    rm -rf "${BUILD_DIR}"
    rm -rf "${RELEASE_DIR}"
fi

# Create release directory
mkdir -p "${RELEASE_DIR}"

# Build universal binary (Apple Silicon + Intel)
log_info "Building universal binary (arm64 + x86_64)..."
swift build \
    -c release \
    --arch arm64 \
    --arch x86_64

log_success "Build completed"

# =============================================================================
# Create App Bundle
# =============================================================================

log_step "Creating App Bundle"

# Remove existing bundle
rm -rf "${APP_BUNDLE}"

# Create bundle structure
log_info "Creating bundle structure..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
log_info "Copying binary..."
cp "${BUILD_DIR}/apple/Products/Release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Copy Info.plist
log_info "Copying Info.plist..."
if [[ -f "${PROJECT_DIR}/Sources/${APP_NAME}/Info.plist" ]]; then
    cp "${PROJECT_DIR}/Sources/${APP_NAME}/Info.plist" "${APP_BUNDLE}/Contents/"
elif [[ -f "${PROJECT_DIR}/Info.plist" ]]; then
    cp "${PROJECT_DIR}/Info.plist" "${APP_BUNDLE}/Contents/"
else
    # Generate Info.plist if it doesn't exist
    log_info "Generating Info.plist..."
    cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>LGTV Menu Bar needs local network access to communicate with your LG TV.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>LGTV Menu Bar needs Accessibility permission to capture volume keys for TV control.</string>
</dict>
</plist>
EOF
fi

# Copy entitlements for reference (not embedded, used for signing)
if [[ -f "${PROJECT_DIR}/Sources/${APP_NAME}/${APP_NAME}.entitlements" ]]; then
    cp "${PROJECT_DIR}/Sources/${APP_NAME}/${APP_NAME}.entitlements" "${RELEASE_DIR}/"
elif [[ -f "${PROJECT_DIR}/${APP_NAME}.entitlements" ]]; then
    cp "${PROJECT_DIR}/${APP_NAME}.entitlements" "${RELEASE_DIR}/"
fi

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

log_success "App bundle created at ${APP_BUNDLE}"

# =============================================================================
# Code Signing (Ad-hoc for development)
# =============================================================================

log_step "Code Signing (Ad-hoc)"

log_info "Signing app bundle with ad-hoc signature..."
log_info "Note: Ad-hoc signing requires re-granting Accessibility permission after each build."

# Ad-hoc sign the app bundle (required for TCC/Accessibility permissions)
codesign --force --deep --sign - "${APP_BUNDLE}"

# Verify signature
log_info "Verifying signature..."
codesign --verify --deep --verbose=1 "${APP_BUNDLE}"

log_success "Ad-hoc code signing completed"

# -----------------------------------------------------------------------------
# DEVELOPER ID SIGNING - Uncomment when ready for distribution
# -----------------------------------------------------------------------------
# 
# Replace "Developer ID Application: Your Name (TEAM_ID)" with your certificate
# 
# SIGNING_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
# ENTITLEMENTS="${RELEASE_DIR}/${APP_NAME}.entitlements"
# 
# log_info "Signing app bundle with Developer ID..."
# 
# # Sign frameworks and helpers first (if any)
# # find "${APP_BUNDLE}/Contents/Frameworks" -name "*.framework" -exec \
# #     codesign --force --options runtime --sign "${SIGNING_IDENTITY}" {} \;
# 
# # Sign the main app
# codesign --force \
#     --options runtime \
#     --entitlements "${ENTITLEMENTS}" \
#     --sign "${SIGNING_IDENTITY}" \
#     --timestamp \
#     "${APP_BUNDLE}"
# 
# # Verify signature
# log_info "Verifying signature..."
# codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
# 
# log_success "Developer ID code signing completed"
# -----------------------------------------------------------------------------

# =============================================================================
# Create DMG
# =============================================================================

log_step "Creating DMG"

# Clean up any existing DMG staging
rm -rf "${DMG_STAGING}"
rm -f "${DMG_PATH}"

# Create staging directory
log_info "Preparing DMG contents..."
mkdir -p "${DMG_STAGING}"

# Copy app to staging
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"

# Create Applications symlink
ln -s /Applications "${DMG_STAGING}/Applications"

# Create DMG
log_info "Creating DMG image..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

log_success "DMG created at ${DMG_PATH}"

# Clean up staging
rm -rf "${DMG_STAGING}"

# =============================================================================
# DMG Code Signing (Scaffolded - Uncomment when ready)
# =============================================================================

# -----------------------------------------------------------------------------
# DMG SIGNING - Uncomment when ready for distribution
# -----------------------------------------------------------------------------
# 
# log_info "Signing DMG..."
# codesign --force --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"
# 
# log_success "DMG signed"
# -----------------------------------------------------------------------------

# =============================================================================
# Notarization (Scaffolded - Uncomment when ready)
# =============================================================================

# -----------------------------------------------------------------------------
# NOTARIZATION - Uncomment when ready for distribution
# -----------------------------------------------------------------------------
# 
# Requires App Store Connect API key or Apple ID credentials
# See: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution
# 
# APPLE_ID="your-apple-id@example.com"
# TEAM_ID="YOUR_TEAM_ID"
# APP_PASSWORD="your-app-specific-password"  # Or use keychain item
# 
# log_info "Submitting for notarization..."
# xcrun notarytool submit "${DMG_PATH}" \
#     --apple-id "${APPLE_ID}" \
#     --team-id "${TEAM_ID}" \
#     --password "${APP_PASSWORD}" \
#     --wait
# 
# log_info "Stapling notarization ticket..."
# xcrun stapler staple "${DMG_PATH}"
# 
# log_success "Notarization completed"
# -----------------------------------------------------------------------------

# =============================================================================
# Summary
# =============================================================================

log_step "Build Complete!"

echo ""
echo "  App Bundle: ${APP_BUNDLE}"
echo "  DMG:        ${DMG_PATH}"
echo ""
echo "  To test the app:"
echo "    open ${APP_BUNDLE}"
echo ""
echo "  To install from DMG:"
echo "    open ${DMG_PATH}"
echo "    Drag ${APP_NAME} to Applications"
echo ""
echo "  ⚠️  IMPORTANT: After each build, you must re-grant Accessibility permission:"
echo "    1. Open System Settings > Privacy & Security > Accessibility"
echo "    2. Remove ${APP_NAME} if present (click -, or select and delete)"
echo "    3. Add the new ${APP_NAME}.app (click +)"
echo "    4. Restart the app"
echo ""

# Get file sizes
APP_SIZE=$(du -sh "${APP_BUNDLE}" | cut -f1)
DMG_SIZE=$(du -sh "${DMG_PATH}" | cut -f1)

echo "  Sizes:"
echo "    App: ${APP_SIZE}"
echo "    DMG: ${DMG_SIZE}"
echo ""
