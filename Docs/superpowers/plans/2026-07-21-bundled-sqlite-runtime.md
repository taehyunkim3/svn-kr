# Bundled SQLite Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bundle the exact SQLite runtime expected by the embedded SVN helper and release version 0.5.6 build 17.

**Architecture:** Keep ordinary macOS system libraries external, but special-case SQLite in the embedding pipeline. Resolve the SVN compile-time SQLite version through verbose version output, verify a pinned amalgamation archive, compile it for macOS 14, rewrite SQLite load paths, and validate the packaged runtime before signing.

**Tech Stack:** zsh, SQLite amalgamation, clang, Mach-O `otool`/`install_name_tool`/`vtool`, codesign, SwiftPM

## Global Constraints

- SQLite runtime version must exactly match SVN's compile-time SQLite version.
- The bundled SQLite dylib deployment target must be macOS 14.0.
- App version must be 0.5.6 and build number 17.
- Preserve unrelated working tree and staged changes.

---

### Task 1: Packaging regression tests

**Files:**
- Create: `Tests/Packaging/EmbedSVNTests.sh`
- Modify: `scripts/embed-svn.sh`

**Interfaces:**
- Consumes: `svn --version --verbose`, an optional `SQLITE_SOURCE_ARCHIVE`.
- Produces: exact-version SQLite dylib at `Contents/Frameworks/libsqlite3.dylib`.

- [ ] Write a shell test that sources testable helpers and asserts SQLite version extraction, pinned archive metadata, and system-SQLite special handling.
- [ ] Run `zsh Tests/Packaging/EmbedSVNTests.sh` and confirm it fails because the helpers do not exist.
- [ ] Extract side-effect-free helpers in `embed-svn.sh`, add the pinned 3.51.0 archive metadata, checksum verification, compilation, link rewriting, and runtime validation.
- [ ] Re-run `zsh Tests/Packaging/EmbedSVNTests.sh` and confirm it passes.

### Task 2: Release version and documentation

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `README.md`

**Interfaces:**
- Produces: version 0.5.6 build 17 and accurate packaging prerequisites.

- [ ] Change `CFBundleShortVersionString` from `0.5.5` to `0.5.6` and `CFBundleVersion` from `16` to `17`.
- [ ] Document the pinned SQLite source/cache behavior and current SVN helper architecture limitation.

### Task 3: Full verification and delivery

**Files:**
- Verify: `dist/SVN Mac.app`
- Verify: `dist/SVN-Mac-0.5.6-arm64.zip`

**Interfaces:**
- Consumes: the package script and release metadata.
- Produces: a signed application bundle and distributable ZIP.

- [ ] Run the packaging shell regression test and `swift test`.
- [ ] Run `./scripts/package-app.sh` with the pinned SQLite source archive.
- [ ] Verify the app version/build, SQLite relative link, SQLite compile/runtime equality, dylib deployment target, deep code signature, and ZIP contents.
- [ ] Review `git diff` and stage only the scoped files.
- [ ] Commit with a Korean packaging-fix message.
