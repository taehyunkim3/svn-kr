# macOS 14 SVN Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and package a checksum-pinned SVN 1.14.5 arm64 runtime whose complete non-system dependency closure targets macOS 14.

**Architecture:** A source manifest defines immutable inputs. A dedicated builder produces a staged static runtime, a validator rejects incompatible Mach-O files and leaked build paths, and the existing app packager consumes only that validated runtime.

**Tech Stack:** zsh, autoconf/configure, make, clang, SCons, Mach-O tooling, SwiftPM

## Global Constraints

- Runtime architecture is arm64.
- Deployment target is macOS 14.0.
- SVN version is 1.14.5.
- SQLite version is 3.51.0.
- Release version is 0.5.7 build 18.
- Homebrew and staging paths must not remain in packaged Mach-O load commands.

---

### Task 1: Runtime manifest and validation contract

**Files:**
- Create: `scripts/svn-runtime-manifest.sh`
- Create: `Tests/Packaging/SVNRuntimeTests.sh`

**Interfaces:**
- Produces `runtime_source_url`, `runtime_source_sha256`, `macho_minimum_os`, and `validate_runtime_binary`.

- [ ] Write failing tests for pinned versions, unsupported sources, minimum-OS rejection, and forbidden load paths.
- [ ] Run `zsh Tests/Packaging/SVNRuntimeTests.sh` and confirm missing manifest helpers cause failure.
- [ ] Add the source manifest and side-effect-free validation helpers.
- [ ] Re-run the focused test and confirm it passes.

### Task 2: Reproducible source runtime builder

**Files:**
- Create: `scripts/build-svn-runtime.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes the pinned source manifest and optional `SVN_RUNTIME_CACHE`.
- Produces `.build/svn-runtime/macos-14-arm64/bin/svn`, `licenses`, and `manifest.txt`.

- [ ] Implement fetch, checksum, extraction, isolated build environment, and tool preflight.
- [ ] Build static Expat, OpenSSL, APR, APR-util, LZ4, utf8proc, Serf, SQLite-backed SVN.
- [ ] Reject a runtime whose Mach-O target or load paths violate the manifest contract.
- [ ] Run the resulting SVN through repository creation, checkout, status, add, and commit integration operations.

### Task 3: Package only the validated runtime

**Files:**
- Modify: `scripts/embed-svn.sh`
- Modify: `scripts/package-app.sh`
- Modify: `Tests/Packaging/EmbedSVNTests.sh`

**Interfaces:**
- Consumes `SVN_RUNTIME_DIR` and copies its validated helper and licenses.
- Produces an app with no build-host package-manager dependency.

- [ ] Write a failing packaging test requiring `SVN_RUNTIME_DIR` for release packaging.
- [ ] Replace the Homebrew-plus-runtime-SQLite path with validated runtime copying.
- [ ] Add package-wide minimum-OS and forbidden-load-path checks before signing.
- [ ] Run both packaging test suites.

### Task 4: Release, package, and commit

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `CHANGELOG.md`
- Verify: `dist/SVN Mac.app`
- Verify: `dist/SVN-Mac-0.5.7-arm64.zip`

**Interfaces:**
- Produces the 0.5.7 build 18 app and ZIP.

- [ ] Bump the version and record the runtime change.
- [ ] Run `swift test` and the packaging regression suites.
- [ ] Build the runtime and package the app using `SVN_RUNTIME_DIR`.
- [ ] Verify runtime operations, Mach-O minimum OS/load paths, deep signing, and ZIP integrity.
- [ ] Stage only scoped files and commit with a Korean message.
