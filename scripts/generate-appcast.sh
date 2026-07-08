#!/usr/bin/env bash
#
# Generate a Sparkle appcast for the notarized release DMG.
#
# Required:
#   - SPARKLE_ED_PRIVATE_KEY, SPARKLE_PRIVATE_KEY_FILE, or SPARKLE_KEYCHAIN_ACCOUNT
#
# Optional:
#   - APP_VERSION
#   - GITHUB_REPOSITORY
#   - SPARKLE_DMG_PATH
#   - SPARKLE_DOWNLOAD_URL_PREFIX
#   - SPARKLE_FULL_RELEASE_NOTES_URL
#   - SPARKLE_GENERATE_APPCAST
#   - SPARKLE_KEYCHAIN_ACCOUNT

set -euo pipefail

APP_NAME="LGTVMenuBar"
DEFAULT_REPOSITORY="thesammykins/LGTVMenuBar"
DEFAULT_KEYCHAIN_ACCOUNT="com.thesammykins.lgtvmenubar"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INFO_PLIST="${PROJECT_DIR}/Sources/${APP_NAME}/Info.plist"
RELEASE_DIR="${PROJECT_DIR}/release"
APPCAST_WORK_DIR="${RELEASE_DIR}/sparkle-appcast"
APPCAST_PATH="${RELEASE_DIR}/appcast.xml"
GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"
KEYCHAIN_ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-${DEFAULT_KEYCHAIN_ACCOUNT}}"

log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ $1" >&2
}

if [[ -n "${APP_VERSION:-}" ]]; then
    VERSION="${APP_VERSION}"
else
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST}" 2>/dev/null || echo "")
fi

if [[ -z "${VERSION}" ]]; then
    log_error "Unable to determine app version. Set APP_VERSION or update ${INFO_PLIST}."
    exit 1
fi

REPOSITORY="${GITHUB_REPOSITORY:-${DEFAULT_REPOSITORY}}"
DMG_NAME="${APP_NAME}-${VERSION}-universal.dmg"
DMG_PATH="${SPARKLE_DMG_PATH:-${RELEASE_DIR}/${DMG_NAME}}"
DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/${REPOSITORY}/releases/download/v${VERSION}/}"
FULL_RELEASE_NOTES_URL="${SPARKLE_FULL_RELEASE_NOTES_URL:-https://github.com/${REPOSITORY}/releases/tag/v${VERSION}}"

if [[ ! -x "${GENERATE_APPCAST}" ]]; then
    log_error "Sparkle generate_appcast tool not found at ${GENERATE_APPCAST}."
    log_error "Run 'swift package resolve' before generating the appcast."
    exit 1
fi

if [[ ! -f "${DMG_PATH}" ]]; then
    log_error "DMG not found: ${DMG_PATH}"
    exit 1
fi

if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" && -z "${SPARKLE_ED_PRIVATE_KEY:-}" && -z "${KEYCHAIN_ACCOUNT}" ]]; then
    log_error "Missing Sparkle signing key. Set SPARKLE_ED_PRIVATE_KEY, SPARKLE_PRIVATE_KEY_FILE, or SPARKLE_KEYCHAIN_ACCOUNT."
    exit 1
fi

rm -rf "${APPCAST_WORK_DIR}"
mkdir -p "${APPCAST_WORK_DIR}"
cp "${DMG_PATH}" "${APPCAST_WORK_DIR}/${DMG_NAME}"

log_info "Generating Sparkle appcast for ${DMG_NAME}"

APPCAST_ARGS=(
    --download-url-prefix "${DOWNLOAD_URL_PREFIX}"
    --full-release-notes-url "${FULL_RELEASE_NOTES_URL}"
    --link "https://github.com/${REPOSITORY}"
    --maximum-versions 1
    -o "${APPCAST_WORK_DIR}/appcast.xml"
    "${APPCAST_WORK_DIR}"
)

if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    "${GENERATE_APPCAST}" --ed-key-file "${SPARKLE_PRIVATE_KEY_FILE}" "${APPCAST_ARGS[@]}"
elif [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    printf '%s' "${SPARKLE_ED_PRIVATE_KEY}" | "${GENERATE_APPCAST}" --ed-key-file - "${APPCAST_ARGS[@]}"
else
    "${GENERATE_APPCAST}" --account "${KEYCHAIN_ACCOUNT}" "${APPCAST_ARGS[@]}"
fi

cp "${APPCAST_WORK_DIR}/appcast.xml" "${APPCAST_PATH}"
log_success "Appcast written to ${APPCAST_PATH}"
