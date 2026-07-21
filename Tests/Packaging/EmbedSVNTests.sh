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

svn_version_output=$'System information:\n* linked dependencies:\n  - SQLite 3.51.0 (static)\n'
assert_equal "3.51.0" "$(extract_static_sqlite_version "$svn_version_output")" \
  "extracts the statically linked SQLite version"

assert_equal "true" "$(is_allowed_runtime_dependency /usr/lib/libSystem.B.dylib)" \
  "allows stable system libraries"
assert_equal "true" "$(is_allowed_runtime_dependency /System/Library/Frameworks/Security.framework/Versions/A/Security)" \
  "allows system frameworks"
assert_equal "false" "$(is_allowed_runtime_dependency /opt/homebrew/lib/libssl.3.dylib)" \
  "rejects Homebrew dependencies"
assert_equal "false" "$(is_allowed_runtime_dependency @rpath/libsqlite3.dylib)" \
  "rejects unresolved bundled dependencies"

if version_is_at_most "26.0" "14.0"; then
  print -u2 "a macOS 26 runtime must not pass the macOS 14 deployment check"
  exit 1
fi

print "EmbedSVNTests passed"
