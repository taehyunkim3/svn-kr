#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
source "$ROOT/scripts/svn-runtime-manifest.sh"

SOURCE_NAMES=(expat openssl apr apr-util lz4 utf8proc scons serf sqlite subversion)
CACHE_ROOT="${SVN_RUNTIME_CACHE:-${TMPDIR:-/tmp}/svn-mac-runtime-sources}"
BUILD_ROOT="${SVN_RUNTIME_BUILD_ROOT:-$ROOT/.build/svn-runtime-build/macos-14-arm64}"
OUTPUT_ROOT="${SVN_RUNTIME_OUTPUT:-$ROOT/.build/svn-runtime/macos-14-arm64}"
SOURCE_ROOT="$BUILD_ROOT/sources"
PREFIX="$BUILD_ROOT/prefix"
JOBS="${SVN_RUNTIME_JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || print 4)}"

function require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    print -u2 "Required build tool is missing: $1"
    return 1
  }
}

function verify_source_archive() {
  local source_name="$1"
  local archive="$2"
  local expected actual
  expected="$(runtime_source_sha256 "$source_name")"
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    print -u2 "Checksum mismatch for $source_name"
    print -u2 "Expected: $expected"
    print -u2 "Actual:   $actual"
    return 1
  }
}

function fetch_source() {
  local source_name="$1"
  local archive="$CACHE_ROOT/$(runtime_source_archive_name "$source_name")"
  if [[ ! -f "$archive" ]]; then
    print -u2 "Downloading $source_name $(runtime_source_version "$source_name")..."
    curl -L --fail --silent --show-error "$(runtime_source_url "$source_name")" -o "$archive"
  fi
  verify_source_archive "$source_name" "$archive"
  print -r -- "$archive"
}

function extract_source() {
  local source_name="$1"
  local archive="$2"
  local destination="$SOURCE_ROOT/$source_name"
  mkdir -p "$destination"
  case "$archive" in
    *.zip) unzip -q "$archive" -d "$destination" ;;
    *.tar.gz|*.tar.bz2|*.tar.xz) tar -xf "$archive" -C "$destination" ;;
    *) print -u2 "Unsupported source archive: $archive"; return 1 ;;
  esac
  find "$destination" -mindepth 1 -maxdepth 1 -type d | head -n 1
}

function configure_make_install() {
  local source="$1"
  local build="$2"
  shift 2
  mkdir -p "$build"
  (
    cd "$build"
    "$source/configure" "$@"
    make -j "$JOBS"
    make install
  )
}

function write_serf_pkg_config() {
  mkdir -p "$PREFIX/lib/pkgconfig"
  {
    print 'prefix='"$PREFIX"
    print 'exec_prefix=${prefix}'
    print 'libdir=${exec_prefix}/lib'
    print 'includedir=${prefix}/include/serf-1'
    print
    print 'Name: serf'
    print 'Description: HTTP client library'
    print 'Version: '"$(runtime_source_version serf)"
    print 'Libs: -L${libdir} -lserf-1 -L'"$PREFIX"'/lib -lssl -lcrypto -lz'
    print 'Libs.private: -L'"$PREFIX"'/lib -laprutil-1 -lapr-1'
    print 'Cflags: -I${includedir}'
  } > "$PREFIX/lib/pkgconfig/serf-1.pc"
}

function write_lz4_pkg_config() {
  mkdir -p "$PREFIX/lib/pkgconfig"
  {
    print 'prefix='"$PREFIX"
    print 'libdir=${prefix}/lib'
    print 'includedir=${prefix}/include'
    print
    print 'Name: lz4'
    print 'Description: fast lossless compression algorithm library'
    print 'Version: '"$(runtime_source_version lz4)"
    print 'Libs: -L${libdir} -llz4'
    print 'Cflags: -I${includedir}'
  } > "$PREFIX/lib/pkgconfig/liblz4.pc"
}

function write_utf8proc_pkg_config() {
  mkdir -p "$PREFIX/lib/pkgconfig"
  {
    print 'prefix='"$PREFIX"
    print 'libdir=${prefix}/lib'
    print 'includedir=${prefix}/include'
    print
    print 'Name: libutf8proc'
    print 'Description: UTF-8 processing library'
    print 'Version: '"$(runtime_source_version utf8proc)"
    print 'Libs: -L${libdir} -lutf8proc'
    print 'Cflags: -I${includedir}'
  } > "$PREFIX/lib/pkgconfig/libutf8proc.pc"
}

function dependencies() {
  otool -L "$1" | awk 'NR > 1 {print $1}'
}

function deployment_target() {
  vtool -show-build "$1" | awk '/minos/ {print $2; exit}'
}

function validate_runtime() {
  local binary minos dependency
  for binary in "$OUTPUT_ROOT/bin/svn" "$OUTPUT_ROOT/bin/svnmucc"; do
    [[ -x "$binary" ]] || {
      print -u2 "SVN runtime was not produced: $binary"
      return 1
    }

    file "$binary" | grep -q 'arm64' || {
      print -u2 "SVN runtime is not arm64: $binary"
      return 1
    }

    minos="$(deployment_target "$binary")"
    [[ -n "$minos" ]] && version_is_at_most "$minos" "$SVN_RUNTIME_DEPLOYMENT_TARGET" || {
      print -u2 "SVN runtime deployment target must be macOS $SVN_RUNTIME_DEPLOYMENT_TARGET or lower, got: ${minos:-unknown}"
      return 1
    }

    while IFS= read -r dependency; do
      [[ -z "$dependency" ]] && continue
      if is_forbidden_runtime_dependency "$dependency"; then
        print -u2 "SVN runtime links a build-machine dependency: $dependency"
        return 1
      fi
    done < <(dependencies "$binary")
  done

  "$OUTPUT_ROOT/bin/svn" --version --verbose
  "$OUTPUT_ROOT/bin/svnmucc" --version
  print "Validated SVN runtime tools (arm64, macOS $minos)"
}

function copy_license_group() {
  local source_name="$1"
  local source_dir="$2"
  local destination="$OUTPUT_ROOT/licenses/$source_name"
  mkdir -p "$destination"
  find "$source_dir" -maxdepth 2 -type f \( \
    -iname 'LICENSE*' -o -iname 'NOTICE*' -o -iname 'COPYING*' -o -iname 'COPYRIGHT*' \
  \) -exec cp {} "$destination/" \;
}

function main() {
  for tool in curl shasum tar unzip make perl python3 xcrun pkg-config otool vtool file; do
    require_tool "$tool"
  done

  mkdir -p "$CACHE_ROOT"
  [[ "$BUILD_ROOT" == "$ROOT/.build/svn-runtime-build/"* || "$BUILD_ROOT" == /tmp/svn-mac-runtime-* || "$BUILD_ROOT" == /private/tmp/svn-mac-runtime-* ]] || {
    print -u2 "Refusing unsafe SVN runtime build root: $BUILD_ROOT"
    return 1
  }
  [[ "$OUTPUT_ROOT" == "$ROOT/.build/svn-runtime/"* || "$OUTPUT_ROOT" == /tmp/svn-mac-runtime-* || "$OUTPUT_ROOT" == /private/tmp/svn-mac-runtime-* ]] || {
    print -u2 "Refusing unsafe SVN runtime output root: $OUTPUT_ROOT"
    return 1
  }
  rm -rf "$BUILD_ROOT" "$OUTPUT_ROOT"
  mkdir -p "$SOURCE_ROOT" "$PREFIX" "$OUTPUT_ROOT/bin" "$OUTPUT_ROOT/licenses"

  typeset -A sources
  local source_name archive
  for source_name in "${SOURCE_NAMES[@]}"; do
    archive="$(fetch_source "$source_name")"
    sources[$source_name]="$(extract_source "$source_name" "$archive")"
  done

  export MACOSX_DEPLOYMENT_TARGET="$SVN_RUNTIME_DEPLOYMENT_TARGET"
  export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
  export CC="$(xcrun -f clang)"
  export AR="$(xcrun -f ar)"
  export RANLIB="$(xcrun -f ranlib)"
  export CFLAGS="-O2 -arch $SVN_RUNTIME_ARCHITECTURE -mmacosx-version-min=$SVN_RUNTIME_DEPLOYMENT_TARGET -isysroot $SDKROOT"
  export CPPFLAGS="-I$PREFIX/include"
  export LDFLAGS="-arch $SVN_RUNTIME_ARCHITECTURE -mmacosx-version-min=$SVN_RUNTIME_DEPLOYMENT_TARGET -isysroot $SDKROOT -L$PREFIX/lib"
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

  print "Building Expat..."
  configure_make_install "${sources[expat]}" "$BUILD_ROOT/build-expat" \
    --prefix="$PREFIX" --disable-shared --enable-static \
    --without-xmlwf --without-examples --without-tests --without-docbook

  print "Building OpenSSL..."
  (
    cd "${sources[openssl]}"
    perl Configure darwin64-arm64-cc no-shared no-tests no-module no-legacy \
      --prefix="$PREFIX" --openssldir="$PREFIX/etc/ssl" \
      "-mmacosx-version-min=$SVN_RUNTIME_DEPLOYMENT_TARGET"
    make -j "$JOBS"
    make install_sw
  )

  print "Building APR..."
  configure_make_install "${sources[apr]}" "$BUILD_ROOT/build-apr" \
    --prefix="$PREFIX" --disable-shared --enable-static

  print "Building APR-util..."
  configure_make_install "${sources[apr-util]}" "$BUILD_ROOT/build-apr-util" \
    --prefix="$PREFIX" --disable-shared --enable-static --disable-util-dso \
    --without-pgsql --without-mysql --without-sqlite3 --without-odbc --without-oracle \
    --with-apr="$PREFIX" --with-expat="$PREFIX" --with-openssl="$PREFIX"

  print "Building LZ4..."
  make -C "${sources[lz4]}/lib" -j "$JOBS" liblz4.a CC="$CC" CFLAGS="$CFLAGS"
  cp "${sources[lz4]}/lib/liblz4.a" "$PREFIX/lib/"
  cp "${sources[lz4]}"/lib/lz4*.h "$PREFIX/include/"
  write_lz4_pkg_config

  print "Building utf8proc..."
  make -C "${sources[utf8proc]}" -j "$JOBS" libutf8proc.a CC="$CC" CFLAGS="$CFLAGS"
  cp "${sources[utf8proc]}/libutf8proc.a" "$PREFIX/lib/"
  cp "${sources[utf8proc]}/utf8proc.h" "$PREFIX/include/"
  write_utf8proc_pkg_config

  print "Building Serf..."
  (
    cd "${sources[serf]}"
    /usr/bin/python3 "${sources[scons]}/scripts/scons.py" -j "$JOBS" \
      PREFIX="$PREFIX" LIBDIR="$PREFIX/lib" \
      APR="$PREFIX/bin/apr-1-config" APU="$PREFIX/bin/apu-1-config" \
      OPENSSL="$PREFIX" APR_STATIC=yes \
      CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS" LINKFLAGS="$LDFLAGS" \
      libserf-1.a
  )
  mkdir -p "$PREFIX/include/serf-1"
  cp "${sources[serf]}/libserf-1.a" "$PREFIX/lib/"
  cp "${sources[serf]}/serf.h" "${sources[serf]}/serf_bucket_types.h" \
    "${sources[serf]}/serf_bucket_util.h" "$PREFIX/include/serf-1/"
  write_serf_pkg_config

  print "Building Subversion..."
  mkdir -p "$BUILD_ROOT/build-subversion"
  mkdir -p "$BUILD_ROOT/build-subversion/sqlite-amalgamation"
  cp "${sources[sqlite]}/sqlite3.c" "${sources[sqlite]}/sqlite3.h" \
    "${sources[sqlite]}/sqlite3ext.h" \
    "$BUILD_ROOT/build-subversion/sqlite-amalgamation/"
  (
    cd "$BUILD_ROOT/build-subversion"
    "${sources[subversion]}/configure" \
      --prefix="$PREFIX" --disable-shared --enable-static --enable-all-static --disable-nls \
      --without-berkeley-db --without-sasl \
      --with-apr="$PREFIX" --with-apr-util="$PREFIX" --with-serf="$PREFIX" \
      --with-expat="$PREFIX/include:$PREFIX/lib:expat" \
      --with-lz4="$PREFIX" --with-utf8proc="$PREFIX"
    make mkdir-init
    make -j "$JOBS" svn svnmucc
  )
  cp "$BUILD_ROOT/build-subversion/subversion/svn/svn" "$OUTPUT_ROOT/bin/svn"
  cp "$BUILD_ROOT/build-subversion/tools/client-side/svnmucc/svnmucc" \
    "$OUTPUT_ROOT/bin/svnmucc"
  chmod 755 "$OUTPUT_ROOT/bin/svn" "$OUTPUT_ROOT/bin/svnmucc"

  for source_name in "${SOURCE_NAMES[@]}"; do
    copy_license_group "$source_name" "${sources[$source_name]}"
  done

  runtime_manifest_contents > "$OUTPUT_ROOT/runtime-manifest.txt"

  validate_runtime
  print "$OUTPUT_ROOT"
}

main "$@"
