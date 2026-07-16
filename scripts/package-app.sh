#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

CACHE_ROOT="${TMPDIR:-/tmp}/svn-mac-build-cache"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$CACHE_ROOT/clang}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CACHE_ROOT/swiftpm}"

swift build --disable-sandbox -c release

APP="$ROOT/dist/SVN Mac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/SVNMac" "$APP/Contents/MacOS/SVNMac"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
"$ROOT/scripts/embed-svn.sh" "$APP"

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  SIGN_ARGUMENTS=(--force --sign -)
else
  SIGN_ARGUMENTS=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
fi

for binary in "$APP"/Contents/Frameworks/*.dylib "$APP/Contents/Resources/bin/svn"; do
  codesign "${SIGN_ARGUMENTS[@]}" "$binary"
done
codesign "${SIGN_ARGUMENTS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/Resources/bin/svn" --version --quiet

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(uname -m)
ARCHIVE="$ROOT/dist/SVN-Mac-$VERSION-$ARCH.zip"
rm -f "$ARCHIVE"
ditto -c -k --keepParent "$APP" "$ARCHIVE"

echo "$APP"
echo "$ARCHIVE"
