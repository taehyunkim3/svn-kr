#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

CACHE_ROOT="${TMPDIR:-/tmp}/svn-mac-build-cache"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$CACHE_ROOT/clang}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CACHE_ROOT/swiftpm}"

APP="$ROOT/dist/SVN Mac.app"
DISTRIBUTION="${DISTRIBUTION:-developer-id}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
STORE_ENTITLEMENTS_DIR=""
APP_ENTITLEMENTS=""

# MARK: - 공통 정리

function cleanup() {
  # App Store 권한 파일은 프로비저닝 프로파일에서 추출한 임시 산출물이므로
  # 성공과 실패 여부에 관계없이 스크립트 종료 시 삭제합니다.
  if [[ -n "$STORE_ENTITLEMENTS_DIR" && -d "$STORE_ENTITLEMENTS_DIR" ]]; then
    rm -rf "$STORE_ENTITLEMENTS_DIR"
  fi
}
trap cleanup EXIT

# MARK: - 앱 번들 조립

function build_app_bundle() {
  swift build --disable-sandbox -c release

  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$ROOT/.build/release/SVNMac" "$APP/Contents/MacOS/SVNMac"
  cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
  "$ROOT/scripts/embed-svn.sh" "$APP"
}

# MARK: - 서명 설정

function configure_signing() {
  SIGN_ARGUMENTS=(--force --sign "$SIGN_IDENTITY")
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_ARGUMENTS+=(--options runtime --timestamp)
  fi
}

function prepare_app_store_entitlements() {
  [[ "$DISTRIBUTION" == "app-store" ]] || return 0

  : "${PROVISIONING_PROFILE:?Set PROVISIONING_PROFILE to the Mac App Store provisioning profile path}"
  : "${INSTALLER_SIGN_IDENTITY:?Set INSTALLER_SIGN_IDENTITY to the Mac Installer Distribution certificate name}"
  [[ "$SIGN_IDENTITY" != "-" ]] || {
    print -u2 "Set CODE_SIGN_IDENTITY to an Apple Distribution certificate"
    exit 1
  }

  STORE_ENTITLEMENTS_DIR="${TMPDIR:-/tmp}/svn-mac-store-entitlements-$$"
  local profile_plist="$STORE_ENTITLEMENTS_DIR/profile.plist"
  APP_ENTITLEMENTS="$STORE_ENTITLEMENTS_DIR/app.entitlements"
  mkdir -p "$STORE_ENTITLEMENTS_DIR"
  security cms -D -i "$PROVISIONING_PROFILE" > "$profile_plist"
  /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$profile_plist" > "$APP_ENTITLEMENTS"

  local bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
  local profile_app_id=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$APP_ENTITLEMENTS")
  [[ "$profile_app_id" == *".$bundle_id" ]] || {
    print -u2 "Provisioning profile app identifier '$profile_app_id' does not match '$bundle_id'"
    exit 1
  }

  # 프로파일에 이미 존재하는 권한은 Set, 없는 권한은 Add로 보완합니다.
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
}

function sign_app_bundle() {
  # 다운로드한 프로비저닝 프로파일 등에 붙은 격리 속성이 번들 내부에 남으면
  # App Store Connect 검증이 실패하므로 서명 전에 모두 제거합니다.
  xattr -cr "$APP"

  for binary in "$APP"/Contents/Frameworks/*.dylib(N); do
    codesign "${SIGN_ARGUMENTS[@]}" "$binary"
  done

  if [[ "$DISTRIBUTION" == "app-store" ]]; then
    codesign "${SIGN_ARGUMENTS[@]}" --entitlements "$ROOT/Resources/SVNHelper.entitlements" "$APP/Contents/Helpers/svn"
    codesign "${SIGN_ARGUMENTS[@]}" --entitlements "$APP_ENTITLEMENTS" "$APP"
  else
    codesign "${SIGN_ARGUMENTS[@]}" "$APP/Contents/Helpers/svn"
    codesign "${SIGN_ARGUMENTS[@]}" "$APP"
  fi

  codesign --verify --deep --strict "$APP"
  if [[ "$DISTRIBUTION" != "app-store" ]]; then
    "$APP/Contents/Helpers/svn" --version --quiet
  fi
}

# MARK: - 배포 산출물 생성

function create_zip_archive() {
  local version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
  local architecture=$(uname -m)
  ARCHIVE="$ROOT/dist/SVN-Mac-$version-$architecture.zip"
  rm -f "$ARCHIVE"
  ditto -c -k --keepParent "$APP" "$ARCHIVE"
}

function create_app_store_package() {
  [[ "$DISTRIBUTION" == "app-store" ]] || return 0

  local version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
  PKG="$ROOT/dist/SVN-Mac-$version-app-store.pkg"
  rm -f "$PKG"
  productbuild \
    --component "$APP" /Applications \
    --sign "$INSTALLER_SIGN_IDENTITY" \
    "$PKG"
  pkgutil --check-signature "$PKG"
}

build_app_bundle
configure_signing
prepare_app_store_entitlements
sign_app_bundle
create_zip_archive
create_app_store_package

echo "$APP"
echo "$ARCHIVE"
if [[ "$DISTRIBUTION" == "app-store" ]]; then
  echo "$PKG"
fi
