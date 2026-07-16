#!/bin/zsh
set -euo pipefail

APP="${1:?Usage: embed-svn.sh /path/to/App.app}"
SVN_SOURCE="${SVN_EXECUTABLE:-$(command -v svn || true)}"

if [[ -z "$SVN_SOURCE" || ! -x "$SVN_SOURCE" ]]; then
  print -u2 "Packaging requires SVN. Install it on the build Mac with: brew install subversion"
  exit 1
fi

RESOURCES="$APP/Contents/Resources"
FRAMEWORKS="$APP/Contents/Frameworks"
HELPERS="$APP/Contents/Helpers"
LICENSES="$RESOURCES/Licenses"
SVN_TARGET="$HELPERS/svn"

mkdir -p "$HELPERS" "$FRAMEWORKS" "$LICENSES"
cp -L "$SVN_SOURCE" "$SVN_TARGET"
chmod u+w "$SVN_TARGET"

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

copy_license_files "$SVN_SOURCE"

typeset -a queue
queue=("$SVN_TARGET")
integer index=1

while (( index <= ${#queue} )); do
  binary="${queue[$index]}"
  while IFS= read -r dependency; do
    [[ -z "$dependency" ]] && continue
    is_system_dependency "$dependency" && continue
    [[ "$dependency" == @* ]] && continue

    resolved="${dependency:A}"
    name="${resolved:t}"
    target="$FRAMEWORKS/$name"
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
  if [[ "$binary" == "$SVN_TARGET" ]]; then
    loader_prefix='@loader_path/../Frameworks'
  else
    loader_prefix='@loader_path'
    install_name_tool -id "@rpath/${binary:t}" "$binary"
  fi

  while IFS= read -r dependency; do
    [[ -z "$dependency" ]] && continue
    is_system_dependency "$dependency" && continue
    [[ "$dependency" == @* ]] && continue
    install_name_tool -change "$dependency" "$loader_prefix/${dependency:A:t}" "$binary"
  done < <(dependencies "$binary")
done

print "Embedded SVN from: $SVN_SOURCE"
print "Bundled libraries: ${#queue} binaries total"
