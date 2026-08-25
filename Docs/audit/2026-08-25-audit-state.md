# SVN Mac 상태 정합성과 비용 감사 보고서 (감사 D)

**감사 일자**: 2026-08-25  
**감사 대상**: `Sources/SVNMac/`, `Sources/SVNCore/`, `Tests/SVNMacTests/`  
**감사 영역**: 상태 정합성, 생명주기 관리, 스테일 세션 검증, 커밋 선택 상태, SVN CLI 호출 비용, 파일 브라우저 캐시 무효화

---

## 1. 개요

### 1.1 감사 목적
본 감사는 병렬 브랜치에서 개별 개발 후 코디네이터에 의해 통합된 SVN Mac 애플리케이션의 **프로젝트 전환 생명주기**, **다단계 작업 세션의 스테일 상태 검증**, **새로고침 시 커밋 선택 경로 정합성**, **대규모 저장소 대상 SVN CLI 호출 비용**, **파일 브라우저 캐시 무효화 정합성**을 전수 점검하여 데이터 손실 및 오작동을 유발할 수 있는 결함을 식별하고 개선 방안을 제시하는 것을 목적으로 한다.

### 1.2 발견 요약
- **발견 총 건수**: 12건
- **심각도별 분류**:
  - **치명적 (Critical)**: 2건
  - **중요 (Major)**: 5건
  - **보통 (Moderate)**: 5건
  - **미미 (Minor)**: 0건

| ID | 제목 | 심각도 | 영역 | 파일 위치 | 재현 구분 |
|---|---|---|---|---|---|
| **STATE-01** | 프로젝트 전환 시 경로 복구(Path Recovery) 상태 미초기화로 인한 타 프로젝트 오작동 | 치명적 | 1. 전환 시 초기화 누락 | `ProjectStore.swift:1687`, `ProjectStore+Recovery.swift:23` | 코드 기준 추정 |
| **STATE-02** | 프로젝트 전환 시 모달 시트 플래그 미초기화로 인한 타겟 프로젝트 오작동 위험 | 치명적 | 1. 전환 시 초기화 누락 | `ProjectStore.swift:1687`, `UpdatePreviewView.swift:94` | 코드 기준 추정 |
| **STATE-03** | `DocumentOpenRequest`, `RevertRequest`, `ForceUnlockRequest`의 `projectID` 누락 | 중요 | 1. 전환 시 초기화 누락 | `ProjectStore+Locking.swift:4`, `ProjectStatusSummary.swift:11` | 코드 기준 추정 |
| **STATE-04** | 트리 충돌 해결(서버 버전 복원) 시 프로젝트 전체 강제 업데이트 실행 | 중요 | 2. 스테일 세션 검증 | `ProjectStore+Conflicts.swift:160` | 코드 기준 추정 |
| **STATE-05** | 일괄 잠금 해제(`BulkUnlockRequest`) 시 실행 직전 최신 잠금 소유권 미검증 | 보통 | 2. 스테일 세션 검증 | `ProjectStore+Locking.swift:126`, `LockWorkflow.swift:128` | 코드 기준 추정 |
| **STATE-06** | 과거 리비전 복원(`confirmHistoryRevisionRestore`) 시 로컬 미커밋 변경 덮어쓰기 | 보통 | 2. 스테일 세션 검증 | `ProjectStore+History.swift:85`, `RevisionFileService.swift:113` | 코드 기준 추정 |
| **STATE-07** | 누락(Missing) 파일 선택 후 인증 실패 재시도 또는 업데이트 후 재시도 시 커밋 실패 | 중요 | 3. 새로고침 후 선택 상태 | `ProjectStore.swift:1217, 1546`, `ProjectStore+Update.swift:95` | 코드 기준 추정 |
| **STATE-08** | 업데이트 복구 진행 중 새로고침 발생 시 사용자 수동 선택 해제 무력화 | 보통 | 3. 새로고침 후 선택 상태 | `ProjectStore.swift:1179` | 코드 기준 추정 |
| **STATE-09** | 프로젝트 새로고침 및 윈도우 활성화 시 중복 `svn status` 및 `svn status -u` 동시 실행 비용 | 중요 | 4. 비용 | `ProjectStore.swift:1018`, `ProjectStore+FileBrowser.swift:4, 26` | 코드 기준 추정 |
| **STATE-10** | 파일 검색 시 디스크 전체 트리 동기 재귀 순회로 인한 부하 및 메모리 급증 | 보통 | 4. 비용 | `ProjectStore+FileBrowser.swift:187`, `WorkingCopyFileService.swift:80` | 코드 기준 추정 |
| **STATE-11** | 커밋·되돌리기·이동·복사·무시규칙 작업 후 파일 브라우저 캐시 미무효화 | 중요 | 5. 캐시와 무효화 | `ProjectStore.swift:1251`, `WorkingCopySplitBrowserView.swift:76` | 코드 기준 추정 |
| **STATE-12** | `WorkingCopySplitBrowserState`의 `@State` 수명 분리로 인한 동기화 취약점 | 보통 | 5. 캐시와 무효화 | `WorkingCopySplitBrowserView.swift:7, 608` | 코드 기준 추정 |

---

## 2. 분야별 상세 감사 결과

### 분야 1: 전환 시 초기화 누락 (Project Switch Leaks)

#### [STATE-01] 프로젝트 전환 시 경로 복구(Path Recovery) 상태 미초기화로 인한 타 프로젝트 오작동
- **위치**: `Sources/SVNMac/ProjectStore.swift:1687-1720`, `Sources/SVNMac/ProjectStore+Recovery.swift:23-39`, `Sources/SVNMac/ChangesView.swift:39-44`
- **심각도**: 치명적 (Critical)
- **재현**: 코드 기준 추정
- **설명**: `ProjectStore.resetSelectedProjectState()`에서 `isShowingPathRecovery`, `pathRecoveryPreview`, `pathRecoverySourceProjectID` 3개 프로퍼티의 초기화가 누락되어 있다. `isShowingTemporaryFileCleanup`이나 `isShowingRepositoryPathNormalization`은 `false`로 리셋되는 반면, 유니코드 경로 복구 상태는 그대로 남는다.
- **재현 시나리오**:
  1. 프로젝트 A에서 유니코드 한글 자소 분리 충돌이 감지되어 "경로 복구" 버튼을 눌러 `WorkingCopyRecoveryView` 시트가 열린다 (`pathRecoverySourceProjectID = projectA.id`, `isShowingPathRecovery = true`).
  2. 사용자가 시트를 닫지 않은 채 사이드바에서 프로젝트 B를 클릭하여 전환한다.
  3. `resetSelectedProjectState()`가 실행되지만 `isShowingPathRecovery`가 `true`로 유지되므로 프로젝트 B 화면 위에 프로젝트 A의 복구 대상 파일 목록이 그대로 노출된다.
  4. 사용자가 대상 폴더를 지정하고 "새 작업 폴더로 복구"를 누르면 `recoverWorkingCopy(to:)`가 `pathRecoverySourceProjectID`(프로젝트 A)의 저장소 경로를 복구하여 등록하고 `selectedProjectID`를 교체한다.
- **수정 권고**: `resetSelectedProjectState()`에 아래 초기화 코드를 추가한다:
  ```swift
  isShowingPathRecovery = false
  pathRecoveryPreview = nil
  pathRecoverySourceProjectID = nil
  ```

---

#### [STATE-02] 프로젝트 전환 시 모달 시트 플래그 미초기화로 인한 타겟 프로젝트 오작동 위험
- **위치**: `Sources/SVNMac/ProjectStore.swift:1687-1720`, `Sources/SVNMac/ContentView.swift:210-231`, `Sources/SVNMac/ChangesView.swift:36-38`, `Sources/SVNMac/UpdatePreviewView.swift:94-106`, `Sources/SVNMac/FileHistoryView.swift:44-58`, `Sources/SVNMac/CredentialsView.swift:170-198`
- **심각도**: 치명적 (Critical)
- **재현**: 코드 기준 추정
- **설명**: `ProjectStore`의 화면 프레젠테이션 플래그인 `isShowingUpdatePreview`, `isShowingFileHistory`, `isShowingLocks`, `isShowingIgnoreRules`, `isShowingCredentials`가 `resetSelectedProjectState()`에서 초기화되지 않는다. 하위 도메인 스토어(`changesState`, `browserState`, `historyState`, `updateState`, `recoveryState`)는 새 인스턴스로 교체되지만 시트 플래그가 열린 채로 유지되어, 새로 선택된 프로젝트 위에서 이전 프로젝트의 의도로 열렸던 시트 액션이 새 프로젝트를 대상으로 실행된다.
- **재현 시나리오**:
  1. 프로젝트 A에서 업데이트 뱃지를 확인하고 "업데이트 미리보기" 시트를 연다 (`isShowingUpdatePreview = true`).
  2. 사이드바에서 프로젝트 B를 선택한다.
  3. 시트는 닫히지 않고 프로젝트 B 화면 위에 그대로 유지되며, `recoveryState`가 초기화되어 "수신 변경사항 없음" 또는 "업데이트 필요"로 표시된다.
  4. 사용자가 시트 하단의 "업데이트 실행" 버튼을 누르면 `store.update()`가 호출되어 **프로젝트 B에 대해 svn update가 실행**된다.
  5. 프로젝트 A의 "폴더 설정(Credentials)" 시트가 열린 상태에서 프로젝트 B로 전환 후 저장 버튼을 누를 경우 프로젝트 B의 자격증명/경로가 오염될 수 있다.
- **수정 권고**: `resetSelectedProjectState()`에서 프로젝트 종속적인 모든 모달 시트 플래그를 `false`로 명시적 초기화한다:
  ```swift
  isShowingUpdatePreview = false
  isShowingFileHistory = false
  isShowingLocks = false
  isShowingIgnoreRules = false
  isShowingCredentials = false
  ```

---

#### [STATE-03] `DocumentOpenRequest`, `RevertRequest`, `ForceUnlockRequest`의 `projectID` 누락
- **위치**: `Sources/SVNMac/ProjectStore+Locking.swift:4-16, 230-249, 335-350`, `Sources/SVNMac/ProjectStatusSummary.swift:11-14`, `Sources/SVNMac/ProjectStore+FileActions.swift:22-37`
- **심각도**: 중요 (Major)
- **재현**: 코드 기준 추정
- **설명**: `CommitConfirmationRequest`, `DeletionRequest`, `HistoryRevisionRestoreRequest` 등 다른 모든 요청 타입은 `let projectID: SVNProject.ID`를 포함하고 실행 직전 `guard selectedProjectID == request.projectID`를 검증한다. 반면 `DocumentOpenRequest`, `RevertRequest`, `ForceUnlockRequest`는 `projectID` 필드가 없으며, 실행 시 `guard let project = selectedProject`로 현재 선택된 프로젝트를 그대로 사용한다.
- **재현 시나리오**:
  1. 프로젝트 A의 변경 목록에서 파일 되돌리기(Revert) 확인 대화상자를 띄운다.
  2. 대화상자가 표시된 상태에서 단축키나 외부 이벤트로 프로젝트 B로 전환된다.
  3. 사용자가 "되돌리기" 확인을 누르면 `confirmRevert(request)`가 `selectedProject`(프로젝트 B)의 로컬 경로에 프로젝트 A의 파일 상대 경로를 전달하여 `svn revert`를 실행한다.
- **수정 권고**: `DocumentOpenRequest`, `RevertRequest`, `ForceUnlockRequest`에 `projectID: SVNProject.ID`를 추가하고, 실행 메서드에서 `guard let project = selectedProject, project.id == request.projectID else { return }`를 강제한다.

---

### 분야 2: 스테일 세션 검증 (Stale Session Validation)

#### [STATE-04] 트리 충돌 해결(서버 버전 복원) 시 프로젝트 전체 강제 업데이트 실행
- **위치**: `Sources/SVNMac/ProjectStore+Conflicts.swift:160-175`, `Sources/SVNCore/SVNClient.swift:1594-1607`
- **심각도**: 중요 (Major)
- **재현**: 코드 기준 추정
- **설명**: 단일 파일의 트리 충돌 해결 시트(`TreeConflictResolutionView`)에서 사용자가 "서버 버전 복원 (`.restoreServerVersion`)"을 선택하면, `ProjectStore.resolveActiveTreeConflict`는 해당 파일에 대해 `client.revert`를 실행한 후 `client.update(at: project.path)`를 경로 인자 없이 프로젝트 루트 전체에 대해 호출한다.
- **재현 시나리오**:
  1. 저장소의 여러 파일에 걸쳐 새로운 서버 커밋들이 발생해 있는 상태에서, 특정 한 파일 `doc/spec.docx`에 트리 충돌이 발생함.
  2. 사용자가 충돌 해결 화면에서 `doc/spec.docx`에 대해 "서버 버전으로 복원"을 선택함.
  3. 앱이 `revert` 후 `client.update(at: project.path)`를 실행하여, 사용자가 의도하지 않았던 프로젝트 내 다른 모든 미수신 변경사항까지 로컬 작업 복사본으로 일괄 내려받음.
  4. 로컬에서 작업 중이던 다른 파일들에 예기치 않은 새로운 충돌이 연쇄 발생함.
- **수정 권고**: 트리 충돌 해결 시 update 대상을 충돌이 발생한 단일 경로(`session.versionedPath`)로 한정하도록 `client.update`에 `relativePath` 지원을 추가하거나 단일 경로 업데이트를 실행한다.

---

#### [STATE-05] 일괄 잠금 해제(`BulkUnlockRequest`) 시 실행 직전 최신 잠금 소유권 미검증
- **위치**: `Sources/SVNMac/ProjectStore+Locking.swift:126-157`, `Sources/SVNMac/LockWorkflow.swift:105-108, 128-152`
- **심각도**: 보통 (Moderate)
- **재현**: 코드 기준 추정
- **설명**: `BulkUnlockRequest`는 확인 시트가 열릴 때의 `locks: [SVNLockInfo]` 목록을 스냅샷으로 캡처한다. 사용자가 확인 대화상자를 열어두고 있는 동안 다른 사용자가 잠금을 훔쳤거나(steal), 서버에서 잠금이 해제되었거나, 인증 정보가 변경되었더라도 실행 직전 저장소의 최신 잠금 목록을 재조회하지 않고 스냅샷에 저장된 목록으로 `BulkUnlockExecutor.run`을 즉시 실행한다.
- **재현 시나리오**:
  1. 사용자가 10개 파일의 일괄 잠금 해제 확인 창을 띄움.
  2. 동료 사용자가 관리자 권한으로 그중 2개 파일의 잠금을 해제하고 새로 잠금을 획득함.
  3. 사용자가 "잠금 해제"를 누르면 앱이 이미 소유권이 바뀐 파일에 대해 unlock을 시도하여 E195022 오류가 발생하고 실패 목록에 표시됨.
- **수정 권고**: `confirmBulkUnlock` 실행 시작 시 `client.repositoryLocks`를 재조회하여 여전히 현재 사용자 소유로 확인된 잠금만 필터링하여 해제한다.

---

#### [STATE-06] 과거 리비전 복원(`confirmHistoryRevisionRestore`) 시 로컬 미커밋 변경 덮어쓰기
- **위치**: `Sources/SVNMac/ProjectStore+History.swift:85-115`, `Sources/SVNMac/RevisionFileService.swift:113-182`
- **심각도**: 보통 (Moderate)
- **재현**: 코드 기준 추정
- **설명**: 과거 커밋 리비전의 파일 내용을 작업 복사본에 복원할 때 `RevisionFileService.restoreWorkingFile`이 실행 시점의 작업 파일을 `Revision Restore Backups` 디렉터리에 보존한다. 그러나 복원 확인 대화상자가 표시된 시점과 사용자가 "복원"을 클릭하는 시점 사이에 외부 에디터에서 해당 파일이 수정되었을 경우, 변경사항을 알리지 않고 덮어쓴다 (백업은 덮어쓰기 직전 상태로 저장됨).
- **수정 권고**: 확인 대화상자 표시 시점의 파일 수정일시(mtime/size)를 요청에 기록하고, 실행 시점에 파일 속성이 변경되었으면 사용자에게 최신 변경이 있음을 재확인하는 절차를 둔다.

---

### 분야 3: 새로고침 후 선택 상태 (Selection State on Refresh)

#### [STATE-07] 누락(Missing) 파일 선택 후 인증 실패 재시도 또는 업데이트 후 재시도 시 커밋 실패
- **위치**: `Sources/SVNMac/ProjectStore.swift:1217-1233, 1546-1554`, `Sources/SVNMac/ProjectStore+Update.swift:95-120`, `Sources/SVNMac/ProjectStore+Deletion.swift:122-132`
- **심각도**: 중요 (Major)
- **재현**: 코드 기준 추정
- **설명**:
  - 로컬에서 삭제되어 SVN 상태가 `missing`인 파일은 `canScheduleRepositoryDeletion == true`이므로 `selectableStatusPaths` 및 `selectAllStatusPaths`에 포함되어 체크박스 선택이 가능하다.
  - 사용자가 "커밋"을 누르면 `commitSelectedChanges`가 먼저 `scheduleSelectedMissingDeletions`(`svn delete --force`)를 실행하여 missing 항목을 deleted로 만든 후 `commit`을 호출한다.
  - 그러나 커밋 과정에서 인증 오류(E170001)가 발생하여 자격증명 입력 후 `resume`되거나, 저장소 out of date로 인해 `retryCommitAfterUpdate`가 실행될 때는 `commitSelectedChanges(message:)`가 아닌 `commit(message:)`를 직접 호출한다.
  - `ProjectStore.commit(message:)`는 1220~1229번 라인에서 `statuses`에 `item == .missing`인 선택 파일이 있으면 `error.choose.missing.items` 오류를 내며 즉시 중단된다.
- **재현 시나리오**:
  1. Finder에서 `sample.xlsx` 파일을 삭제하여 SVN 상태가 `missing`이 됨.
  2. "전체 선택" 후 커밋 메시지를 입력하고 커밋을 누름.
  3. 서버에서 out-of-date 오류가 반환되어 "업데이트 필요" 복구 상태로 진입함 (`recovery.paths = ["sample.xlsx"]`).
  4. 사용자가 "업데이트 후 커밋 재시도"를 클릭함.
  5. 업데이트가 완료된 후 `retryCommitAfterUpdate`가 `commit(message: recovery.message)`를 직접 호출함.
  6. `sample.xlsx`가 여전히 `missing` 상태이므로 `commit(message:)`의 가드에 걸려 "선택한 누락 항목을 먼저 처리하십시오" 오류가 발생하며 커밋 재시도가 영구 실패함.
- **수정 권고**: `resume` 및 `retryCommitAfterUpdate`에서 `commit(message:)` 대신 `commitSelectedChanges(message:)`를 호출하도록 변경한다.

---

#### [STATE-08] 업데이트 복구 진행 중 새로고침 발생 시 사용자 수동 선택 해제 무력화
- **위치**: `Sources/SVNMac/ProjectStore.swift:1179-1184`
- **심각도**: 보통 (Moderate)
- **재현**: 코드 기준 추정
- **설명**: `ProjectStore.applyLocalWorkingCopyRefresh`는 로컬 상태 새로고침마다 아래 로직을 수행한다:
  ```swift
  if let recovery = recoveryState.outOfDateCommitRecoveryRequest,
     recovery.projectID == project.id {
      selectedPaths.formUnion(recovery.paths)
  }
  selectedPaths.formIntersection(selectableStatusPaths)
  ```
  커밋 실패 후 업데이트 복구 시트가 떠 있는 상태에서 사용자가 특정 파일의 체크박스를 수동으로 해제하더라도, 백그라운드 뱃지 폴링, 탭 전환, 윈도우 활성화에 의한 자동 새로고침이 발생하면 `recovery.paths`에 있던 모든 경로가 `selectedPaths`에 다시 강제 병합된다.
- **수정 권고**: `selectedPaths.formUnion(recovery.paths)`는 복구 요청 생성 시점에 1회만 수행하고, 매 새로고침 루프에서 반복 병합하지 않도록 수정한다.

---

### 분야 4: 비용 (Cost Calculation & SVN CLI Commands)

#### [STATE-09] 프로젝트 새로고침 및 윈도우 활성화 시 중복 `svn status` 및 `svn status -u` 동시 실행 비용
- **위치**: `Sources/SVNMac/ProjectStore.swift:1018-1037, 1073-1090, 1165-1174`, `Sources/SVNMac/ProjectStore+FileBrowser.swift:4-17, 26-28, 46-52`, `Sources/SVNMac/SVNClient.swift:637-650, 653-666, 1069-1076, 1568-1576`
- **심각도**: 중요 (Major)
- **재현**: 코드 기준 추정
- **비용 분석 및 호출 횟수 계산**:

| 작업 | 호출되는 SVN 명령 | 명령 수 | 중복 여부 |
|---|---|---|---|
| **업데이트 뱃지 폴러** (`UpdateBadgePoller`) | 등록된 프로젝트당 `svn status --show-updates --xml` | **프로젝트 수 N × 1회** (60초 주기) | 60초마다 전체 프로젝트에 N개 네트워크 프로세스 생성. 실패 시 지수 백오프 (60s $\rightarrow$ 120s $\rightarrow$ 240s $\rightarrow$ 480s $\rightarrow$ 900s). |
| **`incomingCommits`** (1회 호출) | 1. `svn status --verbose --xml`<br>2. `svn info --revision HEAD --show-item revision`<br>(신규 커밋 있는 경우 추가)<br>3. `svn log --revision {base+1}:HEAD --verbose --xml --with-all-revprops`<br>4. `svn info --show-item relative-url`<br>5. `svn status --show-updates --xml` | **최소 2회, 최대 5회** (네트워크 명령 3회 포함) | `updatePreview` 열릴 때마다 5회 프로세스 스폰. |
| **단일 프로젝트 새로고침** (`refreshSelectedProject`) | **동시 실행 태스크 1 (refresh)**:<br>- `svn status --verbose --no-ignore --xml` (snapshot)<br>- `svn info --show-item relative-url`<br>- `svn log --limit 50`<br>- `svn status --show-updates --xml` (outOfDate)<br>**동시 실행 태스크 2 (browser)**:<br>- `svn status --verbose --no-ignore --xml` (entries)<br>- `svn status --show-updates --xml` (locks)<br>**동시 실행 태스크 3 (badge)**:<br>- 타 프로젝트 N-1개에 `svn status -u` | **선택 프로젝트 6회 + 타 프로젝트 (N-1)회** | **동일 작업 복사본에 대해:**<br>1. `svn status -v --no-ignore` **2회 중복 동시 실행**<br>2. `svn status -u` **2회 중복 동시 실행** |
| **윈도우 활성화 자동 새로고침** (`refreshForMainWindowActivation`) | - `svn status --verbose --no-ignore --xml` (snapshot)<br>- `svn info --show-item relative-url`<br>- `svn status --verbose --no-ignore --xml` (browser entries) | **총 3회** | 윈도우 포커스 전환마다 `status -v` **2회 중복 동시 실행** |

- **문제점**: 수천~수만 파일 규모의 대형 저장소에서 `svn status --verbose --no-ignore`는 작업 복사본 전체의 메타데이터와 파일시스템을 스캔하는 가장 무거운 명령이다. `refreshSelectedProject`와 `refreshForMainWindowActivation`이 이를 2개의 비동기 태스크로 동시에 실행하여 SQLite `.svn/wc.db` 파일 락 경합 및 디스크 I/O를 2배로 낭비하고 UI 프리징 위험을 높인다.
- **수정 권고**: `workingCopySnapshot` 1회 결과로 `workingCopyBrowserSVNEntries`까지 함께 파생하여 브라우저에 공급하고, `status -u` 역시 1회 호출로 outOfDate 판정과 repositoryLocks 파싱을 공유하도록 통합한다.

---

#### [STATE-10] 파일 검색 시 디스크 전체 트리 동기 재귀 순회로 인한 부하 및 메모리 급증
- **위치**: `Sources/SVNMac/ProjectStore+FileBrowser.swift:187-211`, `Sources/SVNMac/WorkingCopyFileService.swift:80-140`
- **심각도**: 보통 (Moderate)
- **재현**: 코드 기준 추정
- **설명**: 파일 브라우저에서 검색창에 타이핑할 때 `searchWorkingCopyFiles`가 호출되며, 이는 `workingCopyFileService.tree`를 호출하여 전체 작업 복사본 디렉터리 구조를 디스크에서 재귀적으로 생성한다. `ChangesViewPerformanceTests`는 화면 컴포넌트의 텍스트 구성 및 isolated view 분리만 검증할 뿐 대규모 파일 검색 경로의 비동기 부하/메모리를 보장하지 않는다.
- **수정 권고**: 이미 로드된 `workingCopyBrowserSVNEntries` 인메모리 배열 기반으로 경로 문자열을 먼저 필터링하고 필요한 노드만 인덱싱하는 경량 검색 방식을 채택한다.

---

### 분야 5: 캐시와 무효화 (Cache and Invalidation)

#### [STATE-11] 커밋·되돌리기·이동·복사·무시규칙 작업 후 파일 브라우저 캐시 미무효화
- **위치**: `Sources/SVNMac/ProjectStore.swift:1251, 1258`, `Sources/SVNMac/ProjectStore+FileActions.swift:30`, `Sources/SVNMac/ProjectStore+Ignore.swift:23, 44`, `Sources/SVNMac/ProjectStore+RepositoryMaintenance.swift:81, 107`, `Sources/SVNMac/ProjectStore+Conflicts.swift:185, 260`, `Sources/SVNMac/WorkingCopySplitBrowserView.swift:76-78`, `Sources/SVNMac/ProjectStore+FileBrowser.swift:36`
- **심각도**: 중요 (Major)
- **재현**: 코드 기준 추정
- **설명**:
  - `WorkingCopySplitBrowserView`의 캐시(`WorkingCopySplitBrowserState`) 및 트리 브라우저 캐시(`workingCopyBrowserTreeState`)는 오직 `workingCopyBrowserRefreshGeneration`이 증가할 때만 무효화/갱신된다.
  - `workingCopyBrowserRefreshGeneration &+= 1`은 오직 `loadWorkingCopyFiles()`(36번 라인)에서만 호출된다.
  - 그러나 아래의 모든 핵심 작업 핸들러는 작업 성공 후 `refresh()` 또는 `refreshLocalWorkingCopy()`만 호출할 뿐 `loadWorkingCopyFiles()`나 `workingCopyBrowserRefreshGeneration`을 갱신하지 않는다:
    1. **커밋 완료 후** (`commit(message:)`)
    2. **파일 되돌리기 후** (`confirmRevert`)
    3. **이력 유지 파일 이동/복사 후** (`performVersionedFileAction`)
    4. **무시 규칙 추가/제거 후** (`addIgnoreRule`, `removeIgnoreRule`)
    5. **충돌 해결 완료 후** (`resolveActiveConflict`, `resolveActiveTreeConflict`)
    6. **과거 리비전 복원 후** (`confirmHistoryRevisionRestore`)
- **재현 시나리오**:
  1. 파일 브라우저(분할 뷰 또는 트리 뷰)에서 `Report.xlsx`의 상태가 "수정됨(M)"으로 표시되는 것을 확인.
  2. "변경사항" 탭으로 이동하여 `Report.xlsx`를 커밋 완료함.
  3. 다시 "파일" 탭으로 돌아오면 `Report.xlsx`가 여전히 "수정됨"으로 남아 있음.
  4. 파일 브라우저에서 `Old.swift`를 "이력 유지하며 이름 변경"으로 `New.swift`로 이동함.
  5. 캐시가 무효화되지 않아 폴더 목록에는 여전히 `Old.swift`가 보이고 `New.swift`는 나타나지 않음.
- **수정 권고**: `refresh()` 및 `refreshLocalWorkingCopy()` 내부에서 또는 각 작업 완료 시점에 `workingCopyBrowserRefreshGeneration &+= 1`을 트리거하거나 `refreshWorkingCopyBrowser()`를 함께 호출한다.

---

#### [STATE-12] `WorkingCopySplitBrowserState`의 `@State` 수명 분리로 인한 동기화 취약점
- **위치**: `Sources/SVNMac/WorkingCopySplitBrowserView.swift:7-8, 608-612`, `Sources/SVNMac/ProjectStore.swift:1687`
- **심각도**: 보통 (Moderate)
- **재현**: 코드 기준 추정
- **설명**: 분할 파일 브라우저의 핵심 상태인 `WorkingCopySplitBrowserState`(폴더 펼침, 선택 폴더, 디렉터리 캐시)가 `ProjectStore`의 도메인 스토어가 아닌 `WorkingCopySplitBrowserView`의 SwiftUI `@State private var browserState`로 소유되어 있다. 이로 인해 `ProjectStore` 수준에서 프로젝트가 전환되거나 초기화될 때 SwiftUI 뷰 수명주기 이벤트(`.task(id: store.selectedProjectID)`, `.onChange(of: store.workingCopyBrowserRefreshGeneration)`)에만 의존하여 리셋되므로, 뷰가 비활성 상태일 때 백그라운드 상태 변경이 유실될 위험이 존재한다.
- **수정 권고**: `WorkingCopySplitBrowserState`를 `ProjectBrowserStore` 내부로 편입하여 `ProjectStore`가 일원화된 생명주기로 관리하도록 통합한다.

---

## 3. 종합 평가와 우선순위

### 3.1 즉시 조치 필요 항목 (P0 — 릴리즈 전 필수 수정)
1. **[STATE-01]** `ProjectStore.resetSelectedProjectState()`에 유니코드 경로 복구 프로퍼티(`isShowingPathRecovery`, `pathRecoveryPreview`, `pathRecoverySourceProjectID`) 초기화 추가.
2. **[STATE-02]** `resetSelectedProjectState()`에 모달 프레젠테이션 플래그(`isShowingUpdatePreview`, `isShowingFileHistory`, `isShowingLocks`, `isShowingIgnoreRules`, `isShowingCredentials`) 초기화 추가.
3. **[STATE-07]** `ProjectStore.resume` 및 `retryCommitAfterUpdate`에서 `commit(message:)` 대신 `commitSelectedChanges(message:)`를 호출하도록 수정하여 missing 항목 커밋 재시도 실패 해결.
4. **[STATE-11]** `commit`, `revert`, `ignore`, `fileAction` 성공 후 파일 브라우저 세대 번호(`workingCopyBrowserRefreshGeneration`) 증가 및 캐시 무효화 연동.

### 3.2 단기 개선 항목 (P1 — 다음 패치 마일스톤)
1. **[STATE-03]** `DocumentOpenRequest`, `RevertRequest`, `ForceUnlockRequest`에 `projectID` 필드 추가 및 실행 전 일치 검증 강제.
2. **[STATE-04]** 트리 충돌 서버 복원 시 프로젝트 전체 update 대신 충돌 단일 경로 update로 한정.
3. **[STATE-09]** `refreshSelectedProject` 및 `refreshForMainWindowActivation`의 중복 `svn status -v --no-ignore` 및 `svn status -u` 단일 호출 공유 구조로 리팩토링.
4. **[STATE-08]** `applyLocalWorkingCopyRefresh`의 반복적 `recovery.paths` 재선택 로직 단발성으로 제한.

### 3.3 장기 개선 항목 (P2 — 아키텍처 정리)
1. **[STATE-05]** `BulkUnlockRequest` 실행 직전 저장소 최신 잠금 소유권 실시간 재검증.
2. **[STATE-06]** 과거 리비전 복원 시 확인 시점과 실행 시점 간 파일 mtime 변경 감지 및 충돌 경고.
3. **[STATE-10]** 파일 브라우저 검색 시 파일시스템 재귀 순회 대신 인메모리 SVN 엔트리 인덱스 검색으로 전환.
4. **[STATE-12]** `WorkingCopySplitBrowserState`를 `ProjectBrowserStore`로 이동하여 단일 상태 소유권 확립.
