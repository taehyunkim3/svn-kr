#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
source "$ROOT/scripts/svn-runtime-manifest.sh"

function extract_static_sqlite_version() {
  print -r -- "$1" | sed -nE \
    's/.*SQLite ([0-9.]+) \(static\).*/\1/p' | head -n 1
}

function dependencies() {
  otool -L "$1" | awk 'NR > 1 {print $1}'
}

function is_allowed_runtime_dependency() {
  if [[ "$1" == /usr/lib/* || "$1" == /System/Library/* ]]; then
    print true
  else
    print false
  fi
}

function validate_runtime_source() {
  local runtime_dir="$1"
  local svn_binary="$runtime_dir/bin/svn"
  local svnmucc_binary="$runtime_dir/bin/svnmucc"
  local binary
  for binary in "$svn_binary" "$svnmucc_binary"; do
    [[ -x "$binary" ]] || {
      print -u2 "Validated SVN runtime is missing: $binary"
      print -u2 "Build it first with: ./scripts/build-svn-runtime.sh"
      return 1
    }
  done
  [[ -f "$runtime_dir/runtime-manifest.txt" ]] || {
    print -u2 "SVN runtime manifest is missing: $runtime_dir/runtime-manifest.txt"
    return 1
  }
  [[ "$(<"$runtime_dir/runtime-manifest.txt")" == "$(runtime_manifest_contents)" ]] || {
    print -u2 "SVN runtime manifest does not match the pinned source manifest: $runtime_dir/runtime-manifest.txt"
    return 1
  }

  local minos dependency
  for binary in "$svn_binary" "$svnmucc_binary"; do
    file "$binary" | grep -q "Mach-O 64-bit executable $SVN_RUNTIME_ARCHITECTURE" || {
      print -u2 "SVN runtime architecture must be $SVN_RUNTIME_ARCHITECTURE: $binary"
      return 1
    }

    minos="$(vtool -show-build "$binary" | awk '/minos/ {print $2; exit}')"
    [[ -n "$minos" ]] && version_is_at_most "$minos" "$SVN_RUNTIME_DEPLOYMENT_TARGET" || {
      print -u2 "SVN runtime deployment target must be macOS $SVN_RUNTIME_DEPLOYMENT_TARGET or lower, got: ${minos:-unknown}"
      return 1
    }

    while IFS= read -r dependency; do
      [[ -z "$dependency" ]] && continue
      [[ "$(is_allowed_runtime_dependency "$dependency")" == true ]] || {
        print -u2 "SVN runtime contains a non-system dependency: $dependency"
        return 1
      }
    done < <(dependencies "$binary")
  done

  local version_output sqlite_version
  version_output="$("$svn_binary" --version --verbose)"
  sqlite_version="$(extract_static_sqlite_version "$version_output")"
  [[ "$sqlite_version" == "$(runtime_source_version sqlite)" ]] || {
    print -u2 "SVN must statically link SQLite $(runtime_source_version sqlite), got: ${sqlite_version:-unknown}"
    return 1
  }

  "$svnmucc_binary" --version >/dev/null
  print "Validated bundled SVN tools $("$svn_binary" --version --quiet), SQLite $sqlite_version, macOS $minos"
}

function main() {
  local app="${1:?Usage: embed-svn.sh /path/to/App.app}"
  local runtime_dir="${SVN_RUNTIME_DIR:-$ROOT/.build/svn-runtime/macos-14-arm64}"
  validate_runtime_source "$runtime_dir"

  local helper_dir="$app/Contents/Helpers"
  local resources_dir="$app/Contents/Resources"
  mkdir -p "$helper_dir" "$resources_dir/Licenses"
  cp "$runtime_dir/bin/svn" "$helper_dir/svn"
  cp "$runtime_dir/bin/svnmucc" "$helper_dir/svnmucc"
  cp "$runtime_dir/runtime-manifest.txt" "$resources_dir/SVNRuntimeManifest.txt"
  cp -R "$runtime_dir/licenses/." "$resources_dir/Licenses/"
  chmod 755 "$helper_dir/svn" "$helper_dir/svnmucc"

  codesign --force --sign - "$helper_dir/svn"
  codesign --force --sign - "$helper_dir/svnmucc"
  print "Embedded validated SVN runtime from: $runtime_dir"
}

if [[ "${SVN_MAC_EMBED_LIBRARY_ONLY:-0}" != 1 ]]; then
  main "$@"
fi
