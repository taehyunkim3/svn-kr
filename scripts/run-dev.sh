#!/bin/zsh
# 개발용 앱 번들을 만들어 실행합니다.
# `swift run SVNMac`은 Info.plist가 없는 맨 실행 파일이라 창이 앞으로 나오지 않습니다.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

APP="${SVN_MAC_DEV_APP:-${TMPDIR:-/tmp}/SVNMacDev.app}"
CONFIGURATION="${CONFIGURATION:-debug}"

swift build -c "$CONFIGURATION"

BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

# 이전 인스턴스를 먼저 정리하지 않으면 옛 코드가 뜬 창과 구분되지 않습니다.
pkill -f "$APP/Contents/MacOS/SVNMac" 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/SVNMac" "$APP/Contents/MacOS/SVNMac"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$BUILD_DIR/SVNMac_SVNMac.bundle" "$APP/Contents/Resources/"
codesign --sign - --force "$APP" >/dev/null

open "$APP"
echo "실행: $APP"
