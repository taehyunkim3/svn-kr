#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
export SVN_MAC_EMBED_LIBRARY_ONLY=1
source "$ROOT/scripts/embed-svn.sh"

function assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "$actual" != "$expected" ]]; then
    print -u2 "$description: expected '$expected', got '$actual'"
    exit 1
  fi
}

svn_version_output=$'System information:\n* linked dependencies:\n  - SQLite 3.50.4 (compiled with 3.51.0)\n'
assert_equal "3.51.0" "$(extract_compiled_sqlite_version "$svn_version_output")" \
  "extracts the SQLite compile-time version"

assert_equal \
  "https://www.sqlite.org/2025/sqlite-amalgamation-3510000.zip" \
  "$(sqlite_archive_url 3.51.0)" \
  "uses the pinned SQLite source URL"

assert_equal \
  "1caf7116f2910600d04473ad69d37ec538fa62fa36adccd37b5e0e43647c98be" \
  "$(sqlite_archive_sha256 3.51.0)" \
  "uses the verified SQLite archive checksum"

assert_equal "true" "$(is_sqlite_dependency /usr/lib/libsqlite3.dylib)" \
  "recognizes the system SQLite load path"
assert_equal "false" "$(is_sqlite_dependency /usr/lib/libz.1.dylib)" \
  "does not special-case unrelated system libraries"

checksum_fixture="$(mktemp "${TMPDIR:-/tmp}/svn-mac-checksum.XXXXXX")"
trap 'rm -f "$checksum_fixture"' EXIT
verify_archive_sha256 \
  "$checksum_fixture" \
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
if verify_archive_sha256 "$checksum_fixture" "invalid" >/dev/null 2>&1; then
  print -u2 "a mismatched SQLite source checksum must be rejected"
  exit 1
fi

if sqlite_archive_url 3.50.4 >/dev/null 2>&1; then
  print -u2 "unsupported SQLite versions must be rejected"
  exit 1
fi

print "EmbedSVNTests passed"
