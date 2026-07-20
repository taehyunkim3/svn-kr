# Canonical File Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 정규화만 다른 파일 대치를 실제 내용 기준으로 수정 또는 정상 상태로 판정하고 안전하게 커밋한다.

**Architecture:** XML 스냅샷은 원문 대치 후보를 보존하고, SVNClient가 BASE와 로컬 파일의 원본 바이트를 비교한다. 커밋 직전에는 대치 바이트를 보존한 채 관리 경로를 복원·재적용해 SVN이 실제 `modified`로 인식한 경우에만 커밋한다.

**Tech Stack:** Swift 6.2, Foundation Process/FileManager/Data, Swift Testing, SVN 1.14 CLI

## Global Constraints

- 기존 `missing revision=-1` 별칭 정리와 실제 삭제 의미를 유지한다.
- 다중 후보, 디렉터리, 심볼릭 링크는 자동 변환하지 않는다.
- 바이너리 stdout을 UTF-8 문자열로 왕복해 비교하지 않는다.
- 사용자가 대치한 파일 바이트를 실패 경로에서도 보존한다.

---

### Task 1: 대치 후보와 원문 경로 명령

**Files:**
- Modify: `Sources/SVNCore/Models.swift`
- Modify: `Sources/SVNCore/SVNWorkingCopySnapshot.swift`
- Modify: `Sources/SVNCore/SVNClient.swift`
- Test: `Tests/SVNCoreTests/SVNWorkingCopySnapshotTests.swift`
- Test: `Tests/SVNCoreTests/SVNCredentialsTests.swift`

**Interfaces:**
- Produces: `SVNCanonicalFileReplacement`, 원문 UTF-8 경로 실행기, 스냅샷 대치 후보 목록

- [x] 실패 테스트에 일대일 `missing + unversioned` 후보와 모호한 다중 후보 제외를 작성한다.
- [x] 해당 테스트가 후보 API 부재로 실패하는지 실행한다.
- [x] 스냅샷 후보 계산과 원본 UTF-8 경로 전달을 최소 구현한다.
- [x] 관련 테스트가 통과하는지 실행한다.

### Task 2: BASE 바이트 판정과 표시 상태

**Files:**
- Modify: `Sources/SVNCore/SVNClient.swift`
- Modify: `Sources/SVNCore/SVNWorkingCopySnapshot.swift`
- Test: `Tests/SVNCoreTests/SVNCredentialsTests.swift`

**Interfaces:**
- Consumes: `SVNCanonicalFileReplacement`, 파일로 저장한 SVN BASE 출력
- Produces: `workingCopySnapshot`의 `modified` 또는 변경 없음 상태

- [x] 다른 바이트는 `modified`, 같은 바이트는 제외, 디렉터리는 기존 `missing`을 유지하는 가짜 SVN 테스트를 작성한다.
- [x] 현재 구현에서 `missing`으로 실패하는지 실행한다.
- [x] 일반 파일 후보만 `svn cat --revision BASE`와 청크 비교해 상태를 해석한다.
- [x] 관련 테스트가 통과하는지 실행한다.

### Task 3: 안전한 선택 커밋 변환

**Files:**
- Modify: `Sources/SVNCore/SVNClient.swift`
- Test: `Tests/SVNCoreTests/SVNCanonicalAliasIntegrationTests.swift`

**Interfaces:**
- Consumes: 수정으로 판정된 대치 후보
- Produces: 커밋 전 실제 관리 경로의 `modified` 상태와 보존된 사용자 바이트

- [x] 실제 SVN fixture에 NFC 관리 파일과 NFD 대치 파일을 만들고 표시 및 커밋 기대 테스트를 작성한다.
- [x] 현재 커밋 흐름에서 실패하는지 실행한다.
- [x] 선택된 대치 후보만 디스크 백업, revert, 재기록, 상태 재검증한다.
- [x] 오류 시 대치 바이트를 복원하고 커밋을 중단한다.
- [x] 통합 테스트가 통과하는지 실행한다.

### Task 4: 전체 회귀 검증

**Files:**
- Verify: all files modified above

**Interfaces:**
- Consumes: Tasks 1-3 결과
- Produces: 전체 패키지 회귀 검증 결과

- [x] `swift test`를 실행해 전체 테스트 성공을 확인한다.
- [x] `git diff --check`와 `git status --short`로 범위와 공백 오류를 확인한다.
