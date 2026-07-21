#!/bin/zsh
set -euo pipefail

function extract_compiled_sqlite_version() {
  print -r -- "$1" | sed -nE \
    's/.*SQLite [0-9.]+ \(compiled with ([0-9.]+)\).*/\1/p' | head -n 1
}

function extract_runtime_sqlite_version() {
  print -r -- "$1" | sed -nE \
    's/.*SQLite ([0-9.]+) \(compiled with [0-9.]+\).*/\1/p' | head -n 1
}

function sqlite_archive_url() {
  case "$1" in
    3.51.0) print "https://www.sqlite.org/2025/sqlite-amalgamation-3510000.zip" ;;
    *) print -u2 "Unsupported SVN SQLite compile version: $1"; return 1 ;;
  esac
}

function sqlite_archive_sha256() {
  case "$1" in
    3.51.0) print "1caf7116f2910600d04473ad69d37ec538fa62fa36adccd37b5e0e43647c98be" ;;
    *) print -u2 "Unsupported SVN SQLite compile version: $1"; return 1 ;;
  esac
}

function is_sqlite_dependency() {
  if [[ "$1" == /usr/lib/libsqlite3.dylib ]]; then
    print true
  else
    print false
  fi
}

function verify_archive_sha256() {
  local archive="$1"
  local expected_sha256="$2"
  local actual_sha256
  actual_sha256="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
  if [[ "$actual_sha256" == "$expected_sha256" ]]; then
    return 0
  fi

  print -u2 "SQLite source checksum mismatch: $archive"
  print -u2 "Expected: $expected_sha256"
  print -u2 "Actual:   $actual_sha256"
  return 1
}

function dependencies() {
  otool -L "$1" | awk 'NR > 1 { print $1 }'
}

function is_system_dependency() {
  [[ "$1" == /usr/lib/* || "$1" == /System/Library/* ]]
}

function copy_license_files() {
  local binary_path="${1:A}"
  local cellar_prefix="${binary_path%%/Cellar/*}/Cellar"
  [[ "$binary_path" == */Cellar/* ]] || return 0

  local relative="${binary_path#*/Cellar/}"
  local formula="${relative%%/*}"
  local after_formula="${relative#*/}"
  local version="${after_formula%%/*}"
  local formula_root="$cellar_prefix/$formula/$version"
  local destination="$LICENSES/$formula"
  [[ -d "$destination" ]] && return 0

  mkdir -p "$destination"
  find "$formula_root" -maxdepth 1 -type f \( \
    -name 'LICENSE*' -o -name 'NOTICE*' -o -name 'COPYING*' -o -name 'COPYRIGHT*' \
  \) -exec cp {} "$destination/" \;
}

function prepare_sqlite_runtime() {
  local version="$1"
  local source_url
  local expected_sha256
  source_url="$(sqlite_archive_url "$version")"
  expected_sha256="$(sqlite_archive_sha256 "$version")"

  local cache_root="${SQLITE_SOURCE_CACHE:-${TMPDIR:-/tmp}/svn-mac-dependencies}"
  local archive="${SQLITE_SOURCE_ARCHIVE:-$cache_root/${source_url:t}}"
  if [[ ! -f "$archive" ]]; then
    mkdir -p "$cache_root"
    print "Downloading SQLite $version source..."
    curl -L --fail --silent --show-error "$source_url" -o "$archive"
  fi

  verify_archive_sha256 "$archive" "$expected_sha256"

  SQLITE_BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/svn-mac-sqlite.XXXXXX")"
  unzip -q "$archive" -d "$SQLITE_BUILD_ROOT"
  local source="$SQLITE_BUILD_ROOT/sqlite-amalgamation-3510000/sqlite3.c"
  [[ -f "$source" ]] || {
    print -u2 "SQLite amalgamation source missing from: $archive"
    return 1
  }

  MACOSX_DEPLOYMENT_TARGET=14.0 xcrun clang \
    -arch "$(uname -m)" \
    -mmacosx-version-min=14.0 \
    -dynamiclib \
    -O2 \
    -fPIC \
    -DSQLITE_THREADSAFE=1 \
    -DSQLITE_ENABLE_COLUMN_METADATA=1 \
    -Wl,-install_name,@rpath/libsqlite3.dylib \
    -Wl,-compatibility_version,9.0.0 \
    -Wl,-current_version,"$version" \
    "$source" \
    -o "$SQLITE_TARGET"
  chmod u+w "$SQLITE_TARGET"
}

function validate_sqlite_runtime() {
  local verbose_output
  local runtime_version
  local compiled_version
  verbose_output="$("$SVN_TARGET" --version --verbose)"
  runtime_version="$(extract_runtime_sqlite_version "$verbose_output")"
  compiled_version="$(extract_compiled_sqlite_version "$verbose_output")"

  if [[ -z "$runtime_version" || "$runtime_version" != "$compiled_version" ]]; then
    print -u2 "Bundled SVN SQLite version mismatch: compiled=$compiled_version runtime=$runtime_version"
    return 1
  fi

  local sqlite_minos
  sqlite_minos="$(vtool -show-build "$SQLITE_TARGET" | awk '/minos/ { print $2; exit }')"
  if [[ "$sqlite_minos" != "14.0" ]]; then
    print -u2 "Bundled SQLite deployment target must be macOS 14.0, got: $sqlite_minos"
    return 1
  fi

  local binary
  for binary in "$SVN_TARGET" "$FRAMEWORKS"/*.dylib(N); do
    if dependencies "$binary" | grep -q '^/usr/lib/libsqlite3\.dylib$'; then
      print -u2 "A bundled binary still links the system SQLite runtime: $binary"
      return 1
    fi
  done

  print "Bundled SQLite: $runtime_version (macOS $sqlite_minos deployment target)"
}

function main() {
  APP="${1:?Usage: embed-svn.sh /path/to/App.app}"
  SVN_SOURCE="${SVN_EXECUTABLE:-$(command -v svn || true)}"

  if [[ -z "$SVN_SOURCE" || ! -x "$SVN_SOURCE" ]]; then
    print -u2 "Packaging requires SVN. Install it on the build Mac with: brew install subversion"
    return 1
  fi

  RESOURCES="$APP/Contents/Resources"
  FRAMEWORKS="$APP/Contents/Frameworks"
  HELPERS="$APP/Contents/Helpers"
  LICENSES="$RESOURCES/Licenses"
  SVN_TARGET="$HELPERS/svn"
  SQLITE_TARGET="$FRAMEWORKS/libsqlite3.dylib"

  mkdir -p "$HELPERS" "$FRAMEWORKS" "$LICENSES"
  cp -L "$SVN_SOURCE" "$SVN_TARGET"
  chmod u+w "$SVN_TARGET"
  copy_license_files "$SVN_SOURCE"

  local source_version_output
  local sqlite_compile_version
  source_version_output="$("$SVN_SOURCE" --version --verbose)"
  sqlite_compile_version="$(extract_compiled_sqlite_version "$source_version_output")"
  [[ -n "$sqlite_compile_version" ]] || {
    print -u2 "Could not determine the SQLite version used to compile SVN: $SVN_SOURCE"
    return 1
  }
  prepare_sqlite_runtime "$sqlite_compile_version"

  typeset -a queue
  queue=("$SVN_TARGET" "$SQLITE_TARGET")
  integer index=1

  while (( index <= ${#queue} )); do
    local binary="${queue[$index]}"
    while IFS= read -r dependency; do
      [[ -z "$dependency" ]] && continue
      [[ "$(is_sqlite_dependency "$dependency")" == true ]] && continue
      is_system_dependency "$dependency" && continue
      [[ "$dependency" == @* ]] && continue

      local resolved="${dependency:A}"
      local name="${resolved:t}"
      local target="$FRAMEWORKS/$name"
      if [[ ! -f "$target" ]]; then
        cp -L "$resolved" "$target"
        chmod u+w "$target"
        copy_license_files "$resolved"
        queue+=("$target")
      fi
    done < <(dependencies "$binary")
    (( index += 1 ))
  done

  for binary in "${queue[@]}"; do
    local loader_prefix=""
    if [[ "$binary" == "$SVN_TARGET" ]]; then
      loader_prefix='@loader_path/../Frameworks'
    else
      loader_prefix='@loader_path'
      install_name_tool -id "@rpath/${binary:t}" "$binary"
    fi

    while IFS= read -r dependency; do
      [[ -z "$dependency" ]] && continue
      if [[ "$(is_sqlite_dependency "$dependency")" == true ]]; then
        install_name_tool -change "$dependency" "$loader_prefix/libsqlite3.dylib" "$binary"
        continue
      fi
      is_system_dependency "$dependency" && continue
      [[ "$dependency" == @* ]] && continue
      install_name_tool -change "$dependency" "$loader_prefix/${dependency:A:t}" "$binary"
    done < <(dependencies "$binary")
  done

  # install_name_tool은 Homebrew 병 서명을 무효화합니다. 런타임 검사를 위해
  # 임시 ad-hoc 서명하고, package-app.sh가 배포 설정에 맞게 다시 서명합니다.
  for binary in "$FRAMEWORKS"/*.dylib(N); do
    codesign --force --sign - "$binary"
  done
  codesign --force --sign - "$SVN_TARGET"

  validate_sqlite_runtime
  print "Embedded SVN from: $SVN_SOURCE"
  print "Bundled libraries: ${#queue} binaries total"
}

if [[ "${SVN_MAC_EMBED_LIBRARY_ONLY:-0}" != 1 ]]; then
  SQLITE_BUILD_ROOT=""
  trap '[[ -z "$SQLITE_BUILD_ROOT" || ! -d "$SQLITE_BUILD_ROOT" ]] || rm -rf "$SQLITE_BUILD_ROOT"' EXIT
  main "$@"
fi
