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
    -resize '2380x1390' \
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
  '1281x769+108+77' \
  'SVN 작업을 한눈에' \
  '서버·로컬·미커밋 변경을 하나의 타임라인으로 확인하세요.' \
  "$OUTPUT_DIR/01-timeline-overview.png"

build_screenshot \
  "$SOURCE_DIR/changes-ko.png" \
  '1279x768+14+66' \
  '변경 파일만 골라 커밋' \
  '수정·미추적 파일을 확인하고 필요한 항목만 선택하세요.' \
  "$OUTPUT_DIR/02-selective-commit.png"

build_screenshot \
  "$SOURCE_DIR/files-ko.png" \
  '1280x767+83+70' \
  '프로젝트 파일을 빠르게 탐색' \
  '폴더 구조와 파일 상태를 한 화면에서 확인하고 검색하세요.' \
  "$OUTPUT_DIR/03-working-copy-files.png"

build_screenshot \
  "$SOURCE_DIR/repository-locks-ko.png" \
  '1279x770+80+57' \
  '팀 작업 충돌을 미리 방지' \
  '저장소 잠금 상태를 확인해 동시 편집 충돌을 줄이세요.' \
  "$OUTPUT_DIR/04-repository-locks.png"

build_screenshot \
  "$SOURCE_DIR/credentials-ko.png" \
  '1282x770+116+86' \
  '프로젝트별 인증을 안전하게' \
  '비밀번호는 macOS Keychain에 저장하고 저장소별로 관리하세요.' \
  "$OUTPUT_DIR/05-project-credentials.png"

build_screenshot \
  "$SOURCE_DIR/add-repository-ko.png" \
  '1281x771+115+86' \
  '새 저장소를 바로 시작' \
  'URL과 로컬 폴더를 지정해 새로운 작업 폴더를 체크아웃하세요.' \
  "$OUTPUT_DIR/06-add-repository.png"

echo "$OUTPUT_DIR"
