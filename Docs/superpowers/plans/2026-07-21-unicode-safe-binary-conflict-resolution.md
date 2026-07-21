# Unicode-Safe Binary Conflict Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve real HWP binary conflicts even when the UI path is NFD and the SVN-managed path is NFC, without guessing between ambiguous repository paths.

**Architecture:** Refresh one `SVNWorkingCopySnapshot` when conflict preparation begins, resolve the selected display path to one exact versioned raw path, and keep that command path in `ConflictResolutionSession` through `svn info` and `svn resolve`. Extend the existing backup-first flow with the `.working` choice, canonical-aware artifact filtering, and post-resolve status verification.

**Tech Stack:** Swift 6, SwiftUI, Foundation XMLParser, Swift Testing, SVN 1.14 CLI

## Global Constraints

- Do not normalize every command path blindly; select one exact raw SVN-managed path from the snapshot.
- Do not auto-resolve canonical collisions with more than one managed path.
- Preserve mine, server, and latest working bytes before resolving.
- Never commit automatically after conflict resolution.
- Keep tree-conflict automation out of scope.
- Run `swift test` after the change.

---

### Task 1: Canonical-aware conflict paths and artifact filtering

**Files:**
- Modify: `Sources/SVNCore/SVNXMLParser.swift`
- Test: `Tests/SVNCoreTests/SVNXMLParserTests.swift`
- Test: `Tests/SVNCoreTests/SVNWorkingCopySnapshotTests.swift`

**Interfaces:**
- Consumes: `SVNWorkingCopySnapshot.resolvedPath(for:) -> String?`
- Produces: canonical-aware conflict artifact filtering and verified unique raw-path resolution.

- [ ] **Step 1: Write failing parser and snapshot tests**

Add a parser fixture whose conflicted path is NFC and whose `.mine`/`.r42` artifact paths are canonically equivalent NFD strings. Assert only the conflicted entry remains. Add snapshot assertions that an NFD selection returns the sole NFC managed path and returns `nil` when two raw managed paths share the same canonical key.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter SVNXMLParserTests && swift test --filter SVNWorkingCopySnapshotTests`

Expected: the mixed-normalization artifact test fails because the helper entries remain visible; existing raw-path resolution tests continue passing.

- [ ] **Step 3: Implement canonical-aware artifact matching**

Replace exact-string artifact matching with a helper that splits `.mine` or `.r<digits>` from the entry, compares the base path using `precomposedStringWithCanonicalMapping`, and only hides entries matching a known conflicted canonical path. Keep ordinary files ending in nonnumeric `.r...` visible.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter SVNXMLParserTests && swift test --filter SVNWorkingCopySnapshotTests`

Expected: PASS.

- [ ] **Step 5: Commit the path foundation**

```bash
git add Sources/SVNCore/SVNXMLParser.swift Tests/SVNCoreTests/SVNXMLParserTests.swift Tests/SVNCoreTests/SVNWorkingCopySnapshotTests.swift
git commit -m "fix: 한글 충돌 경로와 보조 파일 판정 보정"
```

### Task 2: Resolve one exact SVN path throughout a conflict session

**Files:**
- Modify: `Sources/SVNMac/ConflictFileService.swift`
- Modify: `Sources/SVNMac/ProjectStore+Conflicts.swift`
- Test: `Tests/SVNMacTests/ProjectStoreTests.swift`

**Interfaces:**
- Produces: `ConflictResolutionSession.requestedPath: String`, `versionedPath: String`, and `wasCanonicallyResolved: Bool`.
- Consumes: `SVNClientServing.workingCopySnapshot(at:credentials:)` and `SVNWorkingCopySnapshot.resolvedPath(for:)`.

- [ ] **Step 1: Write failing store tests**

Create a stub snapshot with an NFC conflicted managed path and call `prepareConflictResolution` with its NFD equivalent. Assert the stub receives the NFC path for `conflictDetails`, the session retains both paths, and resolve later receives the same NFC path. Add an ambiguous snapshot test asserting no `svn info` request is made and an error is shown.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter ProjectStoreTests`

Expected: tests fail because preparation forwards the requested NFD path and the session has no separate command path.

- [ ] **Step 3: Implement session path separation**

In `prepareConflictResolution`, load the latest snapshot, call `resolvedPath(for:)`, reject `nil` with `SVNError.pathNormalizationCollision`, and pass the resolved path to `conflictDetails`. Extend the session initializer so the UI-facing requested path and exact versioned path remain immutable through the operation. In `resolveActiveConflict`, pass `session.versionedPath` rather than `session.details.path`.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter ProjectStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit exact-path conflict preparation**

```bash
git add Sources/SVNMac/ConflictFileService.swift Sources/SVNMac/ProjectStore+Conflicts.swift Tests/SVNMacTests/ProjectStoreTests.swift
git commit -m "fix: 충돌 해결에 실제 SVN 관리 경로 사용"
```

### Task 3: Support mine, server, and manually edited working files

**Files:**
- Modify: `Sources/SVNMac/ConflictResolutionView.swift`
- Modify: `Sources/SVNMac/ProjectStore+Conflicts.swift`
- Modify: `Sources/SVNMac/ConflictFileService.swift`
- Test: `Tests/SVNMacTests/ProjectStoreTests.swift`
- Test: `Tests/SVNMacTests/ConflictFileServiceTests.swift`

**Interfaces:**
- Consumes: `SVNConflictChoice.working` and `ConflictResolutionSession.versionedPath`.
- Produces: a third `현재 작업 파일 사용` action and post-resolve verification.

- [ ] **Step 1: Write failing working-choice and verification tests**

Replace the old test that expects `.working` to do nothing. Assert it preserves the latest working bytes, invokes resolve with `.working`, and closes the session only when the refreshed snapshot no longer reports the versioned path as conflicted. Add a failure fixture that returns the conflict after resolve and assert the session remains with a localized error.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter ProjectStoreTests && swift test --filter ConflictFileServiceTests`

Expected: `.working` does not invoke the client and resolve success is not verified.

- [ ] **Step 3: Implement all three choices and verification**

Allow `.working` through `resolveActiveConflict`. Keep `prepareWorkingFileForResolve` backup-first behavior and skip replacement for `.working`. After the client resolve call, request a new snapshot and require that no status with the same raw-path identity or canonical key remains `.conflicted`; otherwise throw a dedicated conflict verification error and keep the session.

- [ ] **Step 4: Add the third UI action and adjusted confirmation copy**

Add a `현재 작업 파일` card explaining that it keeps the HWP currently stored in the working copy. Add `.working` confirmation title, action, and message. When `wasCanonicallyResolved` is true, show a compact informational label above the version cards. Keep all action buttons disabled while resolving.

- [ ] **Step 5: Run focused tests**

Run: `swift test --filter ProjectStoreTests && swift test --filter ConflictFileServiceTests`

Expected: PASS.

- [ ] **Step 6: Commit binary conflict completion**

```bash
git add Sources/SVNMac/ConflictResolutionView.swift Sources/SVNMac/ProjectStore+Conflicts.swift Sources/SVNMac/ConflictFileService.swift Tests/SVNMacTests/ProjectStoreTests.swift Tests/SVNMacTests/ConflictFileServiceTests.swift
git commit -m "feat: 바이너리 충돌의 현재 작업 파일 해결 지원"
```

### Task 4: Real SVN regression and full verification

**Files:**
- Modify: `Tests/SVNCoreTests/SVNCanonicalAliasIntegrationTests.swift`
- Modify if needed: `Tests/SVNCoreTests/SVNCredentialsTests.swift`

**Interfaces:**
- Verifies the public `SVNClient` behavior against a temporary local SVN repository.

- [ ] **Step 1: Add a failing real-SVN binary conflict regression**

Create a temporary repository and two working copies, commit different binary bytes to the same Korean-named file, update the stale copy to create a conflict, and invoke conflict lookup/resolve using the canonically equivalent selected path. Assert the exact managed path is used and the chosen bytes remain after `.working` resolution.

- [ ] **Step 2: Run the integration test**

Run: `swift test --filter SVNCanonicalAliasIntegrationTests`

Expected before the implementation is complete: FAIL at NFD conflict lookup. Expected after Tasks 1-3: PASS.

- [ ] **Step 3: Run formatting and full regression checks**

Run: `git diff --check`

Expected: no output.

Run: `swift test`

Expected: all tests PASS.

- [ ] **Step 4: Inspect the final diff and commit the integration regression**

```bash
git add Tests/SVNCoreTests/SVNCanonicalAliasIntegrationTests.swift Tests/SVNCoreTests/SVNCredentialsTests.swift
git commit -m "test: 한글 경로 바이너리 충돌 회귀 검증"
```
