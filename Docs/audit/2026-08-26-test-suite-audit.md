# 테스트 스위트 전수 감사

- 감사일: 2026-08-26
- 대상: `Tests/` 85개 파일(Swift 83, shell 2)
- 발견된 Swift Testing 테스트: `swift test list` 기준 638개
- 실행 확인: `swift test --enable-code-coverage` 638/638 통과, 66.644초
- 별도 실행: `Tests/Packaging/EmbedSVNTests.sh`, `Tests/Packaging/SVNRuntimeTests.sh` 통과
- 방법: 모든 테스트 선언과 helper를 정적 검토하고 단정, 오류 처리, 소스 읽기,
  시간·파일시스템·외부 프로세스 의존을 색인했다. mutation test와 소스 변경은 하지 않았다.

## 높음

- `Tests/SVNCoreTests/SVNVolumeNormalizationProbeTests.swift:64` — **높음** —
  `hdiutil` 부재뿐 아니라 이미지 생성 또는 attach 실패도 `return`으로 끝나 성공 처리된다.
  - 왜: CI 권한, 디스크 공간, sandbox 문제로 핵심 HFS+ 분기가 한 번도 실행되지 않아도
    녹색이다. 외부 조건 미충족은 명시적 skip 사유로 기록하고, 명령 실패는 실패시켜야 한다.

- `Tests/SVNMacTests/ConflictResolutionViewTests.swift:5` — **높음** —
  충돌 해결 화면 11개 테스트가 렌더링·입력·callback 대신 Swift 소스 문자열만 검사한다.
  - 왜: 버튼 문자열과 함수명이 남은 채 action, disabled 조건, 전달 인자가 잘못돼도 통과한다.
    되돌림 검출 여부는 mutation을 하지 않아 **확인 필요**다. 선택 결과는 상태/서비스 테스트로,
    키보드·role은 UI 이벤트 또는 구조 검사로 분리해야 한다.

- `Tests/SVNMacTests/DestructiveReturnKeyTests.swift:7` — **높음** —
  파괴적 확인 6개가 `.keyboardShortcut`과 `role` 표기만 검사한다.
  - 왜: 실제 Return/Escape 이벤트가 어느 버튼을 실행하는지 검증하지 않는다. modifier 위치 변경,
    중복 default action, 상위 뷰 override는 놓친다. 실제 키 이벤트 검사는 없음을 확인했다.

- `Tests/SVNMacTests/CommitSubmissionGateTests.swift:45` — **높음** —
  UI가 submission token을 async 경계 전에 잡는지는 함수 일부의 문자열 순서로만 검사한다.
  - 왜: 같은 문자열을 유지한 다른 실행 경로나 조기 return이 생기면 통과할 수 있다. 상태 모델
    3개 테스트는 gate 자체만 검증한다. UI 연속 제출 동작은 **확인 필요**다.

- `Tests/SVNMacTests/RevisionRestoreViewTests.swift:5` — **높음** —
  저장·복원 UI 배선 4개가 소스에 호출명과 보안 scope 문자열이 있는지만 검사한다.
  - 왜: 버튼이 비활성화되거나 다른 request를 넘기거나 scope 호출 순서가 깨져도 문자열은 남을 수
    있다. 서비스 동작 테스트는 있으나 화면에서 서비스까지의 실제 경로는 검증하지 않는다.

## 중간

- `Tests/SVNMacTests/ChangesViewPerformanceTests.swift:6` — **중간** —
  9개 전부 production source `contains`/부재 검사다.
  - 왜: commit 상태 소유권, 임시 파일 노출, 충돌 선택 같은 동작과
    `statuses +` 금지, attributed view 개수 같은 구조 규칙이 한 suite에 섞였다. 전자는 모델/렌더링
    검사로 바꿀 수 있다. 후자는 성능 회귀 기준이므로 benchmark나 전용 정적 규칙으로 남길 이유가 있다.

- `Tests/SVNMacTests/AppReviewReadinessTests.swift:31` — **중간** —
  패키징 테스트가 스크립트·앱 소스의 명령 문자열 존재만 보고 실제 bundle 결과를 열지 않는다.
  - 왜: 명령이 실행 불가능하거나 다른 분기에서 건너뛰어도 통과한다. bundle identifier 같은 plist
    정적 계약은 남길 수 있지만 resource 배치는 패키징 산출물 검사로 바꿀 수 있다.

- `Tests/SVNMacTests/AppContactSupportTests.swift:26` — **중간** —
  Help 메뉴 배선은 `SVNMacApp.swift` 문자열 3개만 검사한다.
  - 왜: 메뉴 action이 실행되는지 확인하지 않는다. email/message 순수 함수 테스트는 별도로 있어
    유효하지만 menu-to-action 경계는 **확인 필요**다.

- `Tests/SVNMacTests/AppUpdateCheckerTests.swift:30` — **중간** —
  About 창과 수동 업데이트 명령 연결은 소스 문자열 검사다.
  - 왜: version 비교와 lookup URL 동작은 직접 검사하지만 command action 실행은 검사하지 않는다.

- `Tests/SVNMacTests/BrowserStateRegressionTests.swift:44` — **중간** —
  refresh/lock/search 회귀 하나가 세 파일의 함수명·`defer` 문자열을 검사한다.
  - 왜: 상태 모델이 실제로 정착하는지 확인하지 않는다. repository browser 앞의 2개 상태 테스트와
    달리 리팩터링에는 깨지고 동일 표기를 둔 동작 회귀에는 통과한다.

- `Tests/SVNMacTests/BulkUnlockPresentationRegressionTests.swift:5` — **중간** —
  bulk unlock alert의 오류 노출 방지는 소스에서 `localizedDescription` 부재를 검사한다.
  - 왜: 다른 debug 문자열 노출이나 formatter 회귀는 놓친다. `failureRows` 값 테스트는 별도로 유효하다.

- `Tests/SVNMacTests/ButtonAffordanceTests.swift:4` — **중간** —
  앱 전체 button style 정책을 production source grep으로 강제한다.
  - 왜: 실제 affordance는 렌더링하지 않는다. 다만 전역 금지 정책 자체는 동작 단위 테스트보다
    정적 lint로 남길 이유가 있다. 현재 형태는 주석·dead code도 오탐한다.

- `Tests/SVNMacTests/ChangesDiffPresentationTests.swift:4` — **중간** —
  diff view 공유 여부를 type/function 이름 문자열로만 검사한다.
  - 왜: 실제 line highlighting과 대용량 렌더링 결과는 검사하지 않는다. 구조 정책이면 정적 규칙,
    표시 계약이면 `AttributedString` 생성 로직 테스트가 맞다.

- `Tests/SVNMacTests/ChangesToolbarGuardTests.swift:4` — **중간** —
  needs-lock menu guard가 소스 문자열 4개로만 고정된다.
  - 왜: guard 값이 잘못 계산되거나 action이 다른 project를 사용해도 표기가 남으면 통과한다.

- `Tests/SVNMacTests/CommitMessageConfirmationTests.swift:26` — **중간** —
  6개 중 화면 동작 3개가 소스 일부와 문자열 존재를 검사한다.
  - 왜: 삭제 목록 선택·복원 callback과 empty-message 제출을 실제로 실행하지 않는다. 순수
    `serverDeletionEntries` 테스트는 유효하고 localization resource 계약은 정적으로 남길 수 있다.

- `Tests/SVNMacTests/CommitMessageDraftRegressionTests.swift:5` — **중간** —
  UI의 프로젝트별 draft 배선은 source grep이다.
  - 왜: `CommitMessageDrafts` 자체는 다음 테스트가 직접 검증하지만 project 전환 시 TextField 값과
    제출 대상이 맞는지는 확인하지 않는다.

- `Tests/SVNMacTests/ConcurrencyRepositoryBrowserTests.swift:31` — **중간** —
  dismiss 시 cancel 배선은 source grep이다.
  - 왜: 앞 테스트는 state cancellation을 직접 확인하지만 실제 sheet dismiss가 그 함수를 호출하는지는
    실행하지 않는다. view inspection/UI 이벤트로 바꿀 수 있다.

- `Tests/SVNMacTests/DetailedErrorPresentationTests.swift:14` — **중간** —
  5개 중 4개가 presenter, ScrollView, recovery action 표기만 검사한다.
  - 왜: copy 순수 함수 1개 외에는 실제 error 표시·copy·recovery action을 실행하지 않는다.

- `Tests/SVNMacTests/DocumentOpenConfirmationTests.swift:5` — **중간** —
  prompt와 settings 화면 테스트 2개가 source grep이다.
  - 왜: 세 policy의 저장·분기 동작 테스트는 다른 파일에 있지만 화면 선택과 callback 연결은
    검증하지 않는다. localization key 존재 검사는 정적 계약으로 남길 수 있다.

- `Tests/SVNMacTests/FileBrowserViewModeTests.swift:21` — **중간** —
  5개 중 view 배선·중복 column key 3개가 source text를 검사한다.
  - 왜: 저장값 복원은 직접 검증하지만 double-click, chevron hit area, view 전환은 실행하지 않는다.
    column key 유일성은 AST/lint 규칙으로 남길 이유가 있다.

- `Tests/SVNMacTests/PresentationOwnershipRegressionTests.swift:5` — **중간** —
  세 테스트가 `Sources/SVNMac` 전체 또는 일부의 presentation 문자열 개수만 센다.
  - 왜: 단일 owner 정책은 정적 검사 가치가 있으나, item 수명주기와 중복 presenter 동작은
    확인하지 않는다. 주석·dead code에도 개수가 변한다.

- `Tests/SVNMacTests/ProjectHeaderActionsTests.swift:4` — **중간** —
  header/sidebar/toolbar 8개가 모두 source 순서·문구 검사다.
  - 왜: action의 project 캡처, disabled 상태, 실제 호출은 검사하지 않는다. toolbar 배치 정책은
    snapshot/정적 검사로 남길 수 있고 action 결과는 상태 테스트로 바꿀 수 있다.

- `Tests/SVNMacTests/ProjectRecoveryNormalizationTests.swift:6` — **중간** —
  recovery 등록 경로가 함수를 부르는지는 source grep이다.
  - 왜: 다음 테스트는 `registerRecoveredCheckout` 직접 호출만 검증한다. 실제 recovery 완료에서 해당
    함수가 실행되는지는 **확인 필요**다.

- `Tests/SVNMacTests/RepositoryMaintenanceTests.swift:107` — **중간** —
  relocation 진입 위치와 화면 문구 2개 테스트가 여러 view의 source text를 검사한다.
  - 왜: 실제 Settings action과 relocation request 경계는 실행하지 않는다. real SVN 동작 테스트 1개는
    별도로 유효하다.

- `Tests/SVNMacTests/UpdatePreviewStateTests.swift:134` — **중간** —
  11개 중 view/client 배선 3개가 source grep이다.
  - 왜: state 7개와 localization 계약은 직접 검사하지만 update/cleanup button이 올바른 client 호출을
    만드는지는 확인하지 않는다.

- `Tests/SVNMacTests/ProjectStoreTests.swift:515` — **중간** —
  10개 race 테스트가 10~20ms sleep 뒤 project/state를 바꾼다(`:579`, `:635`, `:1425`,
  `:1673`, `:2153`, `:2272`, `:2309`, `:2537`, `:2780`에도 같은 구조).
  - 왜: 느린 CI에서 첫 task가 아직 시작하지 않았거나 빠른 환경에서 이미 끝나면 의도한 순서를
    만들지 못한다. 일부는 `AsyncTestGate`를 이미 쓰므로 전부 명시적 gate로 바꿀 수 있다.

- `Tests/SVNCoreTests/SVNCredentialsTests.swift:218` — **중간** — 단정 API가 없는 유일한 Swift 테스트다.
  - 왜: 두 task의 성공 완료가 actor 재진입을 간접 검증하므로 껍데기로 확정할 수는 없다. 하지만
    `validationFinished.wait()`에 timeout이 없어 직렬화 회귀 시 실패가 아니라 무한 대기가 된다.

- `Tests/SVNCoreTests/SVNCredentialsTests.swift:169` — **중간** — 외부 프로세스 stream/cancel 테스트가
  15~30초 wall-clock polling과 20ms sleep에 의존한다(`:207`, `:348`).
  - 왜: deadline은 있으나 scheduler 부하에 따라 느리게 실패한다. event/continuation 기반 시작 신호가
    더 결정적이다. 현재 실행에서는 통과했다.

- `Tests/SVNCoreTests/SVNArgumentRulesIntegrationTests.swift:6` — **중간** — real SVN integration이
  설치된 `svn`/`svnadmin`과 로컬 `file://` 저장소·파일시스템 동작에 의존한다.
  - 왜: 바이너리 부재는 `#require`로 실패해 조용히 통과하지는 않는다. 다만 버전·locale·권한 차이가
    suite 결과를 바꾼다. 같은 의존은 `SVNCanonicalAliasIntegrationTests.swift:6`,
    `SVNCoreCommandsIntegrationTests.swift:5`, `SVNRepositoryCleanupDeletionIntegrationTests.swift:6`,
    `SVNRepositoryPathNormalizationIntegrationTests.swift:6`, `SVNStateRecoveryIntegrationTests.swift:5`,
    `SVNSwitchedStatusIntegrationTests.swift:5`, `SVNTreeConflictMetadataIntegrationTests.swift:5`,
    `SVNUnicodeCommitIntegrationTests.swift:6`, `SVNWorkingCopyRecoveryIntegrationTests.swift:7`,
    `SVNWorkingCopySnapshotPropertyIntegrationTests.swift:79`, `SVNRepositoryListTests.swift:44`,
    `SVNLogMessagePathnameTests.swift:7`에 있다.

- `Tests/SVNMacTests/ConflictArtifactCommitSelectionTests.swift:78` — **중간** — app integration도
  시스템 `svn`/`svnadmin`에 의존한다.
  - 왜: 같은 의존은 `ConflictDataLossRegressionTests.swift:13`,
    `ConflictResolutionIntegrationTests.swift:6`, `FolderRevertDataLossTests.swift:10`,
    `MissingCommitSelectionTests.swift:59`, `MixedRevisionUpdateIntegrationTests.swift:7`,
    `RepositoryMaintenanceTests.swift:29`, `RevisionRestoreTests.swift:7`,
    `ProjectStoreTests.swift:5006`에 있다. 모두 부재 시 `#require` 실패이며 silent skip은 아니다.

## 낮음

- `Tests/SVNMacTests/LocalizationCoverageTests.swift:5` — **낮음** — 전체 catalog key 동등성 검사와
  기능별 resource key 존재 검사가 중복된다.
  - 왜: `CommitMessageConfirmationTests.swift:99`, `ConflictResolutionViewTests.swift:135`,
    `DocumentOpenConfirmationTests.swift:34`, `RevisionRestoreViewTests.swift:77`,
    `UpdatePreviewStateTests.swift:205`, `WorkingCopyRecoveryTests.swift:5`가 같은 세 resource를 다시 읽는다.
    전체 key-set 검사 + 필요한 번역값 의미 검사만 남기면 반복 I/O와 유지비를 줄일 수 있다.

- `Tests/SVNMacTests/FileHistoryTimeZoneTests.swift:24` — **낮음** — timezone 주입 배선 1개는 source grep이다.
  - 왜: formatter 결과 테스트는 직접 동작 검사라 유효하다. view wiring은 snapshot/UI inspection이 더 강하다.

- `Tests/SVNMacTests/FolderRevertDataLossTests.swift:69` — **낮음** — 확인창의 path limit 배선만 source grep이다.
  - 왜: 실제 subtree 보존 integration은 같은 파일의 앞 2개가 검증한다. 이 항목은 구조 정책으로만 남는다.

- `Tests/SVNMacTests/HistoryRequestOwnershipRegressionTests.swift:5` — **낮음** — history action route는
  함수명 부재·존재만 검사한다.
  - 왜: request ownership 상태 변화는 실행하지 않는다. focused state test로 대체 가능하다.

- `Tests/SVNMacTests/MainWindowActivationTests.swift:34` — **낮음** — ContentView activation 배선은 source grep이다.
  - 왜: monitor 자체 테스트는 직접 동작 검사다. view-to-refresh 연결만 **확인 필요**로 남는다.

- `Tests/SVNMacTests/RepositoryBrowserTests.swift:30` — **낮음** — Add sheet의 browser 배선 1개는 source grep이다.
  - 왜: browser state 7개는 직접 동작 검사다. 화면 action만 UI inspection으로 옮길 수 있다.

- `Tests/SVNMacTests/ToolbarSearchTests.swift:4` — **낮음** — search owner는 세 source의 `.searchable` 개수로 판정한다.
  - 왜: 단일 owner라는 구조 정책은 남길 이유가 있으나 검색 결과·focus 동작은 검증하지 않는다.

- `Tests/SVNMacTests/TreeConflictPresentationTests.swift:42` — **낮음** — view가 presentation helper를
  호출하는지는 source grep이다.
  - 왜: helper 문구 2개는 직접 검증한다. view 렌더링은 확인하지 않는다.

- `Tests/SVNMacTests/WorkingCopyRecoveryTests.swift:53` — **낮음** — recovery action과 username gate 부재는
  세 view source를 검사한다.
  - 왜: 폴더 비우기 안전성은 직접 검증하지만 recovery UI action은 실행하지 않는다.

## 껍데기·되돌림 판단 요약

- `Tests/SVNCoreTests/SVNCredentialsTests.swift:218` — `#expect`/`#require`/`Issue.record`가 없는 테스트는
  638개 중 1개였다. 성공 완료가 의미 있는 조건이라 무조건 껍데기로 세지 않았다.
- `Tests/SVNCoreTests/SVNVolumeNormalizationProbeTests.swift:64` — 조용히 성공 가능한 테스트는 1개였다.
  `try?`는 그 외 cleanup, sleep, helper의 optional read에만 쓰였고 SUT 오류를 삼키는 사례는 찾지 못했다.
- `Tests/SVNCoreTests/GitIgnoreParserTests.swift:3` — `#expect(true)`, `XCTAssertTrue(true)`, 자기 자신과의
  동등 비교는 전체 검색에서 0개였다.
- `Tests/SVNMacTests/AppContactSupportTests.swift:26` — production Swift source를 읽는 테스트는 수작업으로
  함수 경계를 확인해 32개 파일, 85개로 셌다. 이 85개는 해당 표기가 바뀌면 실패하지만 실제 동작을
  되돌렸을 때 실패하는지는 보장하지 않는다. mutation을 하지 않았으므로 개별 되돌림 결과는 모두
  **확인 필요**다.

## 소스 문자열 검사 분류

`동작 전환`은 상태/서비스/UI event 검사로 바꿀 수 있다는 뜻이다. `정적 유지`는 동작보다 금지 표기,
소유권, 배치 같은 코드 정책이 목적이라 AST/lint/snapshot 형태로 남길 이유가 있다는 뜻이다.

| 파일:줄 | source-code 검사 수 | 판정 |
|---|---:|---|
| `Tests/SVNMacTests/AppContactSupportTests.swift:26` | 1 | 동작 전환 |
| `Tests/SVNMacTests/AppReviewReadinessTests.swift:31` | 7 | packaging은 산출물 검사, 배치·credit은 정적 유지 가능 |
| `Tests/SVNMacTests/AppUpdateCheckerTests.swift:30` | 1 | 동작 전환 |
| `Tests/SVNMacTests/BrowserStateRegressionTests.swift:44` | 1 | 동작 전환 |
| `Tests/SVNMacTests/BulkUnlockPresentationRegressionTests.swift:5` | 1 | 동작 전환 |
| `Tests/SVNMacTests/ButtonAffordanceTests.swift:4` | 2 | 정적 유지, lint 권장 |
| `Tests/SVNMacTests/ChangesDiffPresentationTests.swift:4` | 1 | 혼합 |
| `Tests/SVNMacTests/ChangesToolbarGuardTests.swift:4` | 1 | 동작 전환 |
| `Tests/SVNMacTests/ChangesViewPerformanceTests.swift:6` | 9 | 혼합 |
| `Tests/SVNMacTests/CommitMessageConfirmationTests.swift:26` | 3 | 동작 전환 |
| `Tests/SVNMacTests/CommitMessageDraftRegressionTests.swift:5` | 1 | 동작 전환 |
| `Tests/SVNMacTests/CommitSubmissionGateTests.swift:45` | 1 | 동작 전환 |
| `Tests/SVNMacTests/ConcurrencyRepositoryBrowserTests.swift:31` | 1 | 동작 전환 |
| `Tests/SVNMacTests/ConflictResolutionViewTests.swift:5` | 11 | 동작 전환, role 정책 일부 정적 유지 |
| `Tests/SVNMacTests/DestructiveReturnKeyTests.swift:7` | 6 | UI event 전환, 금지 정책은 정적 유지 |
| `Tests/SVNMacTests/DetailedErrorPresentationTests.swift:14` | 4 | 동작 전환 |
| `Tests/SVNMacTests/DocumentOpenConfirmationTests.swift:5` | 2 | 동작 전환 |
| `Tests/SVNMacTests/FileBrowserViewModeTests.swift:21` | 3 | 혼합 |
| `Tests/SVNMacTests/FileHistoryTimeZoneTests.swift:24` | 1 | 동작 전환 |
| `Tests/SVNMacTests/FolderRevertDataLossTests.swift:69` | 1 | 정적 유지 가능 |
| `Tests/SVNMacTests/HistoryRequestOwnershipRegressionTests.swift:5` | 1 | 동작 전환 |
| `Tests/SVNMacTests/MainWindowActivationTests.swift:34` | 1 | 동작 전환 |
| `Tests/SVNMacTests/PresentationOwnershipRegressionTests.swift:5` | 3 | 정적 유지, AST 권장 |
| `Tests/SVNMacTests/ProjectHeaderActionsTests.swift:4` | 8 | 혼합 |
| `Tests/SVNMacTests/ProjectRecoveryNormalizationTests.swift:6` | 1 | 동작 전환 |
| `Tests/SVNMacTests/RepositoryBrowserTests.swift:30` | 1 | 동작 전환 |
| `Tests/SVNMacTests/RepositoryMaintenanceTests.swift:107` | 2 | 혼합 |
| `Tests/SVNMacTests/RevisionRestoreViewTests.swift:5` | 4 | 동작 전환 |
| `Tests/SVNMacTests/ToolbarSearchTests.swift:4` | 1 | 정적 유지, AST 권장 |
| `Tests/SVNMacTests/TreeConflictPresentationTests.swift:42` | 1 | 동작 전환 |
| `Tests/SVNMacTests/UpdatePreviewStateTests.swift:134` | 3 | 동작 전환 |
| `Tests/SVNMacTests/WorkingCopyRecoveryTests.swift:53` | 1 | 동작 전환 |
| **합계** | **85** | |

## 비결정성·외부 조건 요약

- `Tests/SVNMacTests/ProjectStoreTests.swift:515` — 실제 시각을 읽는 테스트는 없었다. 고정 epoch를 쓰는
  Date fixture만 확인했다. 문제는 wall-clock sleep으로 순서를 추정하는 8개 race 테스트다.
- `Tests/SVNCoreTests/SVNArgumentRulesIntegrationTests.swift:6` — real SVN 계열은 설치된 바이너리가 없으면
  `#require`에서 실패한다. CI가 녹색인데 이 계열이 조용히 빠지는 구조는 아니다.
- `Tests/SVNCoreTests/SVNVolumeNormalizationProbeTests.swift:67` — 외부 바이너리/환경 문제를 조용히
  통과시키는 것은 HFS+ probe 1개뿐이다. create/attach 실패까지 같은 방식으로 빠진다.
- `Tests/SVNMacTests/AppUpdateCheckerTests.swift:15` — production update service는 network 기능이 있지만
  테스트는 URL 조립만 하며 실제 network 요청은 하지 않는다. network 비결정성은 현재 suite에서 찾지 못했다.
- `Tests/SVNMacTests/FileBrowserViewModeTests.swift:7` — UserDefaults는 UUID suite, 파일 fixture는 UUID 임시
  디렉터리를 사용한다. 공유 실행 순서에 의존하는 고정 suite/path는 찾지 못했다.

## 커버리지 공백

아래 수치는 이번 `swift test --enable-code-coverage`의 line coverage다. source grep은 production 코드를
실행하지 않으므로 0% 파일을 녹색으로 만들 수 있다. SwiftUI compiler-generated line 집계 특성상 UI 품질의
절대 지표로 쓰지 않고, 큰 공백을 찾는 근거로만 사용했다.

- `Sources/SVNMac/ContentView.swift:1` — **중간** — 1,199 measured lines 중 0 실행.
  - 왜: sidebar, toolbar, sheet, project 전환의 대부분이 source grep뿐이다.
- `Sources/SVNMac/RepositoryDialogs.swift:1` — **중간** — 2,307 measured lines 중 0 실행.
  - 왜: 등록·자격·설정 화면의 실제 입력과 저장 흐름이 없다.
- `Sources/SVNMac/WorkingCopySplitBrowserView.swift:1` — **중간** — 1,342 measured lines 중 0 실행.
  - 왜: state 테스트는 강하지만 key handler와 context action 배선은 실행되지 않는다.
- `Sources/SVNMac/RepositoryPathNormalizationView.swift:1` — **중간** — 935 measured lines 중 0 실행.
  - 왜: presentation/state 테스트와 실제 sheet interaction 사이 공백이다.
- `Sources/SVNMac/HistoryView.swift:1` — **중간** — 779 measured lines 중 0 실행.
  - 왜: history state/service는 덮지만 검색·선택·toolbar UI 경로는 없다.
- `Sources/SVNMac/ConflictResolutionView.swift:1` — **중간** — 607 measured lines 중 0 실행.
  - 왜: 11개 source grep이 runtime coverage를 만들지 못한다.
- `Sources/SVNMac/IgnoreRulesView.swift:1` — **중간** — 606 measured lines 중 0 실행.
  - 왜: importer/store 테스트는 있으나 rule 선택·경고·적용 UI는 없다.
- `Sources/SVNMac/UpdatePreviewView.swift:1` — **중간** — 646 measured lines 중 0 실행.
  - 왜: state는 100%지만 view는 source grep과 localization 검사뿐이다.
- `Sources/SVNMac/OptionalPresentationBinding.swift:3` — **낮음** — 12 measured lines 중 0 실행.
  - 왜: optional item 표시/해제 binding의 get/set 계약 테스트가 없다.
- `Sources/SVNMac/DiffTextView.swift:1` — **낮음** — 31 measured lines 중 0 실행.
  - 왜: 추가·삭제·header highlighting과 newline 보존 테스트가 없다.
- `Sources/SVNMac/ActionProgressLabel.swift:8` — **낮음** — 19 measured lines 중 0 실행.
  - 왜: 여러 source grep이 type 이름만 확인하며 label/progress 표시를 실행하지 않는다.
- `Sources/SVNMac/KeychainStore.swift:37` — **낮음** — 파일 전체 coverage는 47.78%이며
  password read의 success, not-found, access-denied, non-UTF-8 data 입력이 없다.
  - 왜: 현재 3개 테스트는 update/add/delete만 검사한다. read 오류와 `nil` decoding 결과의 계약은 비어 있다.
- `Sources/SVNMac/TemporaryFileClassification.swift:126` — **낮음** — 파일 전체 coverage는 89.25%지만
  `.Trashes` 같은 name-only directory cleanup 판정 입력이 없다.
  - 왜: regular-file 검증을 건너뛰는 후보의 directory 동작은 확인하지 못했다.

## 638개 중 실질 검증 추정

**약 560~570개**를 실질 검증으로 본다.

- 확인한 기준값: production Swift source를 읽지 않는 테스트 553개(`638 - 85`).
- 553개에는 상태·파서·파일 바이트·fake executable·real SVN 결과·정적 resource/manifest 계약이 포함된다.
- source-code 검사 85개 중 약 15개는 단일 owner, 금지 button style, keyboard default 금지,
  대규모 diff 구조 같은 정적 정책으로서 가치가 있다. 나머지는 동작 검증으로 세지 않았다.
- feature별 localization key 검사는 전체 catalog 검사와 중복되고, HFS+ 1개는 조건에 따라 silent pass한다.
  race sleep 테스트는 이번에는 통과했지만 결정적이지 않아 범위 하단에 반영했다.
- 개별 mutation을 실행하지 않았으므로 이 수치는 line coverage나 pass 수가 아니라 구조 기반 추정이다.

## 감사 파일 전수 목록

`문제 있음`은 이 보고서의 취약성·비결정성·중복 항목에 걸린다는 뜻이다. 해당 파일의 모든 테스트가
무의미하다는 뜻은 아니다.

| 파일:줄 | 판정 |
|---|---|
| `Tests/Packaging/EmbedSVNTests.sh:1` | 문제 없음 |
| `Tests/Packaging/SVNRuntimeTests.sh:1` | 문제 없음 |
| `Tests/SVNCoreTests/GitIgnoreImporterTests.swift:1` | 문제 없음 |
| `Tests/SVNCoreTests/GitIgnoreParserTests.swift:1` | 문제 없음 |
| `Tests/SVNCoreTests/SVNApplicationSupportTests.swift:1` | 문제 없음 |
| `Tests/SVNCoreTests/SVNArgumentRulesIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNCanonicalAliasIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNClientSerializationContractTests.swift:1` | 문제 없음 |
| `Tests/SVNCoreTests/SVNCoreCommandsIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNCredentialsTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNErrorClassificationTests.swift:1` | 문제 없음 |
| `Tests/SVNCoreTests/SVNFileSystemTests.swift:1` | 문제 없음 |
| `Tests/SVNCoreTests/SVNLogMessagePathnameTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNPathNormalizationTests.swift:1` | 문제 없음 |
| `Tests/SVNCoreTests/SVNRepositoryCleanupDeletionIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNRepositoryListTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNRepositoryPathNormalizationIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNRepositoryPathNormalizationTests.swift:1` | 문제 없음 |
| `Tests/SVNCoreTests/SVNStateRecoveryIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNSwitchedStatusIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNTreeConflictMetadataIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNUnicodeCommitIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNVolumeNormalizationProbeTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNWorkingCopyRecoveryIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNWorkingCopyRecoveryPreviewTests.swift:1` | 문제 없음 |
| `Tests/SVNCoreTests/SVNWorkingCopyRecoveryTests.swift:1` | 문제 없음 |
| `Tests/SVNCoreTests/SVNWorkingCopySnapshotPropertyIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNCoreTests/SVNWorkingCopySnapshotTests.swift:1` | 문제 없음 |
| `Tests/SVNCoreTests/SVNXMLParserTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/AppContactSupportTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/AppLayoutTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/AppReviewReadinessTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/AppSettingsTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/AppUpdateCheckerTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/BrowserStateRegressionTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/BulkUnlockPresentationRegressionTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ButtonAffordanceTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ChangesDiffPresentationTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ChangesToolbarGuardTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ChangesViewPerformanceTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/CommitConfirmationLayoutTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/CommitMessageConfirmationTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/CommitMessageDraftRegressionTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/CommitSubmissionGateTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ConcurrencyRepositoryBrowserTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ConflictArtifactCommitSelectionTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ConflictDataLossRegressionTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ConflictFileServiceTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/ConflictResolutionIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ConflictResolutionViewTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/DestructiveReturnKeyTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/DetailedErrorPresentationTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/DocumentOpenConfirmationTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/FileBrowserViewModeTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/FileHistoryTimeZoneTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/FolderRevertDataLossTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/HistoryPathPresentationTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/HistoryRequestOwnershipRegressionTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/KeychainStoreTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/LocalizationCoverageTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/LockWorkflowTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/MainWindowActivationTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/MissingCommitSelectionTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/MixedRevisionUpdateIntegrationTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/PresentationOwnershipRegressionTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ProjectHeaderActionsTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ProjectRecoveryNormalizationTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ProjectStoreTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/PropertyConflictResolutionTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/RecoveryDestinationSafetyTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/RecoveryProjectCertificateTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/RepositoryBrowserTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/RepositoryMaintenanceTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/RepositoryPathNormalizationPresentationTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/RevisionRestoreTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/RevisionRestoreViewTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/ServerCertificateTrustTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/StatusWorkflowTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/ToolbarSearchTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/TreeConflictPresentationTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/UpdatePreviewStateTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/WorkingCopyBrowserModelTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/WorkingCopyFileServiceTests.swift:1` | 문제 없음 |
| `Tests/SVNMacTests/WorkingCopyRecoveryTests.swift:1` | 문제 있음 |
| `Tests/SVNMacTests/WorkingCopySplitBrowserStateTests.swift:1` | 문제 없음 |
