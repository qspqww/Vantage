#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Vantage.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_WORK_DIR="$ROOT_DIR/.build/Vantage.iconset"
BUILD_HOME="$ROOT_DIR/.build/home"
BUILD_CACHE="$ROOT_DIR/.build/cache"
CLANG_CACHE="$ROOT_DIR/.build/clang-module-cache"
SWIFTPM_CACHE="$ROOT_DIR/.build/swiftpm-module-cache"

cd "$ROOT_DIR"
env \
    HOME="$BUILD_HOME" \
    XDG_CACHE_HOME="$BUILD_CACHE" \
    CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE" \
    swift build -c "$CONFIGURATION" --product Vantage

rm -rf "$APP_DIR" "$ICON_WORK_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICON_WORK_DIR" "$DIST_DIR"

cp "$BUILD_DIR/Vantage" "$MACOS_DIR/Vantage"
cp "$ROOT_DIR/Config/Info.plist" "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

# Keep the generated SwiftPM resource bundle in Contents/Resources so
# localization catalogs are available in the signed application bundle.
RESOURCE_BUNDLE="$BUILD_DIR/Vantage_Vantage.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "Missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
    exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/Vantage_Vantage.bundle"

ICON_SOURCE="$ROOT_DIR/.build/Vantage-AppIcon-1024.png"
env \
    HOME="$BUILD_HOME" \
    XDG_CACHE_HOME="$BUILD_CACHE" \
    CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
    swift "$ROOT_DIR/Scripts/GenerateIcon.swift" "$ICON_SOURCE"

sips -z 16 16 "$ICON_SOURCE" --out "$ICON_WORK_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICON_WORK_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICON_WORK_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICON_WORK_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICON_WORK_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICON_WORK_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICON_WORK_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICON_WORK_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICON_WORK_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICON_WORK_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICON_WORK_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

if [[ "${SKIP_SIGN:-0}" != "1" ]]; then
    SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        SIGNING_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
    fi

    if [[ -z "$SIGNING_IDENTITY" ]]; then
        echo "No Apple Development signing identity found." >&2
        echo "Set CODE_SIGN_IDENTITY or run with SKIP_SIGN=1." >&2
        exit 1
    fi

    codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi

echo "$APP_DIR"
