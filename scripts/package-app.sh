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
cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
"$ROOT/scripts/embed-svn.sh" "$APP"

DISTRIBUTION="${DISTRIBUTION:-developer-id}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGN_ARGUMENTS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_ARGUMENTS+=(--options runtime --timestamp)
fi

if [[ "$DISTRIBUTION" == "app-store" ]]; then
  : "${PROVISIONING_PROFILE:?Set PROVISIONING_PROFILE to the Mac App Store provisioning profile path}"
  : "${INSTALLER_SIGN_IDENTITY:?Set INSTALLER_SIGN_IDENTITY to the Mac Installer Distribution certificate name}"
  [[ "$SIGN_IDENTITY" != "-" ]] || { print -u2 "Set CODE_SIGN_IDENTITY to an Apple Distribution certificate"; exit 1; }

  STORE_ENTITLEMENTS_DIR="${TMPDIR:-/tmp}/svn-mac-store-entitlements-$$"
  PROFILE_PLIST="$STORE_ENTITLEMENTS_DIR/profile.plist"
  APP_ENTITLEMENTS="$STORE_ENTITLEMENTS_DIR/app.entitlements"
  mkdir -p "$STORE_ENTITLEMENTS_DIR"
  security cms -D -i "$PROVISIONING_PROFILE" > "$PROFILE_PLIST"
  /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$PROFILE_PLIST" > "$APP_ENTITLEMENTS"

  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
  PROFILE_APP_ID=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$APP_ENTITLEMENTS")
  [[ "$PROFILE_APP_ID" == *".$BUNDLE_ID" ]] || {
    print -u2 "Provisioning profile app identifier '$PROFILE_APP_ID' does not match '$BUNDLE_ID'"
    exit 1
  }

  for entitlement in \
    com.apple.security.app-sandbox \
    com.apple.security.files.bookmarks.app-scope \
    com.apple.security.files.user-selected.executable \
    com.apple.security.files.user-selected.read-write \
    com.apple.security.network.client; do
    /usr/libexec/PlistBuddy -c "Set :$entitlement true" "$APP_ENTITLEMENTS" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :$entitlement bool true" "$APP_ENTITLEMENTS"
  done

  cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
fi

# Downloaded inputs such as provisioning profiles can carry Gatekeeper metadata.
# App Store Connect rejects a package if any file in the app retains it.
xattr -cr "$APP"

for binary in "$APP"/Contents/Frameworks/*.dylib; do
  codesign "${SIGN_ARGUMENTS[@]}" "$binary"
done

if [[ "$DISTRIBUTION" == "app-store" ]]; then
  codesign "${SIGN_ARGUMENTS[@]}" --entitlements "$ROOT/Resources/SVNHelper.entitlements" "$APP/Contents/Helpers/svn"
  codesign "${SIGN_ARGUMENTS[@]}" --entitlements "$APP_ENTITLEMENTS" "$APP"
  rm -rf "$STORE_ENTITLEMENTS_DIR"
else
  codesign "${SIGN_ARGUMENTS[@]}" "$APP/Contents/Helpers/svn"
  codesign "${SIGN_ARGUMENTS[@]}" "$APP"
fi

codesign --verify --deep --strict "$APP"
if [[ "$DISTRIBUTION" != "app-store" ]]; then
  "$APP/Contents/Helpers/svn" --version --quiet
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(uname -m)
ARCHIVE="$ROOT/dist/SVN-Mac-$VERSION-$ARCH.zip"
rm -f "$ARCHIVE"
ditto -c -k --keepParent "$APP" "$ARCHIVE"

echo "$APP"
echo "$ARCHIVE"

if [[ "$DISTRIBUTION" == "app-store" ]]; then
  PKG="$ROOT/dist/SVN-Mac-$VERSION-app-store.pkg"
  rm -f "$PKG"
  productbuild \
    --component "$APP" /Applications \
    --sign "$INSTALLER_SIGN_IDENTITY" \
    "$PKG"
  pkgutil --check-signature "$PKG"
  echo "$PKG"
fi
