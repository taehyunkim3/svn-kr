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
  '2580x1570+150+110' \
  'SVN 작업을 한눈에' \
  '서버·로컬·미커밋 변경을 하나의 타임라인으로 확인하세요.' \
  "$OUTPUT_DIR/01-timeline-overview.png"

build_screenshot \
  "$SOURCE_DIR/changes-ko.png" \
  '2620x1590+150+50' \
  '변경 파일만 골라 커밋' \
  '수정·미추적 파일을 확인하고 필요한 항목만 선택하세요.' \
  "$OUTPUT_DIR/02-selective-commit.png"

build_screenshot \
  "$SOURCE_DIR/files-ko.png" \
  '2560x1558+135+93' \
  '프로젝트 파일을 빠르게 탐색' \
  '폴더 구조와 파일 상태를 한 화면에서 확인하고 검색하세요.' \
  "$OUTPUT_DIR/03-working-copy-files.png"

echo "$OUTPUT_DIR"
