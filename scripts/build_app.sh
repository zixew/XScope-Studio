#!/usr/bin/env bash
set -euo pipefail

# Resolve real physical directory even if invoked through a symlink
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
ROOT_DIR="$(cd -P "$SCRIPT_DIR/.." && pwd)"

APP_NAME="XScope Studio.app"
DMG_NAME="XScopeStudio.dmg"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME"
RELEASES_DIR="$DIST_DIR/releases"
LAST_VER_DIR="$RELEASES_DIR/last_version"
NEW_VER_DIR="$RELEASES_DIR/new_version"

INSTALL_TO_APPS=false
RUN_TESTS=true

for arg in "$@"; do
    case "$arg" in
        --install) INSTALL_TO_APPS=true ;;
        --no-test) RUN_TESTS=false ;;
    esac
done

cd "$ROOT_DIR"

if [ "$RUN_TESTS" = true ]; then
    echo "Running unit tests..."
    swift test
fi

echo "Building DevCompanionMac (release)..."
rm -rf "$BUILD_DIR/DevCompanionMac_DevCompanionMac.bundle"
swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/DevCompanionMac" "$APP_BUNDLE/Contents/MacOS/DevCompanionMac"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "$ROOT_DIR/Packaging/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Packaging/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

if [ -d "$BUILD_DIR/DevCompanionMac_DevCompanionMac.bundle" ]; then
    cp -R "$BUILD_DIR/DevCompanionMac_DevCompanionMac.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --deep --options runtime --entitlements "$ROOT_DIR/Packaging/DevCompanion.entitlements" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo "Built $APP_BUNDLE"

# 1. Rotate previous new_version -> last_version before creating new release
mkdir -p "$LAST_VER_DIR" "$NEW_VER_DIR"
if [ -f "$NEW_VER_DIR/$DMG_NAME" ] || [ -f "$NEW_VER_DIR/DevCompanion.app.zip" ]; then
    echo "Rotating previous release into last_version/..."
    rm -rf "$LAST_VER_DIR"/*
    cp -R "$NEW_VER_DIR"/* "$LAST_VER_DIR"/ 2>/dev/null || true
fi

# 2. Build portable drag-and-drop .dmg installer for other Macs
echo "Packaging $DMG_NAME installer..."
DMG_STAGING="$DIST_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
ditto "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME"
ln -s /Applications "$DMG_STAGING/Applications"

DMG_OUT="$DIST_DIR/$DMG_NAME"
rm -f "$DMG_OUT"
hdiutil create -volname "XScope Studio Installer" -srcfolder "$DMG_STAGING" -ov -format UDZO -quiet "$DMG_OUT"
rm -rf "$DMG_STAGING"

# 3. Populate new_version/ with .dmg, timestamped .dmg, .app.zip, session data backup, and BUILD_INFO.txt
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
VERSION_STR="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/Packaging/Info.plist" 2>/dev/null || echo "1.0.0")"

rm -rf "$NEW_VER_DIR"/*
cp "$DMG_OUT" "$NEW_VER_DIR/$DMG_NAME"
cp "$DMG_OUT" "$NEW_VER_DIR/XScopeStudio-v${VERSION_STR}-${TIMESTAMP}.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$NEW_VER_DIR/XScopeStudio.app.zip"

SESSIONS_SRC="$HOME/Library/Application Support/DevCompanion/Sessions"
if [ -d "$SESSIONS_SRC" ]; then
    mkdir -p "$NEW_VER_DIR/Sessions_Backup"
    cp -R "$SESSIONS_SRC"/* "$NEW_VER_DIR/Sessions_Backup"/ 2>/dev/null || true
fi

cat > "$NEW_VER_DIR/BUILD_INFO.txt" <<EOF
App: XScope Studio
Version: ${VERSION_STR}
Build Timestamp: ${TIMESTAMP}
Source Path: ${ROOT_DIR}
Installer DMG: ${DMG_NAME}
Architecture: $(uname -m)
macOS: $(sw_vers -productVersion)
EOF

# If last_version/ is still empty (first ever run), seed it with initial release so both folders are ready
if [ ! -f "$LAST_VER_DIR/$DMG_NAME" ]; then
    cp -R "$NEW_VER_DIR"/* "$LAST_VER_DIR"/ 2>/dev/null || true
fi

echo "Release artifacts ready in $RELEASES_DIR (last_version & new_version)"

# 4. Sync last_version/ and new_version/ (plus Source_Backup) to iCloud Drive & Google Drive (if mounted)
sync_to_cloud_dir() {
    local CLOUD_BASE="$1"
    local DEST_REL="$CLOUD_BASE/DevCompanionReleases"
    mkdir -p "$DEST_REL/last_version" "$DEST_REL/new_version" "$DEST_REL/Source_Backup"
    rm -rf "$DEST_REL/last_version"/* "$DEST_REL/new_version"/*
    cp -R "$LAST_VER_DIR"/* "$DEST_REL/last_version"/ 2>/dev/null || true
    cp -R "$NEW_VER_DIR"/* "$DEST_REL/new_version"/ 2>/dev/null || true
    rsync -a --delete \
        --exclude '.build' \
        --exclude 'dist' \
        --exclude '.git' \
        "$ROOT_DIR/" "$DEST_REL/Source_Backup/" 2>/dev/null || true
    echo "Synced last_version, new_version & Source_Backup to: $DEST_REL"
}

ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
if [ -d "$ICLOUD_DIR" ]; then
    sync_to_cloud_dir "$ICLOUD_DIR"
fi

if [ -d "$HOME/Library/CloudStorage" ]; then
    for GDRIVE in "$HOME/Library/CloudStorage"/GoogleDrive-*; do
        if [ -d "$GDRIVE/My Drive" ]; then
            sync_to_cloud_dir "$GDRIVE/My Drive"
        elif [ -d "$GDRIVE" ]; then
            sync_to_cloud_dir "$GDRIVE"
        fi
    done
fi

if [ "$INSTALL_TO_APPS" = true ]; then
    TARGET_DIR="/Applications"
    if [ ! -w "$TARGET_DIR" ]; then
        TARGET_DIR="$HOME/Applications"
        mkdir -p "$TARGET_DIR"
    fi
    DEST_APP="$TARGET_DIR/$APP_NAME"

    echo "Stopping running DevCompanionMac (if any)..."
    pkill -x DevCompanionMac || true
    sleep 0.5

    echo "Installing to $DEST_APP..."
    rm -rf "$TARGET_DIR/DevCompanion.app"
    rm -rf "$DEST_APP"
    ditto "$APP_BUNDLE" "$DEST_APP"
    codesign --verify --deep --strict "$DEST_APP"
    echo "Installed $DEST_APP"
    open "$DEST_APP"
fi
