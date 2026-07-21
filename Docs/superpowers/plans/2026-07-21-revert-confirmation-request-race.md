# Revert Confirmation Request Race Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 확인창 종료가 Store의 표시 상태를 먼저 비워도 사용자가 승인한 파일의 `svn revert`가 정확히 실행되게 한다.

**Architecture:** SwiftUI 경고창의 `presenting` 클로저가 제공하는 값 타입 `RevertRequest`를 버튼에서 캡처해 Store 메서드에 명시적으로 전달한다. Store는 가변 `revertRequest` 표시 상태를 실행 입력으로 다시 읽지 않으며, 기존 성공·실패·새로고침 흐름은 유지한다.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, Swift Package Manager

## Global Constraints

- 레이아웃 파일과 화면 크기는 변경하지 않는다.
- 확인창 취소와 외부 닫기 시 `revertRequest`를 비우는 현재 동작을 유지한다.
- 되돌리기 외 다른 파일 작업 흐름은 리팩터링하지 않는다.
- 회귀 테스트를 먼저 실패시킨 후 최소 구현으로 통과시킨다.

---

### Task 1: 캡처된 되돌리기 요청을 Store까지 전달

**Files:**
- Modify: `Tests/SVNMacTests/ProjectStoreTests.swift`
- Modify: `Sources/SVNMac/ProjectStore+FileActions.swift:7-18`
- Modify: `Sources/SVNMac/RevertConfirmation.swift:12-14`

**Interfaces:**
- Consumes: `RevertRequest(entry: SVNStatusEntry)`와 현재 선택된 `SVNProject`
- Produces: `ProjectStore.confirmRevert(_ request: RevertRequest) async`

- [x] **Step 1: Store 회귀 테스트와 SVN 호출 기록 추가**

`Tests/SVNMacTests/ProjectStoreTests.swift`에 다음 테스트를 추가한다. `StubSVNClient`에는 `RevertCall` 배열과 조회 메서드를 추가하고 `revert` 구현에서 호출을 기록한다.

```swift
@MainActor
@Test func confirmRevertUsesCapturedRequestAfterPresentationStateClears() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/revert-race")
    let entry = SVNStatusEntry(path: "00 사업관리/보고서.hwp", item: .modified)
    let client = StubSVNClient(
        snapshotsByPath: [
            project.path: SVNWorkingCopySnapshot(
                statuses: [],
                revision: SVNWorkingCopyRevision(minimum: "10", maximum: "10"),
                collisions: [],
                versionedPathsByCanonicalKey: [:]
            ),
        ]
    )
    let store = makeStore(projects: [project], client: client)
    store.statuses = [entry]
    store.selectedPaths = [entry.path]
    let request = RevertRequest(entry: entry)
    store.revertRequest = nil

    await store.confirmRevert(request)

    #expect(await client.requestedReverts() == [
        RevertCall(workingCopyPath: project.path, relativePath: entry.path),
    ])
    #expect(store.statuses.isEmpty)
    #expect(store.selectedPaths.isEmpty)
}
```

```swift
private struct RevertCall: Equatable, Sendable {
    let workingCopyPath: String
    let relativePath: String
}
```

- [x] **Step 2: 대상 테스트가 올바른 이유로 실패하는지 확인**

Run:

```bash
swift test --filter confirmRevertUsesCapturedRequestAfterPresentationStateClears
```

Expected: `confirmRevert`에 인자를 받는 오버로드가 없어 컴파일이 실패한다.

- [x] **Step 3: Store가 명시적인 요청을 실행하도록 최소 수정**

`Sources/SVNMac/ProjectStore+FileActions.swift`의 메서드를 다음 형태로 변경한다.

```swift
func confirmRevert(_ request: RevertRequest) async {
    guard let project = selectedProject else { return }
    revertRequest = nil
    let operationID = beginOperation(.revert(project.id))
    defer { endOperation(operationID) }
    do {
        _ = try await client.revert(at: project.path, relativePath: request.entry.path, credentials: nil)
        selectedPaths.remove(request.entry.path)
        notice = AppLanguage.current.text("로컬 변경을 되돌렸습니다: \(request.entry.path)", "Reverted local changes: \(request.entry.path)")
        await refresh()
    } catch { errorMessage = localizedError(error) }
}
```

- [x] **Step 4: 확인창이 표시 중인 요청을 직접 전달하도록 수정**

`Sources/SVNMac/RevertConfirmation.swift`의 확인 버튼이 `presenting` 값의 이름을 사용하게 한다.

```swift
} actions: { request in
    Button(appLanguage.text("되돌리기", "Revert"), role: .destructive) {
        Task { await store.confirmRevert(request) }
    }
    Button(appLanguage.text("취소", "Cancel"), role: .cancel) { store.revertRequest = nil }
}
```

실제 SwiftUI `alert` 후행 클로저 문법에 맞춰 기존 호출 구조 안에서 `{ _ in`을 `{ request in`으로 바꾸고 인자를 전달한다.

- [x] **Step 5: 대상 테스트와 전체 테스트 실행**

Run:

```bash
swift test --filter confirmRevertUsesCapturedRequestAfterPresentationStateClears
swift test
```

Expected: 대상 테스트와 전체 테스트가 모두 실패 없이 종료한다.

- [x] **Step 6: 변경 범위 확인 후 구현 커밋**

Run:

```bash
git diff --check
git status --short
git add Sources/SVNMac/ProjectStore+FileActions.swift Sources/SVNMac/RevertConfirmation.swift Tests/SVNMacTests/ProjectStoreTests.swift Docs/superpowers/plans/2026-07-21-revert-confirmation-request-race.md
git commit -m "fix: 되돌리기 확인 요청 경합 수정"
```

Expected: 설계에 명시된 파일만 스테이징되고 구현 커밋이 생성된다.
