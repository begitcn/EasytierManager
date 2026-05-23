#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================
# Configuration
# ============================================================
EASYTIER_VERSION="2.6.4"
APP_VERSION="1.0.0"
CACHE_DIR="$HOME/Library/Caches/com.easytier.manager/easytier-binaries"
HELPERS_DIR="$SCRIPT_DIR/Helpers"
DIST_DIR="$SCRIPT_DIR/dist"
BUILD_DIR="$SCRIPT_DIR/build"

# ============================================================
# Architecture detection
# ============================================================
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) EASYTIER_ARCH="x86_64" ;;
    arm64)  EASYTIER_ARCH="aarch64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ============================================================
# Helpers
# ============================================================
usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --help       Show this help
  --download   Only download easytier binaries, skip build
  --dev        Prepare dev environment (download + configure project)

Without options, performs a full release build.
EOF
    exit 0
}

download_easytier() {
    local arch="$1"
    local version="$2"
    local out_dir="$3"

    local zip_name="easytier-macos-${arch}-v${version}.zip"
    local cache_file="$CACHE_DIR/$zip_name"

    mkdir -p "$CACHE_DIR" "$out_dir"

    if [ ! -f "$cache_file" ]; then
        local url="https://github.com/EasyTier/Easytier/releases/download/v${version}/${zip_name}"
        echo "   Downloading $url"
        curl -L -o "$cache_file" "$url"
        echo "   Cached to $cache_file"
    else
        echo "   Using cached $cache_file"
    fi

    local temp_dir
    temp_dir=$(mktemp -d)
    unzip -o "$cache_file" -d "$temp_dir"

    local extracted_dir="$temp_dir/easytier-macos-${arch}"
    if [ -d "$extracted_dir" ]; then
        cp "$extracted_dir/easytier-core" "$extracted_dir/easytier-cli" "$out_dir/"
        chmod +x "$out_dir/easytier-core" "$out_dir/easytier-cli"
        rm -rf "$temp_dir"
        echo "   Extracted easytier-core and easytier-cli to $out_dir"
    else
        rm -rf "$temp_dir"
        echo "Error: unexpected zip structure"
        exit 1
    fi
}

# ============================================================
# Parse args
# ============================================================
ONLY_DOWNLOAD=false
DEV_MODE=false

for arg in "$@"; do
    case "$arg" in
        --help) usage ;;
        --download) ONLY_DOWNLOAD=true ;;
        --dev) DEV_MODE=true ;;
    esac
done

# ============================================================
# Step 1: Ensure easytier binaries
# ============================================================
echo "==> EasyTierManager Build"
echo "    Architecture: $EASYTIER_ARCH"
echo "    EasyTier: v$EASYTIER_VERSION"
echo ""

if [ ! -x "$HELPERS_DIR/easytier-core" ] || [ ! -x "$HELPERS_DIR/easytier-cli" ]; then
    echo "Downloading EasyTier v$EASYTIER_VERSION ($EASYTIER_ARCH)..."
    download_easytier "$EASYTIER_ARCH" "$EASYTIER_VERSION" "$HELPERS_DIR"
else
    echo "easytier binaries already present in $HELPERS_DIR"
fi

# Show version
if [ -x "$HELPERS_DIR/easytier-core" ]; then
    LOCAL_VERSION=$("$HELPERS_DIR/easytier-core" --version 2>/dev/null || true)
    echo "   easytier-core: $LOCAL_VERSION"
fi

if [ "$ONLY_DOWNLOAD" = true ]; then
    echo ""
    echo "Download complete. Binaries in $HELPERS_DIR"
    exit 0
fi

# Dev mode: generate xcodeproj and exit
if [ "$DEV_MODE" = true ]; then
    echo ""
    echo "Generating Xcode project..."
    rm -rf EasyTierManager.xcodeproj
    xcodegen generate
    echo ""
    echo "Dev environment ready. Open EasyTierManager.xcodeproj and build from Xcode."
    echo "The post-compile script will copy Helpers/ into the app bundle."
    exit 0
fi

# ============================================================
# Step 2: Generate Xcode project and build
# ============================================================
echo ""
echo "Building EasyTierManager..."

rm -rf EasyTierManager.xcodeproj "$BUILD_DIR"
xcodegen generate

xcodebuild \
    -project EasyTierManager.xcodeproj \
    -scheme EasyTierManager \
    -configuration Release \
    build \
    SYMROOT="$BUILD_DIR" \
    MARKETING_VERSION="$APP_VERSION" \
    CURRENT_PROJECT_VERSION="1"

xcodebuild \
    -project EasyTierManager.xcodeproj \
    -scheme EasyTierHelper \
    -configuration Release \
    build \
    SYMROOT="$BUILD_DIR" \
    MARKETING_VERSION="$APP_VERSION" \
    CURRENT_PROJECT_VERSION="1"

echo "   Build complete"

# ============================================================
# Step 3: Embed Helpers in app bundle
# ============================================================
APP_BUNDLE="$BUILD_DIR/Release/EasyTierManager.app"
APP_HELPERS="$APP_BUNDLE/Contents/Helpers"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: app bundle not found at $APP_BUNDLE"
    exit 1
fi

mkdir -p "$APP_HELPERS"
cp "$HELPERS_DIR/easytier-core" "$HELPERS_DIR/easytier-cli" "$APP_HELPERS/"
chmod +x "$APP_HELPERS/easytier-core" "$APP_HELPERS/easytier-cli"
echo "   Helpers embedded in app bundle"

HELPER_BIN="$BUILD_DIR/Release/EasyTierHelper"
HELPER_TOOLS_DIR="$APP_BUNDLE/Contents/Library/HelperTools"
HELPER_DAEMONS_DIR="$APP_BUNDLE/Contents/Library/LaunchDaemons"
PLIST_SRC="$SCRIPT_DIR/Resources/com.easytier.manager.helper.plist"

if [ -f "$HELPER_BIN" ]; then
    mkdir -p "$HELPER_TOOLS_DIR"
    cp "$HELPER_BIN" "$HELPER_TOOLS_DIR/com.easytier.manager.helper"
    chmod +x "$HELPER_TOOLS_DIR/com.easytier.manager.helper"

    mkdir -p "$HELPER_DAEMONS_DIR"
    cp "$PLIST_SRC" "$HELPER_DAEMONS_DIR/"
    echo "   Privileged helper embedded in app bundle"
fi

# ============================================================
# Step 4: Create DMG
# ============================================================
echo ""
echo "Creating DMG..."
mkdir -p "$DIST_DIR"

DMG_NAME="EasyTierManager-${EASYTIER_ARCH}-v${APP_VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
TEMP_DMG="$DIST_DIR/.tmp-${DMG_NAME}"

rm -f "$TEMP_DMG" "$DMG_PATH"

DMG_CONTENTS="$DIST_DIR/.dmg-contents"
rm -rf "$DMG_CONTENTS"
mkdir -p "$DMG_CONTENTS"
cp -R "$APP_BUNDLE" "$DMG_CONTENTS/"
ln -s /Applications "$DMG_CONTENTS/Applications"

hdiutil create \
    -volname "EasyTierManager" \
    -srcfolder "$DMG_CONTENTS" \
    -ov \
    -format UDZO \
    "$TEMP_DMG"

mv "$TEMP_DMG" "$DMG_PATH"
rm -rf "$DMG_CONTENTS"

echo "   DMG created: $DMG_PATH"
echo ""
echo "Done!"
