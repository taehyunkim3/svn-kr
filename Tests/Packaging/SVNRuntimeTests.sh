#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
source "$ROOT/scripts/svn-runtime-manifest.sh"

function assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "$actual" != "$expected" ]]; then
    print -u2 "$description: expected '$expected', got '$actual'"
    exit 1
  fi
}

assert_equal "1.14.5" "$(runtime_source_version subversion)" "pins SVN"
assert_equal "3.51.0" "$(runtime_source_version sqlite)" "pins SQLite"
assert_equal "14.0" "$SVN_RUNTIME_DEPLOYMENT_TARGET" "pins the deployment target"
assert_equal "arm64" "$SVN_RUNTIME_ARCHITECTURE" "pins the runtime architecture"
[[ "$(runtime_manifest_contents)" == *"sqlite=3.51.0 sha256=$(runtime_source_sha256 sqlite)"* ]] || {
  print -u2 "runtime manifest must contain the pinned SQLite source"
  exit 1
}

for source_name in subversion sqlite apr apr-util serf openssl expat lz4 utf8proc scons; do
  url="$(runtime_source_url "$source_name")"
  checksum="$(runtime_source_sha256 "$source_name")"
  [[ "$url" == https://* ]] || {
    print -u2 "$source_name must use HTTPS: $url"
    exit 1
  }
  [[ ${#checksum} == 64 && "$checksum" != *[^0-9a-f]* ]] || {
    print -u2 "$source_name must have a 64-character SHA-256: $checksum"
    exit 1
  }
done

version_is_at_most "14.0" "14.0"
version_is_at_most "13.5" "14.0"
if version_is_at_most "26.0" "14.0"; then
  print -u2 "macOS 26 must not satisfy a macOS 14 maximum"
  exit 1
fi

is_forbidden_runtime_dependency "/opt/homebrew/lib/libssl.3.dylib"
is_forbidden_runtime_dependency "/usr/local/lib/libexample.dylib"
is_forbidden_runtime_dependency "/tmp/svn-mac-runtime-build/libexample.dylib"
if is_forbidden_runtime_dependency "/usr/lib/libSystem.B.dylib"; then
  print -u2 "stable system libraries must remain allowed"
  exit 1
fi

if runtime_source_url unsupported >/dev/null 2>&1; then
  print -u2 "unknown runtime sources must be rejected"
  exit 1
fi

print "SVNRuntimeTests passed"
