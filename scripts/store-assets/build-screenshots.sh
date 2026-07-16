#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
SOURCE_DIR="$ROOT/store-assets/source"
OUTPUT_DIR="$ROOT/store-assets/screenshots/ko"
TMP_ROOT="${TMPDIR:-/tmp}/svn-mac-store-assets"
FONT_REGULAR="/Users/user/Library/Fonts/Pretendard-Regular.otf"
FONT_SEMIBOLD="/Users/user/Library/Fonts/Pretendard-SemiBold.otf"

mkdir -p "$OUTPUT_DIR" "$TMP_ROOT"

build_screenshot() {
  local source="$1"
  local crop="$2"
  local headline="$3"
  local subtitle="$4"
  local output="$5"
  local window_image="$TMP_ROOT/${output:t:r}-window.png"
  local window_shadow="$TMP_ROOT/${output:t:r}-shadow.png"

  magick "$source" \
    -crop "$crop" +repage \
    -resize '2380x1390>' \
    "$window_image"

  magick "$window_image" \
    \( +clone -background '#050713' -shadow 65x24+0+26 \) \
    +swap -background none -layers merge +repage \
    "$window_shadow"

  magick -size 2880x1800 'gradient:#14192B-#3F2C78' \
    \( "$ROOT/store-assets/icon/AppIcon-1024.png" -resize 92x92 \) -geometry +178+108 -composite \
    -font "$FONT_SEMIBOLD" -fill '#FFFFFF' -pointsize 76 \
    -annotate +298+158 "$headline" \
    -font "$FONT_REGULAR" -fill '#C9CEE5' -pointsize 34 \
    -annotate +302+216 "$subtitle" \
    \( "$window_shadow" \) -gravity south -geometry +0+18 -composite \
    -strip "PNG32:$output"
}

build_screenshot \
  "$SOURCE_DIR/history-overview-ko.png" \
  '2630x1680+86+30' \
  'SVN 작업을 한눈에' \
  '서버·로컬·미커밋 변경을 하나의 타임라인으로 확인하세요.' \
  "$OUTPUT_DIR/01-timeline-overview.png"

build_screenshot \
  "$SOURCE_DIR/changes-ko.png" \
  '2640x1640+62+28' \
  '변경 파일만 골라 커밋' \
  '수정·미추적 파일을 확인하고 필요한 항목만 선택하세요.' \
  "$OUTPUT_DIR/02-selective-commit.png"

build_screenshot \
  "$SOURCE_DIR/history-local-base-ko.png" \
  '2640x1660+82+42' \
  '서버와 내 로컬 위치를 비교' \
  '작성자·시간·변경 경로와 업데이트 필요 여부를 바로 확인하세요.' \
  "$OUTPUT_DIR/03-commit-history.png"

echo "$OUTPUT_DIR"
