#!/bin/zsh

SVN_RUNTIME_DEPLOYMENT_TARGET="14.0"
SVN_RUNTIME_ARCHITECTURE="arm64"

function runtime_source_version() {
  case "$1" in
    subversion) print "1.14.5" ;;
    sqlite) print "3.51.0" ;;
    apr) print "1.7.6" ;;
    apr-util) print "1.6.3" ;;
    serf) print "1.3.10" ;;
    openssl) print "3.6.3" ;;
    expat) print "2.7.1" ;;
    lz4) print "1.10.0" ;;
    utf8proc) print "2.11.3" ;;
    scons) print "4.10.1" ;;
    *) print -u2 "Unknown SVN runtime source: $1"; return 1 ;;
  esac
}

function runtime_source_archive_name() {
  case "$1" in
    subversion) print "subversion-1.14.5.tar.bz2" ;;
    sqlite) print "sqlite-amalgamation-3510000.zip" ;;
    apr) print "apr-1.7.6.tar.bz2" ;;
    apr-util) print "apr-util-1.6.3.tar.bz2" ;;
    serf) print "serf-1.3.10.tar.bz2" ;;
    openssl) print "openssl-3.6.3.tar.gz" ;;
    expat) print "expat-2.7.1.tar.xz" ;;
    lz4) print "lz4-1.10.0.tar.gz" ;;
    utf8proc) print "utf8proc-2.11.3.tar.gz" ;;
    scons) print "SCons-4.10.1.tar.gz" ;;
    *) print -u2 "Unknown SVN runtime source: $1"; return 1 ;;
  esac
}

function runtime_source_url() {
  case "$1" in
    subversion) print "https://archive.apache.org/dist/subversion/subversion-1.14.5.tar.bz2" ;;
    sqlite) print "https://www.sqlite.org/2025/sqlite-amalgamation-3510000.zip" ;;
    apr) print "https://archive.apache.org/dist/apr/apr-1.7.6.tar.bz2" ;;
    apr-util) print "https://archive.apache.org/dist/apr/apr-util-1.6.3.tar.bz2" ;;
    serf) print "https://archive.apache.org/dist/serf/serf-1.3.10.tar.bz2" ;;
    openssl) print "https://github.com/openssl/openssl/releases/download/openssl-3.6.3/openssl-3.6.3.tar.gz" ;;
    expat) print "https://github.com/libexpat/libexpat/releases/download/R_2_7_1/expat-2.7.1.tar.xz" ;;
    lz4) print "https://github.com/lz4/lz4/archive/refs/tags/v1.10.0.tar.gz" ;;
    utf8proc) print "https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v2.11.3.tar.gz" ;;
    scons) print "https://github.com/SCons/scons/archive/refs/tags/4.10.1.tar.gz" ;;
    *) print -u2 "Unknown SVN runtime source: $1"; return 1 ;;
  esac
}

function runtime_source_sha256() {
  case "$1" in
    subversion) print "e78a29e7766b8b7b354497d08f71a55641abc53675ce1875584781aae35644a1" ;;
    sqlite) print "1caf7116f2910600d04473ad69d37ec538fa62fa36adccd37b5e0e43647c98be" ;;
    apr) print "49030d92d2575da735791b496dc322f3ce5cff9494779ba8cc28c7f46c5deb32" ;;
    apr-util) print "a41076e3710746326c3945042994ad9a4fcac0ce0277dd8fea076fec3c9772b5" ;;
    serf) print "be81ef08baa2516ecda76a77adf7def7bc3227eeb578b9a33b45f7b41dc064e6" ;;
    openssl) print "243a86649cf6f23eeb6a2ff2456e09e5d77dd9018a54d3d96b0c6bdd6ba6c7f1" ;;
    expat) print "354552544b8f99012e5062f7d570ec77f14b412a3ff5c7d8d0dae62c0d217c30" ;;
    lz4) print "537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b" ;;
    utf8proc) print "abfed50b6d4da51345713661370290f4f4747263ee73dc90356299dfc7990c78" ;;
    scons) print "086a9cd78847a43c17138c11e7e93234a96985d0d346563521fa8db28f5bee96" ;;
    *) print -u2 "Unknown SVN runtime source: $1"; return 1 ;;
  esac
}

function runtime_manifest_contents() {
  local source_name
  print "deployment_target=$SVN_RUNTIME_DEPLOYMENT_TARGET"
  print "architecture=$SVN_RUNTIME_ARCHITECTURE"
  for source_name in expat openssl apr apr-util lz4 utf8proc scons serf sqlite subversion; do
    print "$source_name=$(runtime_source_version "$source_name") sha256=$(runtime_source_sha256 "$source_name")"
  done
}

function normalized_runtime_version() {
  local -a components
  components=("${(@s:.:)1}")
  printf '%05d%05d%05d' "${components[1]:-0}" "${components[2]:-0}" "${components[3]:-0}"
}

function version_is_at_most() {
  local actual="$(normalized_runtime_version "$1")"
  local maximum="$(normalized_runtime_version "$2")"
  [[ "$actual" == "$maximum" || "$actual" < "$maximum" ]]
}

function is_forbidden_runtime_dependency() {
  case "$1" in
    /opt/homebrew/*|/usr/local/*|/tmp/svn-mac-runtime-*|/private/tmp/svn-mac-runtime-*|*/.build/svn-runtime/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
