# Simple Conflict Version Choice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 미추적 폴더가 하위 파일을 함께 추가함을 명시하고, 파일 내용 충돌에서는 안전하게 백업한 내 파일과 서버 파일을 열어 본 뒤 전체 버전 하나를 선택하게 한다.

**Architecture:** `SVNClient`가 변경 경로의 실제 노드 종류를 스냅샷에 주입해 UI가 미추적 디렉터리만 구분한다. `ConflictFileService`는 두 SVN 충돌 버전을 Application Support에 전부 복사한 `ConflictResolutionSession`을 만들고, `ProjectStore`와 `ConflictResolutionView`는 그 세션을 통해 열기·백업 폴더 표시·`mine-full`/`theirs-full` 선택만 제공한다.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSWorkspace`, Foundation `FileManager`, Darwin `lstat`, Swift Testing, SVN 1.14 CLI

## Global Constraints

- 주요 창과 시트 크기 숫자는 `Sources/SVNMac/AppLayout.swift`만 소유한다.
- 충돌 시트는 기존 `appSheetFrame(minimumSize: AppLayout.conflictResolutionSheetMinimumSize)`를 유지한다.
- 비교용 파일 수정은 실제 작업 파일이나 SVN 충돌 보조 파일에 반영하지 않는다.
- 내 파일과 서버 파일 백업이 모두 성공하기 전에는 어떤 `svn resolve`도 실행하지 않는다.
- 파일 내용 충돌만 지원하며 트리·속성 충돌은 자동 해결하지 않는다.
- 선택 성공 후 자동 커밋하지 않는다.
- 미추적 폴더는 한 행과 폴더 전체 선택을 유지하며 하위 파일 개별 선택을 추가하지 않는다.
- 사용자가 만든 기존 변경과 스테이징을 보존하고 관련 파일만 커밋한다.

---

### Task 1: 미추적 폴더 노드 종류와 재귀 포함 안내

**Files:**
- Modify: `Sources/SVNCore/Models.swift`
- Modify: `Sources/SVNCore/SVNWorkingCopySnapshot.swift`
- Modify: `Sources/SVNCore/SVNClient.swift`
- Modify: `Sources/SVNMac/ChangesView.swift`
- Test: `Tests/SVNCoreTests/SVNCredentialsTests.swift`
- Test: `Tests/SVNMacTests/ChangesViewPerformanceTests.swift`

**Interfaces:**
- Produces: `SVNStatusEntry.nodeKind: SVNNodeKind?`
- Produces: `SVNWorkingCopySnapshot.annotatingNodeKinds(_ kindsByRawPath: [SVNPathIdentity: SVNNodeKind]) -> SVNWorkingCopySnapshot`
- Consumes: 기존 `SVNPathIdentity`의 원문 UTF-8 경로 구분

- [ ] **Step 1: 노드 종류 주입과 UI 문구의 실패 테스트를 작성한다.**

`SVNCredentialsTests.swift`의 가짜 SVN fixture 작업 폴더에 `새 폴더/문서.pdf`와 `새 파일.pdf`를 만들고 status XML에는 두 최상위 경로만 `unversioned`로 반환한다. 다음 기대를 추가한다.

```swift
let snapshot = try await client.workingCopySnapshot(at: directory.path)
let byPath = Dictionary(uniqueKeysWithValues: snapshot.statuses.map { ($0.path, $0) })
#expect(byPath["새 폴더"]?.nodeKind == .directory)
#expect(byPath["새 파일.pdf"]?.nodeKind == .file)
```

`ChangesViewPerformanceTests.swift`에는 소스 계약을 추가한다.

```swift
@Test func unversionedDirectoryExplainsRecursiveCommit() throws {
    let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())
    #expect(changesView.contains("하위 파일이 함께 추가됩니다."))
    #expect(changesView.contains("entry.item == .unversioned && entry.nodeKind == .directory"))
}
```

- [ ] **Step 2: 실패를 확인한다.**

Run:

```bash
swift test --filter unversionedDirectoryExplainsRecursiveCommit
swift test --filter workingCopySnapshotAnnotatesUnversionedNodeKinds
```

Expected: `SVNStatusEntry.nodeKind`가 없고 안내 문구가 없어 컴파일 또는 기대가 실패한다.

- [ ] **Step 3: 상태 모델과 스냅샷 복사 인터페이스를 구현한다.**

`Models.swift`에서 기존 호출을 깨지 않도록 기본값을 둔다.

```swift
public struct SVNStatusEntry: Identifiable, Hashable, Sendable {
    public let path: String
    public let item: SVNStatusKind
    public let revision: String?
    public let nodeKind: SVNNodeKind?

    public var id: String { path }

    public init(
        path: String,
        item: SVNStatusKind,
        revision: String? = nil,
        nodeKind: SVNNodeKind? = nil
    ) {
        self.path = path
        self.item = item
        self.revision = revision
        self.nodeKind = nodeKind
    }
}
```

`SVNWorkingCopySnapshot.swift`에는 원문 경로 ID로 노드 종류를 적용하고 나머지 필드를 그대로 보존하는 메서드를 추가한다.

```swift
func annotatingNodeKinds(
    _ kindsByRawPath: [SVNPathIdentity: SVNNodeKind]
) -> SVNWorkingCopySnapshot {
    let annotated = statuses.map { entry in
        SVNStatusEntry(
            path: entry.path,
            item: entry.item,
            revision: entry.revision,
            nodeKind: kindsByRawPath[SVNPathIdentity(rawPath: entry.path)]
        )
    }
    return SVNWorkingCopySnapshot(
        statuses: annotated,
        revision: revision,
        collisions: collisions,
        versionedPathsByCanonicalKey: versionedPathsByCanonicalKey,
        canonicalAliasRepairTargets: canonicalAliasRepairTargets,
        canonicalFileReplacements: canonicalFileReplacements,
        missingScheduledAdditionCleanupTargets: missingScheduledAdditionCleanupTargets,
        scheduledAdditionPaths: scheduledAdditionPaths
    )
}
```

- [ ] **Step 4: 실제 파일 시스템 노드 종류를 안전하게 판정한다.**

`SVNClient.workingCopySnapshot`의 마지막 결과에만 annotation을 적용한다. `Darwin.lstat`으로 링크를 따라가지 않고 일반 파일과 디렉터리만 분류한다.

```swift
private static func nodeKind(at url: URL) -> SVNNodeKind? {
    url.withUnsafeFileSystemRepresentation { path in
        guard let path else { return nil }
        var information = stat()
        guard Darwin.lstat(path, &information) == 0 else { return nil }
        switch information.st_mode & S_IFMT {
        case S_IFREG: return .file
        case S_IFDIR: return .directory
        default: return nil
        }
    }
}

private static func annotateLocalNodeKinds(
    in snapshot: SVNWorkingCopySnapshot,
    at workingCopyPath: String
) -> SVNWorkingCopySnapshot {
    let root = URL(fileURLWithPath: workingCopyPath, isDirectory: true)
    let kinds = Dictionary(uniqueKeysWithValues: snapshot.statuses.compactMap { entry in
        guard entry.item == .unversioned,
              let kind = nodeKind(at: root.appendingPathComponent(entry.path)) else { return nil }
        return (SVNPathIdentity(rawPath: entry.path), kind)
    })
    return snapshot.annotatingNodeKinds(kinds)
}
```

- [ ] **Step 5: 미추적 폴더 행에만 안내를 표시한다.**

`ChangesView.changedFileRow`의 경로 텍스트를 `VStack(alignment: .leading, spacing: 2)`로 감싸고 다음 조건부 문구를 추가한다. 새 크기 숫자나 중첩 split view는 추가하지 않는다.

```swift
VStack(alignment: .leading, spacing: 2) {
    Text(entry.path.precomposedStringWithCanonicalMapping).lineLimit(1)
    if entry.item == .unversioned && entry.nodeKind == .directory {
        Text(appLanguage.text(
            "하위 파일이 함께 추가됩니다.",
            "Files inside this folder will be added together."
        ))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 6: 관련 테스트를 실행하고 커밋한다.**

Run:

```bash
swift test --filter workingCopySnapshotAnnotatesUnversionedNodeKinds
swift test --filter unversionedDirectoryExplainsRecursiveCommit
git diff --check
```

Expected: 두 테스트 통과, diff whitespace 오류 없음.

```bash
git add Sources/SVNCore/Models.swift Sources/SVNCore/SVNWorkingCopySnapshot.swift Sources/SVNCore/SVNClient.swift Sources/SVNMac/ChangesView.swift Tests/SVNCoreTests/SVNCredentialsTests.swift Tests/SVNMacTests/ChangesViewPerformanceTests.swift
git commit -m "feat: 미추적 폴더 포함 범위 안내"
```

---

### Task 2: 두 충돌 버전의 원자적 비교 백업

**Files:**
- Modify: `Sources/SVNMac/ConflictFileService.swift`
- Create: `Tests/SVNMacTests/ConflictFileServiceTests.swift`

**Interfaces:**
- Produces: `ConflictVersionBackup`
- Produces: `ConflictResolutionSession`
- Produces: `ConflictFileService.prepareSession(_:projectID:workingCopyPath:) throws -> ConflictResolutionSession`
- Consumes: `SVNConflictDetails.type`, `myFile`, `serverFile`, `serverRevision`

- [ ] **Step 1: 비교 백업 성공·실패 테스트를 작성한다.**

새 테스트 파일에서 임시 작업 폴더, 내 버전, 서버 버전과 전용 백업 루트를 만든다.

```swift
@Test func preparesBothConflictVersionsBeforeReturningSession() throws {
    let fixture = try ConflictFixture()
    let service = ConflictFileService(backupRootURL: fixture.backupRoot)
    let session = try service.prepareSession(
        fixture.details,
        projectID: fixture.projectID,
        workingCopyPath: fixture.workingCopy.path
    )

    #expect(try Data(contentsOf: session.mine.url) == fixture.mineBytes)
    #expect(try Data(contentsOf: session.server.url) == fixture.serverBytes)
    #expect(session.directoryURL == session.mine.url.deletingLastPathComponent())
    #expect(session.directoryURL == session.server.url.deletingLastPathComponent())
}
```

한쪽 소스가 없을 때 `prepareSession`이 throw하고 완성된 세션 디렉터리를 남기지 않는 테스트도 작성한다.

- [ ] **Step 2: 실패를 확인한다.**

Run:

```bash
swift test --filter ConflictFileServiceTests
```

Expected: 새 모델과 `prepareSession`이 없어 컴파일 실패.

- [ ] **Step 3: 비교 세션 모델과 명시적 오류를 구현한다.**

`ConflictFileService.swift`에 다음 모델을 추가한다.

```swift
struct ConflictVersionBackup: Hashable {
    let url: URL
    let byteCount: Int64
    let modificationDate: Date?
    let revision: String?
}

struct ConflictResolutionSession: Identifiable, Hashable {
    let id: UUID
    let details: SVNConflictDetails
    let directoryURL: URL
    let mine: ConflictVersionBackup
    let server: ConflictVersionBackup
}

enum ConflictFileError: LocalizedError {
    case unsupportedType(String)
    case missingMine
    case missingServer

    var errorDescription: String? {
        switch self {
        case let .unsupportedType(type): "지원하지 않는 충돌 유형입니다: \(type)"
        case .missingMine: "내 파일 버전을 찾을 수 없습니다."
        case .missingServer: "서버 파일 버전을 찾을 수 없습니다."
        }
    }
}
```

- [ ] **Step 4: 두 파일이 모두 성공해야 세션을 반환하도록 구현한다.**

`ConflictFileService` 초기화에 테스트용 루트를 주입하고, 상대 경로는 working copy 루트에 연결한다. 새 UUID 디렉터리를 만들고 `defer` 정리 플래그로 부분 복사를 제거한다.

```swift
init(fileManager: FileManager = .default, backupRootURL: URL? = nil) {
    self.fileManager = fileManager
    self.backupRootURL = backupRootURL
}

func prepareSession(
    _ details: SVNConflictDetails,
    projectID: UUID,
    workingCopyPath: String
) throws -> ConflictResolutionSession {
    guard details.type == "text" else { throw ConflictFileError.unsupportedType(details.type) }
    guard let myFile = details.myFile else { throw ConflictFileError.missingMine }
    guard let serverFile = details.serverFile else { throw ConflictFileError.missingServer }

    let supportRoot = try backupRootURL ?? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    ).appendingPathComponent("SVN Mac/Conflict Backups", isDirectory: true)
    let directory = supportRoot
        .appendingPathComponent(projectID.uuidString, isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    var completed = false
    defer { if !completed { try? fileManager.removeItem(at: directory) } }

    func sourceURL(_ path: String) -> URL {
        if (path as NSString).isAbsolutePath { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: workingCopyPath, isDirectory: true).appendingPathComponent(path)
    }
    let mineSource = sourceURL(myFile)
    let serverSource = sourceURL(serverFile)
    guard fileManager.fileExists(atPath: mineSource.path) else { throw ConflictFileError.missingMine }
    guard fileManager.fileExists(atPath: serverSource.path) else { throw ConflictFileError.missingServer }

    let original = URL(fileURLWithPath: details.path)
    let base = original.deletingPathExtension().lastPathComponent
    let ext = original.pathExtension
    func fileName(_ suffix: String) -> String {
        ext.isEmpty ? "\(base)_\(suffix)" : "\(base)_\(suffix).\(ext)"
    }
    let mineURL = directory.appendingPathComponent(fileName("내파일"))
    let revisionSuffix = details.serverRevision.map { "서버파일_r\($0)" } ?? "서버파일"
    let serverURL = directory.appendingPathComponent(fileName(revisionSuffix))
    try fileManager.copyItem(at: mineSource, to: mineURL)
    try fileManager.copyItem(at: serverSource, to: serverURL)

    func backup(_ url: URL, revision: String?) throws -> ConflictVersionBackup {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return ConflictVersionBackup(
            url: url,
            byteCount: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate,
            revision: revision
        )
    }
    let session = ConflictResolutionSession(
        id: UUID(),
        details: details,
        directoryURL: directory,
        mine: try backup(mineURL, revision: nil),
        server: try backup(serverURL, revision: details.serverRevision)
    )
    completed = true
    return session
}
```

기존 `backup`과 `preserveComparableVersions`는 Task 3에서 호출을 제거한 뒤 삭제할 수 있게 이 Task에서는 유지한다.

- [ ] **Step 5: 서비스 테스트를 실행하고 커밋한다.**

Run:

```bash
swift test --filter ConflictFileServiceTests
git diff --check
```

Expected: 양쪽 바이트·메타데이터 테스트 통과, 부분 백업 디렉터리 없음.

```bash
git add Sources/SVNMac/ConflictFileService.swift Tests/SVNMacTests/ConflictFileServiceTests.swift
git commit -m "feat: 충돌 비교 버전 안전 백업"
```

---

### Task 3: ProjectStore 충돌 세션과 전체 버전 선택

**Files:**
- Modify: `Sources/SVNMac/ConflictFileService.swift`
- Modify: `Sources/SVNMac/ProjectStore.swift`
- Modify: `Sources/SVNMac/ProjectStore+Conflicts.swift`
- Modify: `Sources/SVNMac/ChangesView.swift`
- Modify: `Tests/SVNMacTests/ProjectStoreTests.swift`

**Interfaces:**
- Consumes: `ConflictFileService.prepareSession`
- Produces: `ProjectStore.activeConflictSession: ConflictResolutionSession?`
- Produces: `openConflictVersion(_ choice: SVNConflictChoice)`
- Produces: `openConflictBackupFolder()`
- Produces: `resolveActiveConflict(using choice: SVNConflictChoice) async`

- [ ] **Step 1: 준비·열기·선택 동작의 실패 테스트를 작성한다.**

`StubSVNClient`에 충돌 상세, 기록된 resolve choice와 선택적 resolve error를 추가한다. `makeStore`가 임시 루트의 `ConflictFileService`를 주입받게 한다.

```swift
@MainActor
@Test func preparesBackupsOpensOnlyCopiesAndResolvesSelectedWholeVersion() async throws {
    let fixture = try ConflictFixture()
    let opener = StubWorkspaceOpener()
    let client = StubSVNClient(conflictDetailsValue: fixture.details)
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot),
        workspaceOpener: opener
    )

    await store.prepareConflictResolution(for: fixture.details.path)
    let session = try #require(store.activeConflictSession)
    store.openConflictVersion(.mineFull)
    store.openConflictVersion(.theirsFull)
    store.openConflictBackupFolder()

    #expect(opener.openedURLs == [session.mine.url, session.server.url, session.directoryURL])
    await store.resolveActiveConflict(using: .theirsFull)
    #expect(await client.lastConflictChoice()?.rawValue == SVNConflictChoice.theirsFull.rawValue)
    #expect(store.activeConflictSession == nil)
}
```

지원하지 않는 `type="tree"`, 백업 실패, resolve 실패가 각각 세션 미생성 또는 세션 유지가 되는 테스트를 추가한다.

- [ ] **Step 2: 실패를 확인한다.**

Run:

```bash
swift test --filter preparesBackupsOpensOnlyCopiesAndResolvesSelectedWholeVersion
swift test --filter unsupportedConflictDoesNotCreateResolutionSession
swift test --filter failedResolveKeepsConflictSession
```

Expected: `activeConflictSession`과 새 open 메서드가 없어 실패.

- [ ] **Step 3: Store 상태를 세션 단위로 교체한다.**

`ProjectStore.swift`에서 `activeConflict`를 다음으로 바꾸고 프로젝트 전환 초기화에도 nil을 설정한다.

```swift
@Published var activeConflictSession: ConflictResolutionSession?
```

`ChangesView`의 sheet binding도 세션으로 변경한다.

```swift
.sheet(item: $store.activeConflictSession) { _ in
    ConflictResolutionView().environmentObject(store)
}
```

- [ ] **Step 4: 준비·열기·해결 흐름을 구현한다.**

`ProjectStore+Conflicts.swift`를 다음 책임만 갖게 정리한다.

```swift
func prepareConflictResolution(for relativePath: String) async {
    guard let project = selectedProject else { return }
    let operationID = beginOperation(.resolveConflict(project.id))
    defer { endOperation(operationID) }
    do {
        guard let details = try await client.conflictDetails(
            at: project.path,
            relativePath: relativePath,
            credentials: nil
        ) else { throw ConflictFileError.unsupportedType("unknown") }
        activeConflictSession = try conflictFileService.prepareSession(
            details,
            projectID: project.id,
            workingCopyPath: project.path
        )
    } catch { errorMessage = localizedError(error) }
}

func openConflictVersion(_ choice: SVNConflictChoice) {
    guard let session = activeConflictSession else { return }
    let url: URL
    switch choice {
    case .mineFull: url = session.mine.url
    case .theirsFull: url = session.server.url
    case .working: return
    }
    openWorkspaceURL(url)
}

func openConflictBackupFolder() {
    guard let directory = activeConflictSession?.directoryURL else { return }
    openWorkspaceURL(directory)
}
```

`ProjectStore.swift`에는 private `workspaceOpener`를 외부 extension에 노출하지 않는 내부 메서드를 추가한다.

```swift
func openWorkspaceURL(_ url: URL) {
    guard workspaceOpener.open(url) else {
        errorMessage = AppLanguage.current.text("파일을 열 수 없습니다.", "Could not open the file.")
        return
    }
}
```

`resolveActiveConflict`은 기존 추가 backup 호출을 제거하고 세션의 원래 details path에 `mineFull` 또는 `theirsFull`만 전달한다. 성공 시 세션을 nil로 만들고 refresh하며, 실패 시 세션과 백업을 유지한다. `ConflictFileService`의 기존 `backup`·`preserveComparableVersions`와 Store의 `preserveConflictVersions`·`openActiveConflictFile`은 삭제한다.

- [ ] **Step 5: Store 테스트를 실행하고 커밋한다.**

Run:

```bash
swift test --filter preparesBackupsOpensOnlyCopiesAndResolvesSelectedWholeVersion
swift test --filter unsupportedConflictDoesNotCreateResolutionSession
swift test --filter failedResolveKeepsConflictSession
git diff --check
```

Expected: 세 테스트 통과, 선택 전 commit 호출 없음, 실패 후 세션 유지.

```bash
git add Sources/SVNMac/ConflictFileService.swift Sources/SVNMac/ProjectStore.swift Sources/SVNMac/ProjectStore+Conflicts.swift Sources/SVNMac/ChangesView.swift Tests/SVNMacTests/ProjectStoreTests.swift
git commit -m "feat: 충돌 버전 선택 흐름 연결"
```

---

### Task 4: 두 버전 비교 화면과 최종 회귀 검증

**Files:**
- Modify: `Sources/SVNMac/ConflictResolutionView.swift`
- Modify: `Tests/SVNMacTests/ChangesViewPerformanceTests.swift`
- Verify: `Sources/SVNMac/AppLayout.swift`
- Verify: `Docs/LayoutArchitecture.md`

**Interfaces:**
- Consumes: `ProjectStore.activeConflictSession`
- Consumes: `openConflictVersion`, `openConflictBackupFolder`, `resolveActiveConflict`
- Produces: 내 파일과 서버 파일 카드 두 개, 비교용 파일 경고와 버전별 확인 alert

- [ ] **Step 1: 화면 문구와 제거 범위의 실패 테스트를 작성한다.**

`ChangesViewPerformanceTests.swift`에 다음 소스 계약을 추가한다.

```swift
@Test func conflictResolutionOffersOnlyTwoBackedUpWholeVersions() throws {
    let view = try source(named: "ConflictResolutionView.swift", in: try svnMacSources())
    #expect(view.contains("내 파일 열기"))
    #expect(view.contains("서버 파일 열기"))
    #expect(view.contains("내 파일 사용"))
    #expect(view.contains("서버 파일 사용"))
    #expect(view.contains("백업 폴더 열기"))
    #expect(view.contains("수정해도 실제 작업 파일에는 반영되지 않습니다"))
    #expect(!view.contains("두 버전 모두 원본 옆에 보관"))
    #expect(!view.contains("현재 파일로 충돌 해결 완료"))
}
```

- [ ] **Step 2: 실패를 확인한다.**

Run:

```bash
swift test --filter conflictResolutionOffersOnlyTwoBackedUpWholeVersions
```

Expected: 기존 복잡한 버튼이 남고 새 안내·백업 폴더 버튼이 없어 실패.

- [ ] **Step 3: 고정 시트 컨테이너 안에 두 버전 카드를 구현한다.**

기존 최상위 `VStack`, `appSheetFrame`과 `AppLayout.conflictResolutionSheetMinimumSize`를 유지한다. 카드에는 URL 마지막 경로, `ByteCountFormatter`, 수정 시각 또는 서버 리비전, 열기와 사용 버튼을 둔다.

```swift
private func versionCard(
    title: String,
    version: ConflictVersionBackup,
    openTitle: String,
    useTitle: String,
    choice: SVNConflictChoice
) -> some View {
    GroupBox(title) {
        VStack(alignment: .leading, spacing: 10) {
            Text(version.url.lastPathComponent).lineLimit(1)
            Text(ByteCountFormatter.string(fromByteCount: version.byteCount, countStyle: .file))
                .foregroundStyle(.secondary)
            HStack {
                Button(openTitle) { store.openConflictVersion(choice) }
                Spacer()
                Button(useTitle) { pendingChoice = choice }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}
```

두 카드 위에는 다음 안내와 버튼을 둔다.

```swift
HStack(alignment: .top) {
    Label(
        appLanguage.text(
            "내 파일과 서버 파일은 백업 폴더에 복사되었습니다. 열어 수정해도 실제 작업 파일에는 반영되지 않습니다.",
            "Both versions were copied to a backup folder. Editing these copies does not change the working file."
        ),
        systemImage: "externaldrive.badge.checkmark"
    )
    Spacer()
    Button(appLanguage.text("백업 폴더 열기", "Open Backup Folder"), systemImage: "folder") {
        store.openConflictBackupFolder()
    }
}
```

- [ ] **Step 4: 선택별 확인 경고를 구현한다.**

`pendingChoice`에 따라 alert 제목과 메시지를 분리한다.

```swift
private func confirmationMessage(for choice: SVNConflictChoice) -> String {
    switch choice {
    case .mineFull:
        appLanguage.text(
            "내 파일을 유지합니다. 이후 커밋하면 서버 파일이 이 내용으로 변경됩니다.",
            "Keep your file. A later commit will replace the repository file with this content."
        )
    case .theirsFull:
        appLanguage.text(
            "서버 파일로 교체합니다. 작업 중이던 내 변경 내용은 작업 폴더에서 사라집니다. 내 원본은 백업 폴더에 보관됩니다.",
            "Replace with the server file. Your local edits leave the working copy but remain in the backup folder."
        )
    case .working:
        ""
    }
}
```

실행 버튼만 destructive role을 사용하고 취소는 cancel role을 유지한다. 화면 본문에는 직접 병합, 부분 선택, working 선택 버튼을 남기지 않는다.

- [ ] **Step 5: UI·레이아웃·전체 테스트를 실행한다.**

Run:

```bash
swift test --filter conflictResolutionOffersOnlyTwoBackedUpWholeVersions
swift test
git diff --check
git status --short
```

Expected: 전체 테스트 0 failures. `Docs/LayoutArchitecture.md`의 최소·기본·큰 창과 시트 헤더·본문·푸터 위치 규칙에 위배되는 새 숫자 또는 중첩 split view가 없음.

- [ ] **Step 6: 화면 변경을 커밋한다.**

```bash
git add Sources/SVNMac/ConflictResolutionView.swift Tests/SVNMacTests/ChangesViewPerformanceTests.swift
git commit -m "feat: 내 파일과 서버 파일 충돌 선택 단순화"
```

- [ ] **Step 7: 앱을 패키징하고 최종 앱을 검증한다.**

Run:

```bash
./scripts/package-app.sh
codesign --verify --deep --strict "dist/SVN Mac.app"
```

Expected: production build와 패키징 성공, `dist/SVN Mac.app: valid on disk`, 최신 zip 생성. 실행 중인 앱을 새 패키지로 재시작한 뒤 미추적 폴더 안내와 충돌 시트의 두 카드·백업 폴더 버튼을 확인한다.
