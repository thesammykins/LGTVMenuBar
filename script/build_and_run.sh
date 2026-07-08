#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PRODUCT_NAME="LGTVMenuBar"
UX_PROCESS_NAME="LGTVMenuBarUXTesting"
BUNDLE_ID="com.thesammykins.lgtvmenubar.ux-testing"
MIN_SYSTEM_VERSION="15.0"
WINDOW_TITLE="LGTV Menu Bar UX Validation"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/UXTesting"
APP_BUNDLE="$DIST_DIR/$UX_PROCESS_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$UX_PROCESS_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SCREENSHOT_PATH="$ROOT_DIR/screenshots/ux-testing-window.png"
SPARKLE_FRAMEWORK_SOURCE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

usage() {
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--screenshot]" >&2
    exit 2
}

build_bundle() {
    pkill -x "$UX_PROCESS_NAME" >/dev/null 2>&1 || true

    swift build --product "$PRODUCT_NAME" -Xswiftc -D -Xswiftc UX_TESTING_APP
    BUILD_BINARY="$(swift build --show-bin-path)/$PRODUCT_NAME"

    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_MACOS" "$APP_RESOURCES"
    cp "$BUILD_BINARY" "$APP_BINARY"
    chmod +x "$APP_BINARY"
    copy_sparkle_framework
    ensure_framework_rpath

    if [[ -f "$ROOT_DIR/Sources/LGTVMenuBar/Resources/AppIcon.icns" ]]; then
        cp "$ROOT_DIR/Sources/LGTVMenuBar/Resources/AppIcon.icns" "$APP_RESOURCES/"
    fi

    cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$UX_PROCESS_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>LGTV Menu Bar UX Testing</string>
  <key>CFBundleDisplayName</key>
  <string>LGTV Menu Bar UX Testing</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>LGTV Menu Bar needs local network access to communicate with your LG TV.</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>LGTV Menu Bar needs Accessibility permission to capture volume keys for TV control.</string>
</dict>
</plist>
PLIST

    codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
}

copy_sparkle_framework() {
    if [[ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
        return
    fi

    mkdir -p "$APP_FRAMEWORKS"
    rm -rf "$APP_FRAMEWORKS/Sparkle.framework"
    ditto "$SPARKLE_FRAMEWORK_SOURCE" "$APP_FRAMEWORKS/Sparkle.framework"
}

ensure_framework_rpath() {
    if otool -l "$APP_BINARY" | grep -Fq "@executable_path/../Frameworks"; then
        return
    fi

    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
}

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

stop_app() {
    pkill -x "$UX_PROCESS_NAME" >/dev/null 2>&1 || true
}

window_bounds() {
    /usr/bin/osascript <<APPLESCRIPT 2>/dev/null || true
tell application "System Events"
  if not (exists process "$UX_PROCESS_NAME") then return ""
  tell process "$UX_PROCESS_NAME"
    set frontmost to true
    repeat 40 times
      if exists window "$WINDOW_TITLE" then exit repeat
      if exists window 1 then exit repeat
      delay 0.1
    end repeat
    if exists window "$WINDOW_TITLE" then
      set targetWindow to window "$WINDOW_TITLE"
    else if exists window 1 then
      set targetWindow to window 1
    else
      return ""
    end if
    set windowPosition to position of targetWindow
    set windowSize to size of targetWindow
    return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
  end tell
end tell
APPLESCRIPT
}

window_id() {
    /usr/bin/osascript <<APPLESCRIPT 2>/dev/null || true
tell application "System Events"
  if not (exists process "$UX_PROCESS_NAME") then return ""
  tell process "$UX_PROCESS_NAME"
    set frontmost to true
    repeat 20 times
      if exists window "$WINDOW_TITLE" then exit repeat
      if exists window 1 then exit repeat
      delay 0.1
    end repeat
    if exists window "$WINDOW_TITLE" then
      return id of window "$WINDOW_TITLE"
    else if exists window 1 then
      return id of window 1
    else
      return ""
    end if
  end tell
end tell
APPLESCRIPT
}

wait_for_window() {
    local bounds

    for _ in {1..40}; do
        bounds="$(window_bounds)"
        if [[ -n "$bounds" ]]; then
            return 0
        fi
        sleep 0.25
    done

    return 1
}

capture_screenshot() {
    local bounds capture_window_id

    mkdir -p "$(dirname "$SCREENSHOT_PATH")"

    capture_window_id="$(window_id)"
    if [[ "$capture_window_id" =~ ^[0-9]+$ ]]; then
        /usr/sbin/screencapture -x -l "$capture_window_id" "$SCREENSHOT_PATH"
    else
        bounds="$(window_bounds)"
        if [[ -z "$bounds" ]]; then
            echo "unable to locate $WINDOW_TITLE window for screenshot" >&2
            exit 1
        fi
        /usr/sbin/screencapture -x -R "$bounds" "$SCREENSHOT_PATH"
    fi
    echo "$SCREENSHOT_PATH"
}

build_bundle

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        wait_for_window
        /usr/bin/log stream --info --style compact --predicate "process == \"$UX_PROCESS_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        wait_for_window
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"com.lgtvmenubar\""
        ;;
    --verify|verify)
        open_app
        wait_for_window
        stop_app
        ;;
    --screenshot|screenshot)
        open_app
        wait_for_window
        capture_screenshot
        stop_app
        ;;
    *)
        usage
        ;;
esac
