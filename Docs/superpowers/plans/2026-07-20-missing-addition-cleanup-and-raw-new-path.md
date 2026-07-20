# Missing Addition Cleanup and Raw New Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 사라진 추가 예약은 안전하게 자동 정리하고, 실제 존재하는 NFD 새 폴더와 파일은 원문 경로로 추가·커밋한다.

**Architecture:** `SVNWorkingCopySnapshot`은 새 경로의 관리 중인 상위 부분만 SVN 원문으로 맞추고 새 하위 부분은 파일 시스템 원문 바이트를 보존한다. 별도의 누락 추가 예약 후보 목록을 만들고 `SVNClient.workingCopySnapshot`이 실제 경로 부재를 확인한 뒤 원문 targets 파일로 revert하고 상태를 다시 읽는다.

**Tech Stack:** Swift 6.2, Foundation, Swift Testing, SVN 1.14 CLI

## Global Constraints

- 사용자가 만든 기존 변경과 스테이징을 보존한다.
- 실제 파일, 디렉터리, 심볼릭 링크는 자동 삭제하거나 덮어쓰지 않는다.
- NFC/NFD 동등 경로, 충돌, 저장소 관리 상태가 섞인 경로는 자동 정리하지 않는다.
- 모든 SVN 대상 경로는 원문 UTF-8 바이트를 보존한다.
- 자동 정리 실패 시 새 커밋을 방해하지 않도록 최상위 예외 한 줄만 유지한다.

---

### Task 1: 새 경로 원문 보존

**Files:**
- Modify: `Sources/SVNCore/SVNWorkingCopySnapshot.swift`
- Test: `Tests/SVNCoreTests/SVNWorkingCopySnapshotTests.swift`
- Test: `Tests/SVNCoreTests/SVNCredentialsTests.swift`

**Interfaces:**
- Produces: `SVNWorkingCopySnapshot.resolvedPath(for:) -> String?`가 관리 상위 경로와 원문 신규 suffix를 결합한 경로

- [ ] 기존 `resolvesDecomposedNewChildAgainstComposedVersionedAncestor` 기대값을 “NFC 관리 상위 + NFD 신규 suffix”로 바꿔 실패를 확인한다.
- [ ] 실제 커밋 명령 테스트가 `add:`와 `commit:` targets에서 NFD 신규 suffix를 요구하도록 바꾸고 실패를 확인한다.
- [ ] `resolvedPath(for:)`와 `resolveNewPath`에서 신규 suffix의 `precomposedStringWithCanonicalMapping` 변환을 제거한다.
- [ ] 두 테스트를 실행해 원문 신규 경로가 targets 파일까지 보존되는지 확인한다.

### Task 2: 안전한 누락 추가 예약 후보와 목록 접기

**Files:**
- Modify: `Sources/SVNCore/SVNWorkingCopySnapshot.swift`
- Modify: `Sources/SVNCore/Models.swift`
- Test: `Tests/SVNCoreTests/SVNWorkingCopySnapshotTests.swift`

**Interfaces:**
- Produces: `SVNWorkingCopySnapshot.missingScheduledAdditionCleanupTargets: [String]`
- Produces: 누락 추가 트리를 최상위 `SVNStatusEntry(item: .missing, revision: "-1")` 한 건으로 접은 `statuses`

- [ ] 단일 누락 파일과 누락 디렉터리 트리가 최상위 후보 한 건이 되는 실패 테스트를 작성한다.
- [ ] NFC/NFD 동등 unversioned 경로, 충돌, revision이 있는 관리 항목이 섞이면 후보가 되지 않는 실패 테스트를 작성한다.
- [ ] 가장 짧은 누락 추가 루트를 계산하고, 그 아래 모든 상태가 추가 예약 계열일 때만 cleanup target으로 노출한다.
- [ ] 표시 상태에서는 누락 추가 하위 항목을 제거하고 후보 또는 예외의 최상위 한 줄만 남긴다.
- [ ] 관련 스냅샷 테스트를 실행한다.

### Task 3: 상태 조회 중 자동 정리와 실패 보존

**Files:**
- Modify: `Sources/SVNCore/SVNClient.swift`
- Modify: `Sources/SVNMac/ChangesView.swift`
- Test: `Tests/SVNCoreTests/SVNCredentialsTests.swift`
- Test: `Tests/SVNMacTests/ChangesViewPerformanceTests.swift`

**Interfaces:**
- Consumes: `missingScheduledAdditionCleanupTargets`
- Produces: 정리 성공 후 다시 읽은 `SVNWorkingCopySnapshot`; 실패 시 접힌 원래 스냅샷

- [ ] 가짜 SVN에서 첫 status가 누락 추가 트리, revert 뒤 status가 정상인 실패 테스트를 작성한다.
- [ ] 실제 경로 또는 심볼릭 링크가 존재하면 revert를 호출하지 않는 실패 테스트를 작성한다.
- [ ] `workingCopySnapshot`에서 각 후보의 경로가 없음을 확인하고 `revert --depth infinity`를 원문 targets 파일로 실행한 뒤 상태를 다시 읽는다.
- [ ] revert 또는 사후 검증 실패 시 오류를 전파하지 않고 접힌 원래 상태를 반환한다.
- [ ] 남은 회색 배지 문구를 `정리 필요` / `Cleanup Needed`로 변경한다.
- [ ] 관련 코어 및 UI 테스트를 실행한다.

### Task 4: 실제 SVN 및 전체 회귀 검증

**Files:**
- Modify: `Tests/SVNCoreTests/SVNCanonicalAliasIntegrationTests.swift`
- Verify: all files modified above

**Interfaces:**
- Consumes: Tasks 1-3 결과
- Produces: 실제 SVN 작업 복사본과 전체 패키지 검증 결과

- [ ] 실제 SVN fixture에서 사라진 추가 예약을 정리해 저장소와 로컬 파일 내용이 변하지 않는지 확인한다.
- [ ] 실제 NFD 신규 디렉터리를 추가·커밋하고 저장소에 동일 원문 경로와 파일 바이트가 생기는지 확인한다.
- [ ] `swift test` 전체를 실행해 모든 테스트가 통과하는지 확인한다.
- [ ] `git diff --check`, `git status --short`로 기존 변경 보존과 범위를 확인한다.
- [ ] `./scripts/package-app.sh`로 앱을 패키징하고 코드 서명을 확인한 뒤 실행 중인 앱을 재시작한다.
