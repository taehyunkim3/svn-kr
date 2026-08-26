# 전수 감사 B3b 전수 감사

## 읽은 파일
- Sources/SVNMac/LockConfirmation.swift — 34줄 — 다른 사람 잠금을 강제로 빼앗기 전 확인 알림
- Sources/SVNMac/MainWindowActivationView.swift — 72줄 — 메인 창이 key가 될 때만 로컬 새로고침을 거는 NSView 브리지
- Sources/SVNMac/PropertyConflictResolutionView.swift — 171줄 — 속성 충돌 mine/theirs 선택과 파괴 확인
- Sources/SVNMac/RepositoryBrowserView.swift — 256줄 — 체크아웃 전 저장소 URL을 탐색하는 시트
- Sources/SVNMac/RepositoryDialogs.swift — 915줄 — 인증, 체크아웃 추가, 폴더 설정, relocate, 이름변경/복사
- Sources/SVNMac/RepositoryLocksView.swift — 159줄 — 저장소 잠금 목록, 개별/일괄 해제, 강제 해제
- Sources/SVNMac/RepositoryPathNormalizationView.swift — 481줄 — 저장소 경로 NFC 정규화 대상 선택과 확인
- Sources/SVNMac/RevertConfirmation.swift — 28줄 — 로컬 되돌리기 확인 알림
- Sources/SVNMac/SVNLogMessageView.swift — 41줄 — 커밋 메시지와 잘못 인코딩된 원문 팝오버
- Sources/SVNMac/TemporaryFileCleanupView.swift — 96줄 — 업데이트 뒤 검증된 임시파일을 골라 삭제·커밋
- Sources/SVNMac/TreeConflictResolutionView.swift — 206줄 — 트리 충돌 유지/서버복원과 하위 경로 경고
- Sources/SVNMac/UpdatePreviewView.swift — 272줄 — 업데이트 미리보기와 기한 지난 커밋 재시도
- Sources/SVNMac/WorkingCopyBrowserView.swift — 394줄 — 트리형 작업 복사본 파일 브라우저
- Sources/SVNMac/WorkingCopyRecoveryView.swift — 122줄 — 유니코드 경로 충돌을 새 폴더 체크아웃으로 복구
- Sources/SVNMac/WorkingCopySplitBrowserView.swift — 779줄 — 기본 파일 탭의 분할 폴더/내용 브라우저

이전 감사 10건 중 이 블록과 겹치는 항목은 `Docs/audit/2026-08-25-audit-ui.md`, `audit-destructive.md`, `audit-concurrency.md`, `audit-state.md`, `dead-end-audit-cursor.md`를 대조했다. 이미 고친 항목(파괴적 Return, 트리 충돌 하위 경로 표시, 프로젝트 전환 초기화, 브라우저 캐시 무효화)은 다시 적지 않는다.

## 발견
### 진행 중인 업데이트·정리·복구 시트를 닫아도 작업이 계속된다
- 심각도: 높음
- 근거: Sources/SVNMac/UpdatePreviewView.swift:21, 94; Sources/SVNMac/TemporaryFileCleanupView.swift:16-17, 58-71; Sources/SVNMac/WorkingCopyRecoveryView.swift:19-21, 90-92; Sources/SVNMac/ProjectStore+Update.swift:34-38, 167-233. 체크아웃·충돌·경로 정규화 시트는 `interactiveDismissDisabled`가 있다. 이 세 시트는 없다. 업데이트 미리보기의 닫기는 진행 중에도 활성이다.
- 재현: 코드 기준 추정
- 트리거: 커밋이 기한 지남 → 업데이트 미리보기에서 「업데이트 실행」→ 진행 중에 「닫기」또는 Escape. 또는 임시파일 「삭제하고 커밋」중 닫기. 또는 경로 복구가 도는 중 시트를 제스처로 닫기.
- 증상: 화면은 취소된 것처럼 사라진다. `Task { await store.update() }`는 뷰 수명과 무관해서 업데이트가 끝까지 간다. 기한 지난 커밋 복구가 있으면 `retryCommitAfterUpdate`까지 이어져 저장해 둔 메시지로 커밋이 올라간다. 임시파일 정리는 선택 경로를 저장소에서 지우고 커밋한다. 경로 복구는 새 작업 복사본을 등록하고 선택을 옮긴다.
- 확률: 사무실 작업 복사본 업데이트는 수 초~수십 초 걸린다. 기한 지난 커밋 후 업데이트 재시도는 이 팀에서 흔한 경로다.
- 고치는 방법: 진행 중 `interactiveDismissDisabled`를 켜고, 닫기 버튼을 비활성으로 두거나 닫기를 취소 확인으로 바꾼다. 업데이트 태스크를 시트 닫기와 함께 취소하지 않을 거면 닫기를 막아야 한다.

### 폴더 되돌리기 확인이 하위 파일까지 버린다고 말하지 않는다
- 심각도: 높음
- 근거: Sources/SVNMac/RevertConfirmation.swift:17-21; Sources/SVNCore/SVNClient.swift:1685-1688 (`svn revert --depth infinity`). 확인 문구 키 `ui.uncommitted.changes.in.will.be.discarded.and.can`는 선택한 경로 이름만 넣는다.
- 재현: 실제 재현함. 임시 `file://` 저장소에 `공유/보고서.xlsx`, `공유/메모.hwp`를 커밋한 뒤 두 파일을 수정하고 폴더에 `svn:ignore`를 걸었다. 앱과 같은 `svn revert --depth infinity 공유`를 실행하자 폴더 속성뿐 아니라 두 파일의 로컬 수정도 전부 되돌아갔다.
- 트리거: 변경 탭에서 속성만 바뀐 한글 폴더 행을 우클릭 → 「로컬 변경 되돌리기」→ 확인. 같은 폴더 아래 xlsx/hwp는 목록에 따로 있어도, 폴더만 되돌리면 함께 사라진다.
- 증상: 알림은 「공유의 커밋하지 않은 변경이 삭제됩니다. 이 작업은 SVN으로 복구할 수 없습니다.」만 보인다. 확인 후 하위 문서 편집이 전부 원본으로 돌아간다.
- 확률: 이 팀은 폴더 단위 문서 공유가 많다. 속성 변경 폴더와 수정 파일이 한 목록에 같이 나온다. 폴더만 되돌린다고 읽기 쉽다.
- 고치는 방법: 디렉터리면 하위 미커밋 파일 개수·경로를 확인 문구에 넣고, 가능하면 폴더 되돌리기는 `--depth empty`로 제한한다.

### 폴더 설정에서 위치 변경이 성공한 뒤 계정 확인 실패를 취소하면 폴더는 새 위치에 남는다
- 심각도: 중간
- 근거: Sources/SVNMac/RepositoryDialogs.swift:559-561, 636-677. `save()`는 `relocateProject`를 먼저 커밋한 다음 `verifyCredentials`를 한다. 확인 실패 알림의 「변경 취소하고 닫기」만 `discardChanges()`로 폴더를 되돌린다. 시트 「취소」는 `dismiss()`만 한다.
- 재현: 코드 기준 추정
- 트리거: 폴더 설정에서 로컬 폴더를 옮긴 뒤 저장. 새 위치는 작업 복사본이라 relocate는 성공하고, 입력한 비밀번호가 틀려 계정 확인만 실패. 알림에서 「유효한 계정 입력」을 고른 다음 시트에서 「취소」.
- 증상: 시트는 닫힌다. 앱이 가리키는 로컬 폴더는 이미 새 경로다. 비밀번호는 저장되지 않았다. 주석은 「확인 전에는 아무것도 바꾸지 않는다」고 하지만 relocate는 이미 반영된 상태다.
- 확률: 작업 폴더를 Finder에서 옮긴 뒤 앱에서 위치를 맞추는 일은 있다. 그 직후 비밀번호를 다시 넣는 실수도 있다.
- 고치는 방법: 폴더 이동과 계정 저장을 한 트랜잭션으로 묶거나, 시트 취소·닫기가 `discardChanges()`와 같은 경로를 타게 한다. relocate는 계정 확인 통과 뒤로 미룬다.

### 기본 분할 파일 브라우저는 새로고침 후 needs-lock 표시를 다시 읽지 않는다
- 심각도: 중간
- 근거: Sources/SVNMac/WorkingCopySplitBrowserView.swift:76-78, 614-676; Sources/SVNMac/WorkingCopyBrowserView.swift:101-102, 205-209. 트리 보기는 보이는 행이 바뀔 때마다 `loadNeedsLockState`를 다시 부른다. 분할 보기의 `loadDirectory`만 호출하고, 이미 캐시된 디렉터리는 건너뛴다. 창 활성화·커밋 뒤 `reloadCachedDirectories`는 캐시만 갈아끼우고 `loadNeedsLockState`를 부르지 않는다. 파일 탭 기본값은 분할이다.
- 재현: 코드 기준 추정
- 트리거: 분할 보기에서 폴더를 연 뒤, 다른 사람이 `svn:needs-lock`을 켠 파일을 업데이트로 받는다. 또는 창을 다른 앱에 갔다가 돌아온다.
- 증상: 잠금이 필요한 파일에 자물쇠 네모가 없거나, 꺼진 속성이 아이콘으로 남는다. 같은 폴더에 머무르면 프로젝트 전환 전까지 갱신되지 않는다. 트리 보기로 바꾸면 `.task(id: needsLockPathsToLoad)`가 다시 돌아 아이콘이 맞는다.
- 확률: 이 팀은 xlsx/hwp에 needs-lock을 쓴다. 기본 UI가 분할 보기라 트리 보기의 보정 경로를 안 탄다.
- 고치는 방법: `reloadCachedDirectories` 끝에 현재 디렉터리의 버전 파일로 `loadNeedsLockState`를 다시 부른다. 트리 보기와 같은 `.task`를 분할 보기에도 붙인다.

### 저장소 둘러보기에서 파일을 고르면 「이 저장소 경로 사용」이 꺼진다
- 심각도: 낮음
- 근거: Sources/SVNMac/RepositoryBrowserView.swift:228-233; Sources/SVNMac/RepositoryBrowserState.swift:128-133. 선택이 없으면 `currentURL`을 쓴다. 디렉터리를 고르면 그 하위 URL. 파일을 고르면 `nil`.
- 재현: 코드 기준 추정. `repositoryBrowserSelectionStoresFullCheckoutURL`은 디렉터리만 검증한다.
- 트리거: 저장소 추가 → 저장소 둘러보기 → 폴더에 들어가 xlsx를 한 번 클릭 → 「이 저장소 경로 사용」.
- 증상: 버튼이 비활성이다. 지금 보고 있는 폴더 URL은 유효한데, 파일 선택을 해제해야 다시 살아난다. 안내 문구는 없다.
- 확률: 둘러보기는 체크아웃 URL을 고르려고 연다. 목록에서 문서를 눌러 확인하는 동작이 자연스럽다.
- 고치는 방법: 파일 선택이면 `currentURL`을 체크아웃 경로로 쓴다. 디렉터리 선택만 하위로 붙인다.

### 파일 기록·이름변경·잠금 확인 시트가 같은 상태에 여러 번 붙어 있다
- 심각도: 중간
- 근거: Sources/SVNMac/WorkingCopyBrowserView.swift:91-109; Sources/SVNMac/WorkingCopySplitBrowserView.swift:66-89; Sources/SVNMac/ContentView.swift:385-396. 기본 분할이면 트리 브라우저가 opacity 0으로 같이 살아 있고, 둘 다 `isShowingFileHistory`, `versionedFileActionRequest`, `documentOpenConfirmation`, `explicitLockConfirmation`을 붙인다. 변경 탭 `ChangesView`에도 같은 수식어가 있다. 2026-08-25 UI 감사와 동일하고 아직 남아 있다.
- 재현: 코드 기준 추정. GUI로 시트가 실제로 안 뜨는지는 확인하지 않았다.
- 트리거: 파일 탭(기본 분할)에서 버전 파일 우클릭 → 커밋 기록, 이력 보존 이름변경, 강제 잠금 검토. 또는 문서 더블클릭.
- 증상: SwiftUI가 같은 `Binding`의 `.sheet`/`.alert`를 여러 부모에 붙이면 시트가 안 뜨거나 숨은 트리 보기 쪽에 붙는다. 사용자는 잠금 확인이나 이름변경 창이 없는 것처럼 느낀다.
- 확률: 파일 탭 기본값이 분할이라 첫 실행부터 트리+분할이 동시에 존재한다. xlsx 열기와 이름변경은 이 팀에서 흔하다.
- 고치는 방법: 시트와 확인창을 `ContentView` 또는 파일 탭 컨테이너 한곳에만 붙인다. 자식 두 브라우저와 변경 탭에서 중복을 뺀다.

## 블록 경계
- `RevertConfirmation` → `ProjectStore.confirmRevert` → `SVNClient.revert`의 `--depth infinity`. 화면 문구는 파일 단위, 실제 명령은 하위 트리. 계약이 어긋난다.
- `UpdatePreviewView` / `TemporaryFileCleanupView` → `ProjectStore+Update`. 미리보기에서 실행한 `update()`가 끝나면 시트가 닫혀 있어도 `retryCommitAfterUpdate`와 `confirmRepositoryTemporaryFileCleanup`이 이어서 돈다. 화면 소유와 작업 수명이 분리돼 있다.
- `WorkingCopySplitBrowserView.reloadCachedDirectories` → `ProjectStore.loadWorkingCopyDirectoryContents`. 트리 브라우저의 `loadNeedsLockState` 계약을 분할 쪽이 안 지킨다. `needsLockPaths`는 `ProjectRecoveryState`에 있고 변경 탭도 같은 집합을 본다. 분할 보기만  stale이 되면 탭 사이 아이콘이 갈라진다.
- `WorkingCopyBrowserView`와 `WorkingCopySplitBrowserView`가 컨텍스트 메뉴·잠금 배지·아이콘·상태 문구를 각각 복사한다. 수정일 표시는 이미 갈라졌다. 트리는 `WorkingCopyFileDateFormatting`, 분할은 `Date.FormatStyle` + 시스템 로케일. 앱 언어와 macOS 언어가 다르면 같은 파일이 탭 전환만으로 다른 날짜 문자열을 보여 준다.
- `LockConfirmation` / `RepositoryLocksView` → `ProjectStore+Locking`. 강제 잠금 요청에 `projectID`가 없다. 프로젝트 전환 시 `resetSelectedProjectState`가 `recoveryState`를 비워 지금은 막히지만, 확인창이 열린 채 전환되지 않는 다른 경로가 생기면 `selectedProject`에 대해 force lock이 나간다.
- `RepositoryLocksView` 부분 실패 알림은 `BulkUnlockFailure.message`를 그대로 보여 준다. 메시지 출처는 `LockWorkflow.swift`의 `String(describing: error)`라 Swift 오류 덤프가 사용자에게 보인다.
- `RepositoryBrowserView` → `AddRepositoryView`. 둘러보기 자격 증명은 시트를 열 때 한 번 캡처한다. 둘러보기를 연 뒤 추가 화면에서 비밀번호를 고쳐도 이미 열린 브라우저에는 안 반영된다.
- `WorkingCopyRecoveryView` → `ProjectStore+Recovery` / `SVNClient.recoverWorkingCopy`. 빈 폴더 검사는 클라이언트가 한다. 화면은 선택만 막고, 복구 도중 시트를 닫아도 `pathRecoverySourceProjectID`는 남는다. 성공 시 선택이 복구 복사본으로 바뀐다.
- `MainWindowActivationView` → `refreshForMainWindowActivation`. 모달이 열린 동안에도 창이 key가 되면 로컬 `status`가 다시 돈다. 확인창 문구의 경로 집합이 밑에서 바뀔 수 있다. 이전 감사와 같은 경계이고, 이번 블록은 훅만 제공한다.
- `PropertyConflictResolutionView` / `TreeConflictResolutionView` → `ProjectStore+Conflicts`. 해결 호출은 화면이 세션 존재를 재확인하지 않는다. 스토어 쪽이 세션 ID를 검사한다. 닫기 후 늦게 끝나는 `await`는 스토어 가드에 의존한다.

## 검증 공백
- `UpdatePreviewView`: `canRunUpdate`와 미리보기 실패 시 업데이트 허용은 있다. 진행 중 닫기, Escape, `retryCommitAfterUpdate`가 시트 dismiss 이후에도 도는지 검증하는 테스트는 없다. 넣을 입력: 미리보기 표시 중 `update()`를 시작하고 `isShowingUpdatePreview = false`로 만든 뒤 커밋 재시도가 호출되는지.
- `TemporaryFileCleanupView`: 스토어의 부분 실패·커밋 실패 되돌리기는 `ProjectStoreTests`에 있다. 뷰의 닫기 활성, `interactiveDismissDisabled` 부재는 소스 검색으로도 안 잡는다. 넣을 입력: 정리 중 `isShowingTemporaryFileCleanup`을 false로 두었을 때 커밋이 계속되는지.
- `RevertConfirmation`: Return을 확인에 안 묶는지만 본다. 디렉터리 + 하위 수정 파일 픽스처로 확인 문구에 하위 개수가 들어가는지, 실제 revert 깊이인지는 없다. 이번 `file://` 재현이 그 공백을 메운 증거다.
- `CredentialsView.save`: relocate 성공·자격 증명 실패 뒤 시트를 취소하는 경로가 없다. 넣을 입력: relocate 후 `verifyCredentials` 실패, `dismiss()`만 호출, `projects[].path`가 새 경로로 남는지.
- `WorkingCopySplitBrowserView`: 캐시 교체 단위 테스트는 있다. 교체 후 `loadNeedsLockState` 호출 여부는 안 본다. 넣을 입력: 캐시된 디렉터리에 needs-lock이 생긴 뒤 `workingCopyBrowserRefreshGeneration`을 올리고 `needsLockPaths`가 갱신되는지.
- `RepositoryBrowserState.checkoutURL`: 디렉터리 선택만 테스트한다. 파일 선택 픽스처가 없다. 넣을 입력: `kind == .file`인 항목을 고른 뒤 `checkoutURL == currentURL`이어야 한다.
- `WorkingCopyBrowserView` / `WorkingCopySplitBrowserView` 중복 `.sheet`: 소스에 문자열이 있는지만 본다. 두 뷰가 동시에 마운트된 채 시트가 실제로 붙는지는 없다.
- `SVNLogMessageView`, `MainWindowActivationView`, `LockConfirmation`: 배선·옵저버·문구 테스트만 있다. 한글 NFD 경로 표시, 확인창이 열린 동안 창 활성화 새로고침은 없다.
- `RepositoryLocksView` 일괄 해제 확인은 개수만 보여 준다. 경로 목록이 확인창에 나오는지는 테스트하지 않는다.
- `WorkingCopySplitBrowserView.moveContentSelection`은 상태 테스트는 있으나 뷰의 키 핸들러에 연결되어 있지 않다. 내용 패널 위아래 키는 Table 기본 동작에만 의존한다.

관련 기존 테스트는 `swift test --filter`로 68개 돌려 통과했다. `RepositoryBrowserTests`, `UpdatePreviewStateTests`, `LockWorkflowTests`, `WorkingCopySplitBrowserStateTests`, `PropertyConflictResolutionTests`, `MainWindowActivationTests`, `DestructiveReturnKeyTests`, `FileBrowserViewModeTests`, `RepositoryPathNormalizationPresentationTests`, `WorkingCopyRecoveryTests`.

## 확인하지 않은 것
- 앱 GUI를 띄워 시트 닫기·중복 `.sheet`·needs-lock 아이콘을 직접 누르지는 않았다.
- `svn revert --depth infinity`는 임시 저장소에서 실행했다. 앱 확인 알림 UI는 실행하지 않았다.
- `MainWindowActivationView`가 충돌/되돌리기 알림이 열린 동안 `statuses`를 바꾸는지 GUI로 보지 않았다.
- 분할 브라우저 내용 패널의 위아래 키가 실제 Table에서 동작하는지는 보지 않았다.
- `AuthenticationRequiredView`의 `isSubmitting`이 작업 시작 후 시트가 안 닫히는 경로에서 멈추는지는, `useCredentials`가 실패 시 false를 돌려 풀어 주므로 이번 발견에서 뺐다.
- 속성/트리 충돌 화면의 백업·하위 삭제 경고는 이전 수정 이후 코드상 남아 있어 재보고하지 않았다.
