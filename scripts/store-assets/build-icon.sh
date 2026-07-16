#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
SOURCE="$ROOT/store-assets/icon/AppIcon.svg"
ICON_DIR="$ROOT/store-assets/icon"
ICONSET="$ICON_DIR/AppIcon.iconset"

mkdir -p "$ICONSET"

magick -background none "$SOURCE" -resize 1024x1024 "PNG32:$ICON_DIR/AppIcon-1024.png"

for size in 16 32 128 256 512; do
  magick "$ICON_DIR/AppIcon-1024.png" -resize "${size}x${size}" "PNG32:$ICONSET/icon_${size}x${size}.png"
  double=$((size * 2))
  magick "$ICON_DIR/AppIcon-1024.png" -resize "${double}x${double}" "PNG32:$ICONSET/icon_${size}x${size}@2x.png"
done

swift -module-cache-path "${TMPDIR:-/tmp}/svn-mac-icon-module-cache" \
  "$ROOT/scripts/store-assets/build-icns.swift" "$ICONSET" "$ROOT/Resources/AppIcon.icns"

echo "$ICON_DIR/AppIcon-1024.png"
echo "$ROOT/Resources/AppIcon.icns"
