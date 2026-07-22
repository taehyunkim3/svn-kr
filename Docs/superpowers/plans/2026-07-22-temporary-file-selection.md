# 임시 파일 표시와 전체 선택 제외 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 흔한 미추적 임시 파일을 변경 목록에서 `임시파일`로 표시하고 전체 선택에서는 제외하되 수동 선택과 전체 해제는 유지한다.

**Architecture:** `SVNStatusEntry`의 SVN 상태, 노드 종류, 마지막 경로 구성 요소만 읽는 내부 계산 속성으로 임시 파일을 분류한다. `ProjectStore`는 기존 수동 선택 가능 집합과 임시 파일을 제외한 전체 선택 집합을 따로 제공하고, 화면은 같은 분류 속성을 상태 배지에 사용한다.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, Swift Package Manager

## Global Constraints

- 임시 파일 패턴은 `~$*`, `.DS_Store`, `._*`, `*.swp`, `*.swo`, `*~`, `#*#`, `.#*`만 사용한다.
- `*.tmp`와 `*.temp`는 임시 파일로 자동 분류하지 않는다.
- `unversioned`이면서 `nodeKind == .file`인 항목에만 임시 파일 판정을 적용한다.
- 기존 `selectableStatusPaths`는 수동 선택과 커밋 검증 의미를 유지한다.
- 전체 선택은 임시 파일을 제외한 집합으로 현재 선택을 교체한다.
- 전체 해제는 임시 파일을 포함해 모든 선택을 해제한다.
- 레이아웃 크기는 변경하지 않는다.

---

### Task 1: 임시 파일 분류와 전체 선택 경로 분리

**Files:**
- Create: `Sources/SVNMac/TemporaryFileClassification.swift`
- Modify: `Sources/SVNMac/ProjectStore.swift:188-202`
- Modify: `Sources/SVNMac/CommitControlsView.swift:17-22`
- Test: `Tests/SVNMacTests/ProjectStoreTests.swift`

**Interfaces:**
- Consumes: `SVNStatusEntry.path`, `SVNStatusEntry.item`, `SVNStatusEntry.nodeKind`, `SVNStatusEntry.isSelectableForCommit`
- Produces: `SVNStatusEntry.isTemporaryFile: Bool`, `ProjectStore.selectAllStatusPaths: Set<String>`

- [ ] **Step 1: 임시 파일 분류와 선택 집합의 실패 테스트 작성**

`Tests/SVNMacTests/ProjectStoreTests.swift`의 `makeStore` 선언 앞에 다음 테스트를 추가한다.

```swift
@Test func recognizesOnlyConservativeUnversionedTemporaryFiles() {
    let temporaryPaths = [
        "문서/~$보고서.xlsx",
        ".DS_Store",
        "자료/._원본.pdf",
        "코드/.main.swift.swp",
        "코드/.main.swift.swo",
        "메모.txt~",
        "#메모.txt#",
        ".#메모.txt",
    ]

    for path in temporaryPaths {
        let entry = SVNStatusEntry(path: path, item: .unversioned, nodeKind: .file)
        #expect(entry.isTemporaryFile, "임시 파일로 분류되지 않음: \(path)")
    }

    let ordinaryPaths = ["보고서.xlsx", "cache.tmp", "cache.temp", "DS_Store"]
    for path in ordinaryPaths {
        let entry = SVNStatusEntry(path: path, item: .unversioned, nodeKind: .file)
        #expect(!entry.isTemporaryFile, "일반 파일이 임시 파일로 분류됨: \(path)")
    }

    #expect(!SVNStatusEntry(path: "~$관리.xlsx", item: .modified, nodeKind: .file).isTemporaryFile)
    #expect(!SVNStatusEntry(path: "~$폴더", item: .unversioned, nodeKind: .directory).isTemporaryFile)
    #expect(!SVNStatusEntry(path: "~$종류미상", item: .unversioned).isTemporaryFile)
}

@MainActor
@Test func selectAllExcludesTemporaryFilesWithoutBlockingManualSelection() {
    let store = makeStore(projects: [SVNProject(name: "프로젝트", path: "/tmp/project")])
    let modified = SVNStatusEntry(path: "보고서.xlsx", item: .modified, nodeKind: .file)
    let unversioned = SVNStatusEntry(path: "새 문서.xlsx", item: .unversioned, nodeKind: .file)
    let temporary = SVNStatusEntry(path: "~$보고서.xlsx", item: .unversioned, nodeKind: .file)
    store.statuses = [modified, unversioned, temporary]

    #expect(store.selectableStatusPaths == [modified.path, unversioned.path, temporary.path])
    #expect(store.selectAllStatusPaths == [modified.path, unversioned.path])

    store.selectedPaths.insert(temporary.path)
    #expect(store.canCommitSelectedPaths)

    store.selectedPaths = store.selectAllStatusPaths
    #expect(store.selectedPaths == [modified.path, unversioned.path])

    store.selectedPaths.removeAll()
    #expect(store.selectedPaths.isEmpty)
}
```

- [ ] **Step 2: 테스트를 실행해 분류 속성과 전체 선택 집합 부재로 실패하는지 확인**

Run: `swift test --filter recognizesOnlyConservativeUnversionedTemporaryFiles`

Expected: 컴파일 실패. `SVNStatusEntry`에 `isTemporaryFile` 멤버가 없다고 출력한다.

- [ ] **Step 3: 최소 임시 파일 분류 로직 구현**

`Sources/SVNMac/TemporaryFileClassification.swift`를 생성한다.

```swift
import Foundation
import SVNCore

extension SVNStatusEntry {
    var isTemporaryFile: Bool {
        guard item == .unversioned, nodeKind == .file else { return false }

        let name = (path as NSString).lastPathComponent
        return name.hasPrefix("~$")
            || name == ".DS_Store"
            || name.hasPrefix("._")
            || name.hasSuffix(".swp")
            || name.hasSuffix(".swo")
            || name.hasSuffix("~")
            || (name.hasPrefix("#") && name.hasSuffix("#"))
            || name.hasPrefix(".#")
    }
}
```

- [ ] **Step 4: 전체 선택 전용 경로 집합과 버튼 연결 구현**

`ProjectStore.swift`에서 `selectableStatusPaths` 바로 뒤에 다음 계산 속성을 추가한다.

```swift
var selectAllStatusPaths: Set<String> {
    Set(statuses.lazy.filter { $0.isSelectableForCommit && !$0.isTemporaryFile }.map(\.path))
}
```

`CommitControlsView.swift`의 전체 선택 동작만 다음과 같이 바꾼다. 선택 해제 코드는 변경하지 않는다.

```swift
Button(appLanguage.text("전체 선택", "Select All")) {
    store.selectedPaths = store.selectAllStatusPaths
}
```

- [ ] **Step 5: 두 집중 테스트를 실행해 통과 확인**

Run: `swift test --filter recognizesOnlyConservativeUnversionedTemporaryFiles && swift test --filter selectAllExcludesTemporaryFilesWithoutBlockingManualSelection`

Expected: 두 테스트 모두 PASS.

- [ ] **Step 6: 관련 파일만 커밋**

```bash
git add Sources/SVNMac/TemporaryFileClassification.swift Sources/SVNMac/ProjectStore.swift Sources/SVNMac/CommitControlsView.swift Tests/SVNMacTests/ProjectStoreTests.swift
git commit -m "feat: 임시 파일을 전체 선택에서 제외"
```

### Task 2: 임시 파일 상태 배지 표시

**Files:**
- Modify: `Sources/SVNMac/ChangesView.swift:237-262`
- Modify: `Tests/SVNMacTests/ChangesViewPerformanceTests.swift`

**Interfaces:**
- Consumes: Task 1의 `SVNStatusEntry.isTemporaryFile: Bool`
- Produces: 임시 파일 행의 한국어 `임시파일`, 영어 `Temporary` 상태 배지

- [ ] **Step 1: 화면 표시와 전체 선택 연결의 실패 테스트 작성**

`Tests/SVNMacTests/ChangesViewPerformanceTests.swift`에 다음 테스트를 추가한다.

```swift
@Test func temporaryFilesHaveDedicatedBadgeAndSelectAllPolicy() throws {
    let sources = try svnMacSources()
    let changesView = try source(named: "ChangesView.swift", in: sources)
    let commitControls = try source(named: "CommitControlsView.swift", in: sources)

    #expect(changesView.contains("entry.isTemporaryFile"))
    #expect(changesView.contains("임시파일"))
    #expect(changesView.contains("Temporary"))
    #expect(commitControls.contains("store.selectAllStatusPaths"))
    #expect(commitControls.contains("store.selectedPaths.removeAll()"))
}
```

- [ ] **Step 2: 테스트를 실행해 임시 파일 배지 부재로 실패하는지 확인**

Run: `swift test --filter temporaryFilesHaveDedicatedBadgeAndSelectAllPolicy`

Expected: FAIL. `ChangesView.swift`에 `entry.isTemporaryFile`과 `임시파일` 문자열이 없어 expectation이 실패한다.

- [ ] **Step 3: 상태 라벨과 색상에 임시 파일 분기 추가**

`ChangesView.swift`의 `statusLabel` 시작 부분에 임시 파일 조기 반환을 추가한다.

```swift
private func statusLabel(_ entry: SVNStatusEntry) -> String {
    if entry.isTemporaryFile {
        return appLanguage.text("임시파일", "Temporary")
    }
    switch entry.item {
```

`statusColor` 시작 부분에는 임시 파일을 보조 상태로 구분하는 회색 반환을 추가한다.

```swift
private func statusColor(_ entry: SVNStatusEntry) -> Color {
    if entry.isTemporaryFile { return .gray }
    switch entry.item {
```

- [ ] **Step 4: 화면 회귀 테스트와 전체 테스트 실행**

Run: `swift test --filter temporaryFilesHaveDedicatedBadgeAndSelectAllPolicy`

Expected: PASS.

Run: `swift test`

Expected: 157개 테스트, 0 failures.

- [ ] **Step 5: 화면 변경만 별도 커밋**

```bash
git add Sources/SVNMac/ChangesView.swift Tests/SVNMacTests/ChangesViewPerformanceTests.swift
git commit -m "feat: 변경 목록에 임시 파일 상태 표시"
```

### Task 3: 최종 범위와 작업 폴더 검증

**Files:**
- Verify: `Docs/LayoutArchitecture.md`
- Verify: 전체 브랜치 diff와 Git 상태

**Interfaces:**
- Consumes: Task 1과 Task 2의 커밋
- Produces: 구현 범위, 레이아웃 규칙, 전체 테스트 통과 증거

- [ ] **Step 1: 레이아웃 규칙과 변경 범위 확인**

Run: `sed -n '1,240p' Docs/LayoutArchitecture.md`

Expected: 창 크기나 패널 구조 변경이 없고 기존 `WorkspaceSplitView` 구조를 유지했음을 확인한다.

Run: `git diff origin/master...HEAD --check && git diff origin/master...HEAD --stat`

Expected: 설계·계획 문서, 임시 파일 분류, `ProjectStore`, 커밋 컨트롤, 변경 목록, 관련 테스트만 표시되고 whitespace 오류가 없다.

- [ ] **Step 2: 깨끗한 전체 테스트를 다시 실행**

Run: `swift test`

Expected: 157개 테스트, 0 failures.

- [ ] **Step 3: 작업 폴더와 커밋 기록 확인**

Run: `git status --short --branch && git log -4 --oneline`

Expected: `codex/temporary-file-selection` 워크트리가 깨끗하고 설계, 계획, 선택 로직, 배지 커밋이 순서대로 표시된다.
