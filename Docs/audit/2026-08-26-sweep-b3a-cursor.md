# B3a 화면 블록 전수 감사

날짜: 2026-08-26
범위: 읽기 전용. 배정 파일 15개(2921줄). GUI는 띄우지 않음.
관련 테스트 `swift test --filter` 45개 통과. 이 테스트들은 배선·문구 존재만 확인하고, 아래 발견의 실패 경로는 잡지 않는다.

## 읽은 파일
- Sources/SVNMac/AppAboutView.swift — 99줄 — 정보 창·업데이트 확인 메뉴
- Sources/SVNMac/ChangesView.swift — 484줄 — 변경 목록, 충돌·무시·삭제·잠금·파일 기록 시트 호스트
- Sources/SVNMac/CommitConfirmationView.swift — 157줄 — 빈 메시지·서버 삭제 커밋 확인
- Sources/SVNMac/CommitControlsView.swift — 79줄 — 커밋 메시지 입력과 제출 게이트
- Sources/SVNMac/CommitDeletionRestoreConfirmation.swift — 35줄 — 삭제 예정 항목 복원 공통 알림
- Sources/SVNMac/ConflictResolutionView.swift — 280줄 — 내용 충돌 선택·확인
- Sources/SVNMac/ContentView.swift — 465줄 — 사이드바, 탭, 전역 시트, 오류 presenter
- Sources/SVNMac/DeletionConfirmationView.swift — 57줄 — 저장소 삭제 예약 확인
- Sources/SVNMac/DetailedErrorView.swift — 119줄 — 오류 원문 스크롤·복사
- Sources/SVNMac/DiffTextView.swift — 32줄 — 기록 diff 색상 Text. 변경 탭은 쓰지 않음
- Sources/SVNMac/DocumentOpenConfirmation.swift — 96줄 — 잠그고 열기 / 잠금 없이 열기
- Sources/SVNMac/FileHistoryView.swift — 163줄 — 파일 커밋 기록 시트, 저장·복원
- Sources/SVNMac/HistoryRevisionDiffView.swift — 191줄 — 커밋 변경 파일 목록과 diff, 저장·복원
- Sources/SVNMac/HistoryView.swift — 432줄 — 커밋 기록 타임라인
- Sources/SVNMac/IgnoreRulesView.swift — 232줄 — svn:ignore 관리, gitignore 가져오기

경계 확인을 위해 `ProjectStore+History.swift`, `ProjectStore+FileActions.swift`, `ProjectStore+Ignore.swift`, `ProjectStore+Deletion.swift`, `ProjectStore+Locking.swift`, `ProjectStore.swift`(오류 소유자·프로젝트 전환 초기화), `RevisionFileService.swift`, `WorkingCopyBrowserView.swift`/`WorkingCopySplitBrowserView.swift` 시트 부착도 읽었다.

## 발견
### 파일 기록과 커밋 기록이 `fileHistoryRequest` 하나를 덮어쓴다
- 심각도: 중간
- 근거: `Sources/SVNMac/ProjectStore+History.swift:55-72` (`prepareHistoryRevisionActions`가 전역 `fileHistoryRequest`를 새로 씀), `Sources/SVNMac/ProjectStore+FileActions.swift:197-225` (`loadFileHistory`가 다른 UUID의 요청으로 덮어쓰고 `historyRevisionActionContext`는 그대로 둠), `Sources/SVNMac/FileHistoryView.swift:76,94`와 `HistoryRevisionDiffView.swift:41-48,176-180` (`store.fileHistoryRequest?.id == fileHistoryRequest.id`가 아니면 return), `FileHistoryView.swift:50`과 `HistoryRevisionDiffView.swift:29` (둘 다 `.historyRevisionRestoreConfirmation()`)
- 재현: 코드 기준 추정
- 트리거: 커밋 기록에서 파일을 골라 저장·복원 버튼이 보이게 한다. 변경 탭으로 가 같은 또는 다른 파일의 「파일 커밋 기록」을 열고 닫는다. 다시 커밋 기록 탭에서 그대로 남아 있는 저장·복원을 누른다. 또는 파일 기록이 열린 채 복원을 누른다(기록 상세 뷰가 TabView 안에 살아 있어 확인 대화상자가 두 개다).
- 증상: 저장·복원 클릭이 아무 일도 없다. 오류도 없다. 파일 기록 시트가 열린 상태면 복원 확인이 안 뜨거나 겹친다. 사용자는 버튼이 고장난 것으로 본다.
- 확률: 덮어쓴 xlsx/hwp를 기록에서 되돌리는 경로가 방금 커밋 기록 탭에도 붙었다. 변경 탭 우클릭 「파일 커밋 기록」과 이어 쓰면 발생한다.
- 고치는 방법: 파일 기록 요청과 커밋 기록 액션 컨텍스트를 분리한다. 시트 닫을 때 상대 쪽 요청을 건드리지 말고, 확인 대화상자는 보이는 호스트 한곳에만 둔다.

### 삭제·누락 파일에도 작업 파일 복원 버튼이 있고, 확인 뒤에야 실패한다
- 심각도: 중간
- 근거: `Sources/SVNMac/HistoryRevisionDiffView.swift:41-48,73-89` (디렉터리가 아니면 삭제 항목에도 액션을 붙임), `Sources/SVNMac/ProjectStore+History.swift:106-110,174-183` (삭제 경로는 peg `revision-1`로 복원 요청), `Sources/SVNMac/ChangesView.swift:206-209` (누락 파일도 파일 기록을 연다), `Sources/SVNMac/RevisionFileService.swift:184-197` (작업 파일이 없으면 `missingWorkingFile`)
- 재현: 실제 재현함 — `file://` 저장소에 `report.xlsx`를 커밋한 뒤 `svn delete`·커밋·update. 작업 복사본에서 파일이 사라지고 `stat`이 `FileNotFoundError`. 앱 GUI는 안 띄움. 버튼 노출은 코드 기준.
- 트리거: 커밋 기록에서 파일을 지운 리비전을 고른다. 또는 Finder로 지운 항목을 우클릭해 파일 기록을 연 뒤 「작업 파일을 이 리비전으로 복원」→ 확인.
- 증상: 확인 후에 `현재 작업 파일을 찾지 못해 복구본을 만들 수 없습니다.` 같은 오류만 보인다. 「이 버전 저장」은 된다. 다음 행동이 없다. `svn revert`로 로컬 복원하는 경로(변경 탭 「로컬 파일 복원」)와 구분이 안 된다.
- 확률: 공유 문서를 지운 뒤 기록에서 되살리려는 조작이 이 버튼의 자연스러운 쓰임이다.
- 고치는 방법: 작업 파일이 없으면 복원을 숨기거나, 없는 파일은 저장본을 작업 복사본에 추가하는 경로로 안내한다. 누락 항목은 로컬 복원(`revert`)을 먼저 제안한다.

### 프로젝트 전환 후에도 커밋 메시지 입력이 남는다
- 심각도: 중간
- 근거: `Sources/SVNMac/CommitControlsView.swift:7,13,51-57` (`@State commitMessage`. 비우는 조건은 `lastCompletedCommitMessage`뿐), `Sources/SVNMac/ContentView.swift:14,249-291` (`ChangesView()`에 `id` 없음. `selectedProjectTab`도 로컬 `@State`), `Sources/SVNMac/ProjectStore.swift:1726-1766` (`resetSelectedProjectState`는 스토어만 지움)
- 재현: 코드 기준 추정
- 트리거: 폴더 A에서 커밋 메시지를 입력한다. 사이드바에서 폴더 B를 고른다. B의 파일을 선택하고 커밋한다.
- 증상: A용 메시지가 B 커밋에 올라간다. 한글 조합 중 Return으로 제출하는 경로(`Task.yield` 뒤 `commitMessage` 읽기)도 같은 로컬 상태를 쓴다. 스토어는 프로젝트 ID를 검사하지만 메시지 문자열은 뷰가 들고 있다.
- 확률: 이 팀은 문서별로 작업 폴더를 여러 개 둔다. 메시지를 적어 두고 폴더를 바꾸는 일은 흔하다.
- 고치는 방법: `selectedProjectID`가 바뀌면 메시지와 포커스를 비운다. 또는 `ChangesView`/`CommitControlsView`에 `id: project.id`를 붙인다.

### 커밋 확인 시트와 변경 화면이 같은 복원 알림을 둘 다 붙인다
- 심각도: 중간
- 근거: `Sources/SVNMac/ChangesView.swift:78` (도구 모음 「선택 삭제 복원」용), `Sources/SVNMac/CommitConfirmationView.swift:140` (시트 안 「선택 서버 파일 복원」용), `Sources/SVNMac/CommitDeletionRestoreConfirmation.swift:11-14` (둘 다 `$store.commitDeletionRestoreRequest`)
- 재현: 코드 기준 추정. SwiftUI는 같은 `isPresented`로 부모·자식이 동시에 알림을 띄우면 한쪽이 먹거나 경고가 난다. GUI로 확인하지 않음.
- 트리거: 삭제 예정 파일을 포함해 커밋한다. 확인 시트에서 복원 대상을 체크하고 「선택한 서버 파일 복원」.
- 증상: 확인 알림이 안 뜨거나, 시트 뒤에 뜨거나, 두 번 뜬다. 복원 없이 삭제가 커밋될 수 있다.
- 확률: Finder로 지운 문서를 커밋할 때 확인 시트의 복원이 최종 방어선이다.
- 고치는 방법: 알림은 커밋 확인 시트가 열려 있으면 그 시트에만, 아니면 변경 화면에만 붙인다.

### gitignore 규칙 적용이 중간에 실패하면 일부만 남고 목록은 그대로다
- 심각도: 중간
- 근거: `Sources/SVNMac/IgnoreRulesView.swift:64-77,83-95` (`requestApplyGitIgnoreSelection` / `applySelectedGitIgnoreRules`), `Sources/SVNMac/ProjectStore+Ignore.swift:175-205` (`for proposal in proposals { try await addIgnoreRule }` — 항목별 실패를 모으지 않음. `catch`는 `errorMessage`만 설정하고 `compareGitIgnore`를 다시 부르지 않음)
- 재현: 코드 기준 추정
- 트리거: 「git 규칙 비교」 후 여러 규칙을 선택해 적용한다. 앞부분은 성공하고 이후 `propset`이 실패한다(충돌·잠긴 WC 등).
- 증상: 오류 시트만 뜬다. 선택한 항목은 여전히 「적용 가능」으로 보인다. 이미 쓰인 `svn:ignore`는 작업 복사본에 남아 커밋 대상이 된다. 사용자는 아무 것도 안 바뀐 줄 알고 넘어가거나, 같은 선택을 다시 눌러 상태를 더 섞는다.
- 확률: gitignore를 SVN으로 옮기는 일은 초기 설정에서 일어난다. 규칙이 많으면 부분 실패 여지가 있다.
- 고치는 방법: 규칙마다 성공·실패를 모으고, 실패 뒤에도 `compareGitIgnore`로 목록을 다시 만든다. 적용된 것은 「적용됨」으로 바꾼다.

### 파일 기록·이름변경·문서 열기 시트가 같은 상태에 여러 번 붙어 있다
- 심각도: 높음
- 근거: `Sources/SVNMac/ChangesView.swift:51-80`, `Sources/SVNMac/ContentView.swift:385-396` (기본 분할이면 트리·분할을 ZStack에 둘 다 둠), `Sources/SVNMac/WorkingCopyBrowserView.swift:91-109`, `Sources/SVNMac/WorkingCopySplitBrowserView.swift:66-89` (세 곳이 `isShowingFileHistory`, `versionedFileActionRequest`, `documentOpenConfirmation`을 붙임). 2026-08-25 UI 감사와 동일. 현재 코드에서 그대로다.
- 재현: 코드 기준 추정
- 트리거: 파일 탭에서 버전 파일 우클릭 「파일 커밋 기록」/이름변경/복사, 또는 xlsx·hwp 열기. 변경 탭 뷰는 TabView 안에 살아 있다.
- 증상: 시트가 안 뜨거나 잘못된 부모에서 뜬다. 잠금 확인·기록·이름변경이 없는 것처럼 보인다.
- 확률: 파일 탭 기본값이 분할이라 첫 실행부터 트리+분할이 함께 있다. 문서 열기와 파일 기록은 매일 쓴다.
- 고치는 방법: 시트와 확인창을 `ContentView`(또는 탭 컨테이너) 한곳에만 둔다. 자식의 중복 `.sheet` / `.documentOpenConfirmation()` / `.explicitLockConfirmation()`을 제거한다.

### 속성 충돌 시트가 오류 시트 소유자 목록에 없다
- 심각도: 중간
- 근거: `Sources/SVNMac/ProjectStore.swift:619-635` (`activeConflictSession`/`activeTreeConflictSession`은 있고 `recoveryState.propertyConflictSession`은 없음), `Sources/SVNMac/ChangesView.swift:47-50`, `Sources/SVNMac/ContentView.swift:236-239`, `PropertyConflictResolutionView`의 `.detailedErrorPresenter`. 2026-08-25 UI 감사와 동일. 현재 코드에서 그대로다.
- 재현: 코드 기준 추정
- 트리거: 속성 충돌 해결 중 `errorMessage`가 선다.
- 증상: `ContentView`와 속성 충돌 시트가 둘 다 오류 `.sheet`를 띄우려고 한다. 오류 상세가 안 보이거나 충돌 시트가 가려진다. 내용/트리 충돌은 목록에 있어 같은 문제가 없다.
- 확률: `svn:needs-lock` 등 속성 충돌은 내용 충돌보다 드물다. 생기면 커밋이 막힌 채 안내가 깨진다.
- 고치는 방법: `hasContextualErrorPresentationOwner`에 `propertyConflictSession != nil`을 넣는다. 커밋 확인 시트도 필요하면 같이.

### 업데이트 미리보기가 열린 채 인증·인증서 시트를 띄운다
- 심각도: 높음
- 근거: `Sources/SVNMac/ContentView.swift:216-235` (`isShowingUpdatePreview`와 `authenticationRequest`가 같은 뷰의 형제 `.sheet`). 미리보기 *시작* 가드는 `ProjectStore+Update`에 있고, *이미 열린* 뒤에는 없다. 2026-08-25 UI 감사와 동일. 현재 코드에서 그대로다.
- 재현: 코드 기준 추정
- 트리거: 「업데이트」로 미리보기를 연 다음 「업데이트 실행」. 서버 인증서가 만료됐거나 Keychain 접근이 거부된다.
- 증상: 인증/인증서 동의 시트가 안 뜬다. 미리보기만 남은 채 작업이 멈춘다.
- 확률: 사내 HTTPS + 만료/자체 서명 인증서, 또는 처음 Keychain 허용을 거절한 경우.
- 고치는 방법: 인증 요청을 세우기 전에 미리보기를 닫거나, 시트를 한 큐로 직렬화한다.

## 블록 경계
- `ChangesView` ↔ `WorkingCopyBrowserView` / `WorkingCopySplitBrowserView`: 파일 기록·문서 열기·이름변경·명시적 잠금 시트를 세 곳이 같은 `ProjectStore` 플래그에 붙인다. `ContentView`의 `FileBrowserTabView`가 트리+분할을 동시에 살려 중복을 키운다.
- `FileHistoryView` ↔ `HistoryRevisionDiffView`: `HistoryRevisionActions`와 `fileHistoryRequest`·`historyRevisionRestoreRequest`를 공유한다. `loadFileHistory`와 `prepareHistoryRevisionActions`가 서로를 깨뜨린다.
- `CommitConfirmationView` ↔ `ChangesView`: 삭제 복원 알림을 중첩 부착. 복원 성공 시 `ProjectStore+FileActions.confirmCommitDeletionRestore`가 확인 요청을 다시 만들어 시트 목록을 갱신한다. 알림이 안 뜨면 이 갱신에 도달하지 못한다.
- `IgnoreRulesView` ↔ `ProjectStore+Ignore`: 화면은 선택 ID만 넘긴다. 부분 실패·프로젝트 전환 가드는 스토어 루프에만 있다. 화면은 실패 후 목록을 다시 그릴 수단이 없다.
- `ContentView` ↔ 충돌 시트: `hasContextualErrorPresentationOwner`가 내용/트리 충돌은 막고 속성 충돌은 막지 않는다. `ChangesView`가 `PropertyConflictResolutionView`를 연다.
- `ContentView` ↔ `CommitControlsView`: 프로젝트 전환 초기화는 스토어만. 커밋 메시지·선택 탭·검색어는 뷰 `@State`.
- `ChangesView` 잠금 배지: `lockPath`가 `workingCopyBrowserTreeState.node(at:)`에 의존한다. 트리는 펼친 폴더만 캐시한다. 파일 탭을 안 거친 변경 탭에서는 `entry.path`로 떨어진다. 탐색기 쪽은 `node.matchesRepositoryPath`를 쓴다. 잠금 표시가 탭마다 갈라질 수 있다.
- `HistoryView` 변경 경로는 원문 `changedPath.path`. `HistoryRevisionDiffView`는 `HistoryPathPresentation`으로 NFC·percent-decode 한다. 같은 커밋의 한글 경로가 왼쪽 목록과 오른쪽 파일 목록에서 다르게 보일 수 있다.
- `DetailedErrorView`는 복사·닫기만 한다. 다음 화면으로 가는 버튼은 없다. 이전 막다른 길 감사와 같다. 이 블록은 presenter 호스트만 늘렸을 뿐 내용 분류는 없다.

## 검증 공백
- `RevisionRestoreViewTests`: 기록 상세에 `HistoryRevisionActions`가 있는지만 본다. `loadFileHistory` 이후 ID 불일치, 삭제된 경로 복원, 확인 대화상자 이중 부착은 없다. 넣었어야 할 입력: 커밋 기록에서 액션을 준비한 뒤 `loadFileHistory(for:)`를 호출하고 `requestHistoryRevisionRestore`가 no-op인지. 작업 파일이 없는 삭제 경로에서 복원 버튼이 보이는지.
- `CommitMessageConfirmationTests`: 확인 시트에 `.commitDeletionRestoreConfirmation()`이 있는지만 본다. `ChangesView`와의 이중 부착은 고정하지 않는다. 프로젝트 전환 후 `commitMessage` 잔존도 없다. 넣었어야 할 입력: `selectedProjectID` 변경 뒤 메시지 필드가 비는지.
- `DetailedErrorPresentationTests`: 호스트 목록에 `IgnoreRulesView`·`FileHistoryView`·`ConflictResolutionView`는 있고 `propertyConflictSession` 소유자 누락은 `contextualSheetsOwnDetailedErrorPresentation`이 add/locks 플래그만 본다.
- `ConflictResolutionViewTests`: 시트 배선과 문구. 해결 실패 후 오류 시트와 충돌 시트의 겹침은 내용 충돌만 소유자 목록으로 막힌다.
- `IgnoreRulesView`: 전용 테스트 없음. `GitIgnoreImporter` 단위 테스트는 화면의 부분 적용 실패를 안 본다. 넣었어야 할 입력: 3개 규칙 중 2번째 `propset` 실패 후 `gitIgnoreImportItems` disposition.
- `DocumentOpenConfirmationTests`: 시트 구조와 정책 키. Return이 「잠금 없이 열기」인 것은 주석상 의도라 여기서 재보고하지 않음. 중복 `.documentOpenConfirmation()` 개수는 안 센다.
- `HistoryView.filteredLogs`: 검색 테스트 없음. 이 볼륨의 `file://` 로그 XML 경로는 NFC 한글이라 `보고서` 검색은 매칭됐다. NFD 볼륨·percent-encoded 로그는 확인하지 않음.
- `DiffTextView`: 기록 diff에만 연결. 변경 탭 `store.diffContent.localizedText`는 색이 없다. 동작 버그는 아님.
- `AppAboutView`: 업데이트 문자열 테스트만. 사용자 워크플로 결함 없음.
- `DeletionConfirmationView`: Return이 취소인지만 본다. `request.projectID`와 선택 프로젝트 불일치는 스토어가 막는다.

## 확인하지 않은 것
- 앱 GUI를 띄우지 않았다. 시트·알림 겹침과 커밋 메시지 잔존은 **코드 기준 추정**이다.
- 삭제 후 작업 파일이 없는 상태는 `file://` 저장소로 **실제 재현함**. 복원 버튼이 그 항목에 붙는 것은 코드를 따른 추정이다.
- `svn log --xml` 한글 경로는 이 APFS 볼륨에서 NFC 유니코드였다. percent-encoding 로그는 안 나왔다.
- `CommitControlsView`의 한글 조합 `Task.yield`는 기존 제출 게이트 테스트가 토큰 획득만 본다. 실제 IME 조합은 확인하지 않음.
- `DiffTextView`의 `\r\n` 잔여 CR, 대형 diff 메인 스레드 부하는 재현하지 않음.
- 이미 고친 것으로 브리프가 적은 항목(삭제 커밋 Return, 커밋 중복 제출, 지역화 키, 기록 복원 진입점 자체)은 현재 코드에서 고친 상태로 보였고 다시 적지 않았다.
