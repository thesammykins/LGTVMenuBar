#!/bin/bash
#
# build-dmg.sh - Build LGTVMenuBar.app and create distributable DMG
#
# Usage:
#   ./scripts/build-dmg.sh                     # Build with ad-hoc signing
#   ./scripts/build-dmg.sh --clean             # Clean build first
#   ./scripts/build-dmg.sh --release          # Build, Developer ID sign, notarize, staple
#   ./scripts/build-dmg.sh --local-release    # Build and sign locally without notarization
#   ./scripts/build-dmg.sh --skip-signing     # Build without signing (for external signing flows)
#
# Requirements:
#   - Xcode Command Line Tools
#   - Swift 6.0+
#
# Output:
#   - release/LGTVMenuBar.app
#   - release/LGTVMenuBar-{VERSION}-universal.dmg
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

APP_NAME="LGTVMenuBar"
BUNDLE_ID="com.thesammykins.lgtvmenubar"
MIN_MACOS="15.0"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Read version from Info.plist
INFO_PLIST="${PROJECT_DIR}/Sources/${APP_NAME}/Info.plist"
if [[ -f "${INFO_PLIST}" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST}" 2>/dev/null || echo "1.0.0")
else
    VERSION="${APP_VERSION:-1.0.0}"
fi

BUILD_DIR="${PROJECT_DIR}/.build"
RELEASE_DIR="${PROJECT_DIR}/release"
APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
APP_FRAMEWORKS_DIR="${APP_BUNDLE}/Contents/Frameworks"
DMG_STAGING="${RELEASE_DIR}/dmg_staging"
DMG_MOUNT="${RELEASE_DIR}/dmg_mount"
DMG_NAME="${APP_NAME}-${VERSION}-universal.dmg"
DMG_PATH="${RELEASE_DIR}/${DMG_NAME}"
DMG_RW_PATH="${RELEASE_DIR}/${APP_NAME}-${VERSION}-rw.dmg"
DMG_BACKGROUND_SOURCE="${PROJECT_DIR}/scripts/assets/dmg-background.png"
DMG_BACKGROUND_NAME="dmg-background.png"
SPARKLE_FRAMEWORK_SOURCE="${BUILD_DIR}/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

# Signing defaults
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
DEVELOPER_ID_IDENTITY_NAME="${DEVELOPER_ID_IDENTITY_NAME:-}"
ASC_KEY_ID="${ASC_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
ASC_KEY_FILE="${ASC_KEY_FILE:-}"
ASC_1PASSWORD_ITEM="${ASC_1PASSWORD_ITEM:-App Store Connect Developer Key}"
ASC_1PASSWORD_VAULT="${ASC_1PASSWORD_VAULT:-}"
ASC_1PASSWORD_FILE_NAME="${ASC_1PASSWORD_FILE_NAME:-}"
TEMP_NOTARY_KEY_FILE=""

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
    if hdiutil info | grep -Fq "${DMG_MOUNT}"; then
        hdiutil detach "${DMG_MOUNT}" -quiet || true
    fi

    if [[ -d "${DMG_MOUNT}" ]]; then
        rmdir "${DMG_MOUNT}" 2>/dev/null || true
    fi

    if [[ -d "${DMG_STAGING}" ]]; then
        rm -rf "${DMG_STAGING}"
    fi

    if [[ -f "${DMG_RW_PATH}" ]]; then
        rm -f "${DMG_RW_PATH}"
    fi

    if [[ -n "${TEMP_NOTARY_KEY_FILE}" && -f "${TEMP_NOTARY_KEY_FILE}" ]]; then
        rm -f "${TEMP_NOTARY_KEY_FILE}"
    fi
}

trap cleanup EXIT

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "Required command not found: $1"
        exit 1
    fi
}

resolve_developer_id_identity() {
    local identity_output identity_line
    identity_output=$(security find-identity -v -p codesigning)

    if [[ -n "${DEVELOPER_ID_IDENTITY}" ]]; then
        if [[ "${DEVELOPER_ID_IDENTITY}" =~ ^[A-Fa-f0-9]{40}$ ]]; then
            if [[ -z "${DEVELOPER_ID_IDENTITY_NAME}" ]]; then
                DEVELOPER_ID_IDENTITY_NAME=$(awk -v hash="${DEVELOPER_ID_IDENTITY}" -F '"' '$0 ~ hash { print $2; exit }' <<< "${identity_output}")
            fi
            return
        fi

        identity_line=$(awk -v name="${DEVELOPER_ID_IDENTITY}" -F '"' '$2 == name { print $0; exit }' <<< "${identity_output}")
        if [[ -z "${identity_line}" ]]; then
            log_error "Developer ID identity not found in Keychain: ${DEVELOPER_ID_IDENTITY}"
            echo "${identity_output}" || true
            exit 1
        fi

        DEVELOPER_ID_IDENTITY_NAME="${DEVELOPER_ID_IDENTITY}"
        DEVELOPER_ID_IDENTITY=$(awk '{print $2}' <<< "${identity_line}")
        return
    fi

    identity_line=$(awk -F '"' '$2 ~ /^Developer ID Application:/ { print $0; exit }' <<< "${identity_output}")
    DEVELOPER_ID_IDENTITY_NAME=$(awk -F '"' '{print $2}' <<< "${identity_line}")
    DEVELOPER_ID_IDENTITY=$(awk '{print $2}' <<< "${identity_line}")

    if [[ -z "${DEVELOPER_ID_IDENTITY}" ]]; then
        log_error "No Developer ID Application identity found in Keychain. Install a Developer ID Application certificate or set DEVELOPER_ID_IDENTITY explicitly."
        echo "${identity_output}" || true
        exit 1
    fi
}

load_notary_credentials_from_1password() {
    require_command op
    require_command jq

    local item_args=("${ASC_1PASSWORD_ITEM}" --format json)
    if [[ -n "${ASC_1PASSWORD_VAULT}" ]]; then
        item_args+=(--vault "${ASC_1PASSWORD_VAULT}")
    fi

    local item_json
    item_json=$(op item get "${item_args[@]}")

    if [[ -z "${ASC_KEY_ID}" ]]; then
        ASC_KEY_ID=$(jq -r '.fields[] | select(.label == "Key ID") | .value // empty' <<< "${item_json}")
    fi

    if [[ -z "${ASC_ISSUER_ID}" ]]; then
        ASC_ISSUER_ID=$(jq -r '.fields[] | select(.label == "Issuer ID") | .value // empty' <<< "${item_json}")
    fi

    local vault_id item_id file_name
    vault_id=$(jq -r '.vault.id // empty' <<< "${item_json}")
    item_id=$(jq -r '.id // empty' <<< "${item_json}")

    if [[ -n "${ASC_1PASSWORD_FILE_NAME}" ]]; then
        file_name="${ASC_1PASSWORD_FILE_NAME}"
    else
        file_name=$(jq -r '.files[0].name // empty' <<< "${item_json}")
    fi

    if [[ -z "${ASC_KEY_ID}" || -z "${ASC_ISSUER_ID}" || -z "${vault_id}" || -z "${item_id}" || -z "${file_name}" ]]; then
        log_error "Failed to resolve notary credentials from 1Password item '${ASC_1PASSWORD_ITEM}'."
        exit 1
    fi

    TEMP_NOTARY_KEY_FILE=$(mktemp "${TMPDIR:-/tmp}/AuthKey.XXXXXX")
    op read --force --out-file "${TEMP_NOTARY_KEY_FILE}" "op://${vault_id}/${item_id}/${file_name}" >/dev/null
    chmod 600 "${TEMP_NOTARY_KEY_FILE}"
    ASC_KEY_FILE="${TEMP_NOTARY_KEY_FILE}"
}

prepare_release_signing() {
    require_command codesign
    require_command xcrun

    resolve_developer_id_identity

    if [[ -z "${ASC_KEY_ID}" || -z "${ASC_ISSUER_ID}" || -z "${ASC_KEY_FILE}" ]]; then
        load_notary_credentials_from_1password
    fi

    if [[ ! -f "${ASC_KEY_FILE}" ]]; then
        log_error "Notary API key file not found: ${ASC_KEY_FILE}"
        exit 1
    fi
}

prepare_local_release_signing() {
    require_command codesign

    if [[ -z "${DEVELOPER_ID_IDENTITY}" ]]; then
        log_error "--local-release requires DEVELOPER_ID_IDENTITY to be set explicitly."
        security find-identity -v -p codesigning || true
        exit 1
    fi
}

sign_app_ad_hoc() {
    log_step "Code Signing (Ad-hoc)"
    log_info "Signing app bundle with ad-hoc signature..."
    log_info "Note: Ad-hoc signing requires re-granting Accessibility permission after each build."
    sign_embedded_frameworks --sign -
    codesign --force --deep --sign - "${APP_BUNDLE}"
    log_info "Verifying signature..."
    codesign --verify --deep --verbose=1 "${APP_BUNDLE}"
    log_success "Ad-hoc code signing completed"
}

sign_app_release() {
    log_step "Code Signing (Developer ID)"
    if [[ -n "${DEVELOPER_ID_IDENTITY_NAME}" ]]; then
        log_info "Signing app bundle with Developer ID identity: ${DEVELOPER_ID_IDENTITY_NAME} [${DEVELOPER_ID_IDENTITY}]"
    else
        log_info "Signing app bundle with Developer ID identity: ${DEVELOPER_ID_IDENTITY}"
    fi
    sign_embedded_frameworks \
        --sign "${DEVELOPER_ID_IDENTITY}" \
        --options runtime \
        --timestamp

    codesign \
        --force \
        --sign "${DEVELOPER_ID_IDENTITY}" \
        --options runtime \
        --timestamp \
        "${APP_BUNDLE}"

    log_info "Verifying app signature..."
    codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
    log_success "Developer ID code signing completed"
}

sign_embedded_frameworks() {
    if [[ ! -d "${APP_FRAMEWORKS_DIR}" ]]; then
        return
    fi

    local signing_args=("$@")
    local framework

    for framework in "${APP_FRAMEWORKS_DIR}"/*.framework; do
        [[ -e "${framework}" ]] || continue
        log_info "Signing embedded framework: $(basename "${framework}")"
        codesign --force --deep "${signing_args[@]}" "${framework}"
    done
}

copy_embedded_frameworks() {
    if [[ ! -d "${SPARKLE_FRAMEWORK_SOURCE}" ]]; then
        log_error "Sparkle.framework not found at ${SPARKLE_FRAMEWORK_SOURCE}. Run 'swift package resolve' and build again."
        exit 1
    fi

    log_info "Embedding Sparkle.framework..."
    mkdir -p "${APP_FRAMEWORKS_DIR}"
    rm -rf "${APP_FRAMEWORKS_DIR}/Sparkle.framework"
    ditto "${SPARKLE_FRAMEWORK_SOURCE}" "${APP_FRAMEWORKS_DIR}/Sparkle.framework"
}

ensure_framework_rpath() {
    local binary_path="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

    if otool -l "${binary_path}" | grep -Fq "@executable_path/../Frameworks"; then
        return
    fi

    log_info "Adding app bundle framework rpath..."
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${binary_path}"
}

disable_updater_metadata() {
    local staged_info_plist="${APP_BUNDLE}/Contents/Info.plist"
    local key

    log_info "Removing Sparkle updater metadata from local app bundle..."
    for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks SUAutomaticallyUpdate; do
        /usr/libexec/PlistBuddy -c "Delete :${key}" "${staged_info_plist}" >/dev/null 2>&1 || true
    done
}

create_dmg_background() {
    local output_path="$1"

    if [[ ! -f "${DMG_BACKGROUND_SOURCE}" ]]; then
        log_error "DMG background asset not found: ${DMG_BACKGROUND_SOURCE}"
        exit 1
    fi

    cp "${DMG_BACKGROUND_SOURCE}" "${output_path}"
}

apply_dmg_finder_layout() {
    log_info "Applying Finder window layout..."

    /usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
    set dmgFolder to POSIX file "${DMG_MOUNT}" as alias
    set backgroundImage to file ((dmgFolder as text) & ".background:${DMG_BACKGROUND_NAME}")
    tell folder dmgFolder
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {120, 120, 840, 600}

        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to backgroundImage

        set position of item "${APP_NAME}.app" of container window to {145, 240}
        set position of item "Applications" of container window to {570, 240}

        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
}

detach_dmg_mount() {
    local attempts=0

    while [[ ${attempts} -lt 5 ]]; do
        if hdiutil detach "${DMG_MOUNT}" -quiet; then
            return
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    hdiutil detach "${DMG_MOUNT}" -force -quiet
}

sign_dmg_release() {
    log_step "DMG Signing"
    if [[ -n "${DEVELOPER_ID_IDENTITY_NAME}" ]]; then
        log_info "Signing DMG with Developer ID identity: ${DEVELOPER_ID_IDENTITY_NAME} [${DEVELOPER_ID_IDENTITY}]"
    else
        log_info "Signing DMG with Developer ID identity..."
    fi
    codesign --force --sign "${DEVELOPER_ID_IDENTITY}" --timestamp "${DMG_PATH}"
    log_success "DMG signed"
}

notarize_dmg_release() {
    log_step "Notarization"
    require_command jq

    log_info "Submitting DMG for notarization..."
    local submission_json submission_status
    submission_json=$(xcrun notarytool submit "${DMG_PATH}" \
        --key "${ASC_KEY_FILE}" \
        --key-id "${ASC_KEY_ID}" \
        --issuer "${ASC_ISSUER_ID}" \
        --wait \
        --output-format json)

    submission_status=$(jq -r '.status // empty' <<< "${submission_json}")
    if [[ "${submission_status}" != "Accepted" ]]; then
        log_error "Notarization failed with status: ${submission_status:-unknown}"
        jq -r '.id // empty' <<< "${submission_json}" | while IFS= read -r submission_id; do
            if [[ -n "${submission_id}" ]]; then
                log_error "Fetch details with: xcrun notarytool log ${submission_id} --key <key-file> --key-id ${ASC_KEY_ID} --issuer ${ASC_ISSUER_ID}"
            fi
        done
        return 1
    fi

    log_info "Stapling notarization ticket..."
    xcrun stapler staple "${DMG_PATH}"

    log_info "Validating stapled DMG..."
    xcrun stapler validate "${DMG_PATH}"

    log_success "Notarization completed"
}

# =============================================================================
# Parse Arguments
# =============================================================================

CLEAN_BUILD=false
RELEASE_MODE=false
LOCAL_RELEASE_MODE=false
SKIP_SIGNING=false
DISABLE_UPDATER=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --release)
            RELEASE_MODE=true
            shift
            ;;
        --local-release)
            LOCAL_RELEASE_MODE=true
            shift
            ;;
        --skip-signing)
            SKIP_SIGNING=true
            shift
            ;;
        --disable-updater)
            DISABLE_UPDATER=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--clean] [--release] [--local-release] [--skip-signing] [--disable-updater] [--help]"
            echo ""
            echo "Options:"
            echo "  --clean    Clean build directory before building"
            echo "  --release  Build, Developer ID sign, notarize, and staple the DMG"
            echo "  --local-release  Build and sign with a locally available identity without notarization"
            echo "  --skip-signing  Build artifacts without signing"
            echo "  --disable-updater  Remove Sparkle updater keys from the staged app bundle"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ "${RELEASE_MODE}" == true && "${LOCAL_RELEASE_MODE}" == true ]]; then
    log_error "--release and --local-release cannot be used together"
    exit 1
fi

if [[ ( "${RELEASE_MODE}" == true || "${LOCAL_RELEASE_MODE}" == true ) && "${SKIP_SIGNING}" == true ]]; then
    log_error "--skip-signing cannot be used with --release or --local-release"
    exit 1
fi

SIGNING_MODE="adhoc"
if [[ "${SKIP_SIGNING}" == true ]]; then
    SIGNING_MODE="none"
elif [[ "${RELEASE_MODE}" == true ]]; then
    SIGNING_MODE="release"
    prepare_release_signing
elif [[ "${LOCAL_RELEASE_MODE}" == true ]]; then
    SIGNING_MODE="local-release"
    prepare_local_release_signing
fi

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

if [[ "${DISABLE_UPDATER}" == true ]]; then
    disable_updater_metadata
fi

# Copy app icon
log_info "Copying app icon..."
if [[ -f "${PROJECT_DIR}/Sources/${APP_NAME}/Resources/AppIcon.icns" ]]; then
    cp "${PROJECT_DIR}/Sources/${APP_NAME}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
    log_success "App icon copied"
else
    log_info "No app icon found at Sources/${APP_NAME}/Resources/AppIcon.icns"
fi

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

copy_embedded_frameworks
ensure_framework_rpath

log_success "App bundle created at ${APP_BUNDLE}"

# =============================================================================
# Code Signing
# =============================================================================

case "${SIGNING_MODE}" in
    none)
        log_step "Code Signing"
        log_info "Skipping code signing (--skip-signing)"
        ;;
    adhoc)
        sign_app_ad_hoc
        ;;
    local-release)
        sign_app_release
        ;;
    release)
        sign_app_release
        ;;
esac

# =============================================================================
# Create DMG
# =============================================================================

log_step "Creating DMG"

# Clean up any existing DMG staging
rm -rf "${DMG_STAGING}"
rm -rf "${DMG_MOUNT}"
rm -f "${DMG_PATH}"
rm -f "${DMG_RW_PATH}"

# Create staging directory
log_info "Preparing DMG contents..."
mkdir -p "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}/.background"

# Copy app to staging
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"

# Create Applications symlink
ln -s /Applications "${DMG_STAGING}/Applications"

create_dmg_background "${DMG_STAGING}/.background/${DMG_BACKGROUND_NAME}"

log_info "Creating read/write DMG image..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDRW \
    -fs HFS+ \
    "${DMG_RW_PATH}"

mkdir -p "${DMG_MOUNT}"
hdiutil attach "${DMG_RW_PATH}" \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "${DMG_MOUNT}" \
    -quiet

apply_dmg_finder_layout
if ! bless --folder "${DMG_MOUNT}" --openfolder "${DMG_MOUNT}" 2>/dev/null; then
    log_info "Skipping DMG auto-open metadata; this macOS host does not support bless --openfolder."
fi
sync
detach_dmg_mount
rmdir "${DMG_MOUNT}"

log_info "Converting to compressed DMG image..."
hdiutil convert "${DMG_RW_PATH}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG_PATH}" \
    -quiet

rm -f "${DMG_RW_PATH}"

log_success "DMG created at ${DMG_PATH}"

# Clean up staging
rm -rf "${DMG_STAGING}"

# =============================================================================
# Release Signing And Notarization
# =============================================================================

if [[ "${SIGNING_MODE}" == "local-release" || "${SIGNING_MODE}" == "release" ]]; then
    sign_dmg_release
fi

if [[ "${SIGNING_MODE}" == "release" ]]; then
    notarize_dmg_release
fi

# =============================================================================
# Summary
# =============================================================================

log_step "Build Complete!"

echo ""
echo "  App Bundle: ${APP_BUNDLE}"
echo "  DMG:        ${DMG_PATH}"
echo ""
echo "  Signing Mode: ${SIGNING_MODE}"
echo ""
echo "  To test the app:"
echo "    open \"${APP_BUNDLE}\""
echo ""
echo "  To install from DMG:"
echo "    open \"${DMG_PATH}\""
echo "    Drag ${APP_NAME} to Applications"
echo ""

if [[ "${SIGNING_MODE}" == "adhoc" ]]; then
    echo "  ⚠️  IMPORTANT: After each ad-hoc build, you must re-grant Accessibility permission:"
    echo "    1. Open System Settings > Privacy & Security > Accessibility"
    echo "    2. Remove ${APP_NAME} if present (click -, or select and delete)"
    echo "    3. Add the new ${APP_NAME}.app (click +)"
    echo "    4. Restart the app"
    echo ""
elif [[ "${SIGNING_MODE}" == "none" ]]; then
    echo "  Note: Artifacts were created unsigned for external signing workflows."
    echo ""
elif [[ "${SIGNING_MODE}" == "local-release" ]]; then
    echo "  Local release artifacts were signed with the configured local identity."
    echo "  They were not notarized or stapled."
    echo ""
elif [[ "${SIGNING_MODE}" == "release" ]]; then
    echo "  Release artifacts were Developer ID signed, notarized, and stapled."
    echo ""
fi

# Get file sizes
APP_SIZE=$(du -sh "${APP_BUNDLE}" | cut -f1)
DMG_SIZE=$(du -sh "${DMG_PATH}" | cut -f1)

echo "  Sizes:"
echo "    App: ${APP_SIZE}"
echo "    DMG: ${DMG_SIZE}"
echo ""
