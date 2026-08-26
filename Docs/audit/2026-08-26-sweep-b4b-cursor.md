# B4b 전수 감사

날짜: 2026-08-26  
범위: 배정 29파일 4058줄. 소스 수정 없음. 이전 감사에서 이미 고친 항목(강제 로그, peg, 텍스트+속성 백업, Return 파괴, 프로젝트 전환 초기화, 지역화 키 타입, conflict XML 마지막 요소, 브라우저 캐시 무효화)은 다시 적지 않는다. 고치지 않고 남아 있는 중복은 그대로 적는다.

재현: 임시 `file://` 저장소 `/tmp/svnmac-b4b-repro-53640`. svn 1.x, APFS.

## 읽은 파일
- Sources/SVNMac/ActionProgressLabel.swift — 24줄 — 진행 중 버튼 라벨(스피너+문구)
- Sources/SVNMac/AppContactSupport.swift — 26줄 — 지원 메일 주소·알림 문구
- Sources/SVNMac/AppLayout.swift — 141줄 — 창/시트/분할 크기 계약, WorkspaceSplitView
- Sources/SVNMac/AppSettings.swift — 216줄 — UserDefaults 키, 언어·시간대·임시파일·문서잠금 정책, 설정 화면
- Sources/SVNMac/AppUpdateChecker.swift — 180줄 — App Store lookup, 자동/수동 업데이트 확인
- Sources/SVNMac/ConflictFileService.swift — 484줄 — 충돌 비교본·작업파일·하위트리 백업과 경로 안전 검사
- Sources/SVNMac/HistoryDateFormatting.swift — 31줄 — 커밋 시각 포맷 캐시
- Sources/SVNMac/HistoryPathPresentation.swift — 40줄 — 저장소 경로를 WC 기준 짧은 표기로, NFC 표시
- Sources/SVNMac/KeychainStore.swift — 130줄 — 프로젝트 UUID 계정 키로 비밀번호 저장
- Sources/SVNMac/LockWorkflow.swift — 152줄 — 명시 잠금 계획, 일괄 해제 실행·부분 실패
- Sources/SVNMac/OptionalPresentationBinding.swift — 12줄 — Optional 시트를 Bool 바인딩으로 닫기
- Sources/SVNMac/OutOfDateCommitRecovery.swift — 29줄 — 구버전 커밋 복구 요청 모델(projectID 포함)
- Sources/SVNMac/ProjectStatusBadges.swift — 41줄 — 사이드바 충돌/변경/잠금/업데이트 뱃지
- Sources/SVNMac/ProjectStatusSummary.swift — 15줄 — 뱃지 수치 + RevertRequest(projectID 있음)
- Sources/SVNMac/PropertyConflictResolution.swift — 124줄 — 속성 충돌 세션, 해결 검증, .prej 이름 파싱
- Sources/SVNMac/RepositoryBrowserState.swift — 297줄 — 저장소 URL 탐색, 목록 로드, 실패 분류
- Sources/SVNMac/RepositoryPathNormalizationPresentation.swift — 103줄 — NFC/NFD 성분 차이 표시
- Sources/SVNMac/RevisionFileService.swift — 208줄 — 과거 리비전 저장·작업파일 복원과 바이트 검증
- Sources/SVNMac/SVNErrorLocalization.swift — 191줄 — SVNError/ConflictFileError 사용자 문구, 인증서 실패 분류
- Sources/SVNMac/SVNMacApp.swift — 119줄 — 라이브/데모 스토어, 업데이트·지원 알림, 설정/정보 창
- Sources/SVNMac/ServerCertificateTrust.swift — 15줄 — 인증서 실패 집합, other면 허용 불가
- Sources/SVNMac/StatusBadge.swift — 85줄 — 상태 색, 되돌리기/incomplete/obstructed/switched 정책
- Sources/SVNMac/TemporaryFileClassification.swift — 214줄 — 임시파일 숨김·커밋 선택·저장소 정리 검증
- Sources/SVNMac/TreeConflictResolution.swift — 125줄 — 트리 충돌 선택지, 하위 삭제 영향 스캔
- Sources/SVNMac/UpdatePreviewState.swift — 51줄 — 수신 커밋 미리보기, 실패해도 업데이트 허용
- Sources/SVNMac/WorkingCopyBrowserModel.swift — 430줄 — 트리 펼침/키보드/검색 필터, 날짜·크기 표시
- Sources/SVNMac/WorkingCopyFileService.swift — 232줄 — 디스크 트리/직계 자식 읽기, SVN 항목 바이트 키 조회
- Sources/SVNMac/WorkingCopyRecoveryDialogs.swift — 131줄 — cleanup 시트, 취소된 체크아웃 재개/폴더 비우기
- Sources/SVNMac/WorkingCopySplitBrowserState.swift — 212줄 — 분할 보기 폴더/내용 캐시와 키보드 이동

이전 감사 10건 중 이 파일과 겹치는 보고: dead-end(커서/클로드), audit-ui, audit-state, audit-destructive, audit-concurrency, argv-audit 일부.

## 발견
### 속성 전용 충돌이 사이드바 빨간 뱃지에 안 잡힌다
- 심각도: 중간
- 근거: `Sources/SVNMac/ProjectStatusSummary.swift:6`, `Sources/SVNMac/ProjectStatusBadges.swift:20-22`, `Sources/SVNMac/ProjectStore.swift:1699-1706` (`conflictCount`는 `item == .conflicted`만 센다). 변경 행은 `propertyState == .conflicted`를 본다(`SVNStatusEntry.isSelectableForCommit`).
- 재현: 실제 재현함
- 트리거:
  1. 한글 xlsx에 `svn:needs-lock`이 있는 작업 복사본 두 개를 만든다.
  2. 한쪽에서 `svn:mime-type`을 바꾸고 커밋한다.
  3. 다른 쪽에서 같은 속성을 다른 값으로 바꾼 뒤 업데이트한다.
- 증상: 실제 `svn status --xml`은 `item="normal" props="conflicted"`다. 변경 목록에는 커밋 불가로 남는다. 사이드바 `ProjectStatusBadges`는 빨간 충돌 숫자가 아니라 주황 연필(로컬 변경 수)만 보여 준다. 프로젝트 여러 개를 두고 보면 충돌 있는 폴더가 깨끗한 것처럼 보인다.
- 확률: 이 팀은 `svn:needs-lock`을 xlsx/hwp에 건다. 속성만 충돌하는 경우는 내용 충돌보다 드물다. 나도 속성 UI를 쓰면 생긴다. 배정 파일 밖에서 집계하므로 뱃지 계약이 어긋난 상태로 남는다.
- 고치는 방법: `updateLocalSummary`에서 `item == .conflicted || propertyState == .conflicted`를 센다. 뱃지 도움말에 속성 충돌을 명시한다.

### 잠금 경로 비교가 UTF-8 바이트라 NFD 볼륨에서 남의 잠금을 놓친다
- 심각도: 중간
- 근거: `Sources/SVNMac/LockWorkflow.swift:36-38,48-54` (`Data(lhs.utf8) == Data(rhs.utf8)`). 같은 함정이 `WorkingCopyFileService.swift:21-23,140-145,200` (`entriesByPath` / `matchesRepositoryPath`). 충돌·커밋 쪽은 `SVNPathIdentity`+`resolvedPath`를 쓴다. 잠금 계획과 탐색기 조회는 쓰지 않는다. 이전 dead-end 감사의 탐색기 매칭과 같은 계열. 잠금 플래너는 그때 안 적혀 있었다.
- 재현: 코드 기준 추정. 이 머신 APFS 체크아웃의 한글 파일명은 NFC라 잠금 경로와 디스크가 같았다. NFD 볼륨(사이드바 「파일명 경고」가 뜨는 디스크)은 단위 테스트 `matchesCanonicalAliasEntriesByRawPathBytes`가 전제한다. LockWorkflow 테스트는 ASCII 경로만 있다.
- 트리거:
  1. NFD로만 이름을 저장하는 볼륨의 작업 폴더에서 한글 xlsx를 고른다.
  2. 다른 사람이 같은 파일을 잠근 상태로 「잠그고 열기」또는 선택 잠금을 누른다.
- 증상: `ExplicitLockPlanner`가 서버 잠금 경로(보통 NFC)와 요청 경로(디스크 NFD)를 다른 파일로 본다. 강제 확인창 없이 일반 `svn lock`을 보낸다. 사용자는 확인 대신 원문 오류만 본다. 탐색기에서는 `svnEntry`가 비어 미버전처럼 보이고, 잠금 아이콘·잠금 확인을 건너뛴다.
- 확률: 머리글에 NFD 볼륨 경고가 뜨는 폴더에서만. 그 경고가 있는 이유가 이 팀의 한글 파일명이다. APFS NFC 작업 폴더에서는 안 터진다.
- 고치는 방법: 잠금 경로 비교와 탐색기 `svnEntry` 조회를 충돌 해결과 같이 정규화 키로 하고, 같은 키에 원문 경로가 둘이면 바이트로만 가른다.

### 리비전 복원·충돌 해결 복구본이 숨김 파일이고 완료 후 위치를 안 알려 준다
- 심각도: 중간
- 근거: `Sources/SVNMac/RevisionFileService.swift:148-161,181` (이름 `.<파일>-before-rN.ext`, 호출부는 `RevisionRestoreResult`를 버린다 — `ProjectStore+History.swift:270-286`). `Sources/SVNMac/ConflictFileService.swift:249-251` (`.working-file-recovery-<UUID>`). `openConflictBackupFolder`는 세션이 살아 있을 때만 (`ProjectStore+Conflicts.swift:281-283`). 이전 destructive 감사 4번과 동일. 코드·테스트(`hasPrefix(".")`) 그대로다.
- 재현: 코드 기준 추정
- 트리거: 파일 기록에서 「이 버전으로 되돌리기」또는 내용 충돌에서 내/서버 버전을 적용한 뒤, 결과가 잘못되어 직전 파일을 찾는다.
- 증상: 복구본은 Application Support 아래 있다. 완료 알림은 커밋하라는 말만 한다. 파일명이 점으로 시작해 Finder 기본 설정에서는 안 보인다. 충돌 시트는 닫히면 「백업 폴더 열기」가 사라진다. 터미널을 안 쓰는 사용자에게는 복구본이 없는 것과 같다.
- 확률: 되돌리기를 쓰는 사람은 이미 잘못했다고 판단한 사람이다. 한 번 더 틀린 결과는 드물지 않다.
- 고치는 방법: 완료 알림에 복구본 경로와 폴더 열기 버튼을 넣고, 선행 점을 뺀다.

### 일괄 잠금 해제 부분 실패 문구가 Swift 오류 덤프다
- 심각도: 낮음
- 근거: `Sources/SVNMac/LockWorkflow.swift:140-143` (`String(describing: error)`). 화면은 `RepositoryLocksView.swift:148-157`. 다른 실패는 `localizedError`를 쓴다. 이전 destructive 감사 부수 항목과 동일.
- 재현: 코드 기준 추정. 테스트 `bulkUnlockReportsExactPartialFailures`는 `message.contains("denied")`만 본다.
- 트리거: 잠금 여러 개를 한 번에 풀다가 일부만 실패한다(네트워크, 남의 잠금, WC locked).
- 증상: 부분 실패 대화상자에 `LockWorkflowTestError.denied` 같은 타입 이름이 그대로 나온다. 다음에 뭘 해야 하는지는 안 나온다.
- 확률: 일괄 해제는 이 팀 정리 작업으로 쓰인다. 부분 실패 자체는 드물다. 생겨도 데이터 손실은 없다.
- 고치는 방법: `BulkUnlockFailure.message`에 `localizedError`를 넣는다.

## 블록 경계
- `ProjectStatusSummary`/`ProjectStatusBadges`는 숫자만 보여 준다. 집계는 `ProjectStore.updateLocalSummary`가 한다. `item`만 세면 속성 충돌이 뱃지 계약에서 빠진다. 변경 탭·커밋 가능 여부는 `propertyState`를 본다.
- `LockWorkflow.ExplicitLockPlanner`는 `ProjectStore+Locking.prepareExplicitLock`이 넘기는 경로와 `repositoryLocks`를 비교한다. 파일 탭은 `node.repositoryRelativePath`, 변경 탭은 `lockPath(for:)`(탐색기 노드의 repository 경로, 없으면 status 경로). 탐색기 `svnEntry`가 바이트 불일치로 비면 변경 탭도 디스크 경로로 떨어진다.
- `OutOfDateCommitRecoveryRequest`는 `projectID`가 있다. `ProjectStore+Update.retryCommitAfterUpdate`가 `hasCompletedUpdate`를 커밋 재시도 전에 켠다. 이후 인증 재개는 `ProjectStore.resume`이 이 플래그로 update/commit을 가른다. 배정 파일은 모델만 있고 재시도 가드는 스토어에 있다.
- `PropertyConflictResolution.verifyResolved`는 `propertyState`만 본다. 호출은 `ProjectStore+Conflicts`. 내용+속성 동시 충돌은 이제 내용 경로로 보내고 `preserveSubtree`를 탄다(이미 고침). 속성 경로로 오분류되면 검증이 내용 잔류를 못 잡는다.
- `ConflictFileService.containedFilePaths`는 트리 충돌 스캔 `TreeConflictRestoreScan.impact`에 콜백으로 붙는다. 스캔은 NFC `hasPrefix`, 디스크 나열은 파일시스템 표기. Swift `String` 동등은 NFC/NFD를 같게 보므로 스캔 누락 위험은 잠금 바이트 비교보다 낮다.
- `RevisionFileService.restoreWorkingFile`은 덮어쓰기 직전 바이트를 백업한다. 확인창이 떠 있는 동안 외부 편집은 STATE-06. 호출부는 복구본 URL을 버린다.
- `WorkingCopyFileService.tree`는 검색만 재귀로 쓴다(`ProjectStore+FileBrowser.searchWorkingCopyFiles`). 브라우저는 `directoryContents`다. STATE-10이 아직 이 경계에 있다.
- `WorkingCopySplitBrowserState`는 뷰 `@State`다(`WorkingCopySplitBrowserView`). `resetSelectedProjectState`는 `ProjectBrowserStore`만 비운다. STATE-12.
- `RepositoryBrowserState`의 버튼 `Task`는 화면 dismiss와 수명이 분리돼 있다. concurrency 감사. `cancelLoading`은 있으나 뷰가 닫힐 때 호출하는지는 이 블록 밖.
- `SVNErrorLocalization.message(for: SVNError.commandFailed)`는 cleanup / E155015 / E195013 / 인증서 영어 문장만 분기한다. `handleRemoteError`는 Keychain 거부만 시트로 연다. E170001 등은 원문 실패 문구. dead-end 감사. LANG은 `en_US.UTF-8`로 고정돼 인증서 영어 매칭은 성립한다.
- `WorkingCopyRecoveryDialogs`의 cleanup 버튼은 `request.projectID`가 아니라 `cleanupSelectedWorkingCopy()`(선택 프로젝트)를 부른다. 프로젝트 전환 시 `workingCopyCleanupRequest = nil`이라 시트는 같이 사라진다.
- `TemporaryFilePolicy.automaticallySelectedEntries`가 `missing`을 넣는 것은 테스트가 기대하는 현재 제품 동작이다. destructive 감사가 지적한 행 UI 죽은 분기는 `ChangesView` 쪽.
- 경로 부모 계산이 두 벌이다. `WorkingCopySplitBrowserState.parentDirectory`(NSString)와 `WorkingCopyBrowserTreeState.parentPath`(마지막 `/`). 루트에서 반환값만 다르다(`""` vs `nil`). 지금은 의도에 맞다. 한쪽만 고치면 키보드 이동이 갈라진다.
- `HistoryDateFormatting`과 `WorkingCopyFileDateFormatting`은 둘 다 DateFormatter 캐시다. 커밋 시각은 설정 시간대, 파일 수정 시각은 Mac 로컬. 의도적 분리.

## 검증 공백
- `ProjectStatusSummary`/`ProjectStatusBadges`: `conflictCount`에 `propertyState == .conflicted`를 넣는 테스트가 없다. 넣을 입력: 위 재현의 `item=normal props=conflicted` 스냅샷으로 `updateLocalSummary` 후 `conflictCount == 1`.
- `LockWorkflow`: NFC 서버 잠금 vs NFD 요청 경로. `ExplicitLockPlanner.plan(paths: [nfd], locks: [nfc, owner: other])`가 `.confirmForce`여야 한다. 지금은 ASCII만.
- `WorkingCopyFileService.entriesByPath`: 디스크 NFD + 저장소 NFC만 있는 경우(충돌 없음) `svnEntry`가 연결되는지. 있는 테스트는 두 원문이 동시에 있는 충돌 fixture다.
- `HistoryDateFormatting`: 테스트 파일 없음. DST/약어, `usesKSTAbbreviation`이 캐시 키에 없는 것은 약어를 포맷터 밖에서 붙이므로 동작은 맞다. 회귀 테스트는 없다.
- `OutOfDateCommitRecoveryRequest.hasCompletedUpdate`: 업데이트 성공 후 커밋이 인증 실패했을 때 `resume`이 커밋만 재시도하는지. 스토어 테스트에 모델 필드 조합이 거의 없다.
- `PropertyConflictService.propertyNames`: 중첩 파일 `공유/문서.xlsx`와 NFD `.prej` 파일명. 있는 테스트는 디렉터리 한 단계 `공유` + `dir_conflicts.prej`.
- `TreeConflictRestoreScan`: NFD status 경로 + NFC target. `isAtOrBelow`는 NFC로 맞추므로 통과할 가능성이 높다. 입력을 안 넣었다.
- `RevisionFileService`/`ConflictFileService`: 복구본 이름이 Finder에 보이는지, 완료 알림에 URL이 실리는지는 UI 테스트 없음. 선행 점만 단위 테스트가 고정한다.
- `TemporaryFilePolicy.validateRepositoryCleanupCandidates`: `nameOnlyCleanupCandidates` 디렉터리(`.Trashes` 등)가 정규 파일 검사를 건너뛰는지 테스트 없음. destructive 감사가 손실 시나리오로 안 센 항목.
- `RepositoryBrowserState`: 한글 URL NFC/NFD percent-encoding이 다른 lookup URL이 되는지. `list`는 원문 URL 보존이 규칙이다. 브라우저 정규화는 `URLComponents`라 입력 유니코드 형태를 그대로 인코딩한다.
- `SVNErrorLocalization`: E170001/E215004/E170013 안내 문구 테스트 없음. 인증서 영어 문장만 있다.
- `WorkingCopyFileService.tree` 검색: 큰 문서 트리에서 취소·세대 가드. 기능 테스트는 작은 fixture.
- `ActionProgressLabel`, `OptionalPresentationBinding`, `AppContactSupport`, `SVNMacApp`: 동작 테스트 없음(다른 파일 문자열 포함 검사만).
- `KeychainStore`: 읽기 실패 → `accessDenied` 매핑, utf8이 아닌 데이터.

## 확인하지 않은 것
- GUI를 띄우지 않았다. 뱃지 실제 픽셀, 시트 포커스, Finder 숨김 파일 표시는 코드와 XML까지만 봤다.
- NFD 전용 볼륨(HFS+)에서 잠금/탐색기 매칭은 재현하지 않았다. APFS에서는 한글 체크아웃이 NFC였다.
- 사내 HTTPS 인증서·프록시·실제 App Store lookup은 호출하지 않았다.
- `svn revert --depth infinity`가 미버전 파일을 디스크에서 지우는지는 이번 세션에서 다시 돌리지 않았다. `ConflictFileService.preserveSubtree` 주석이 그 전제를 쓴다.
- `offerWorkingCopyCleanup`이 `isShowingCredentials = true`로 폴더 설정 위에 cleanup 시트를 올리는 흐름은 화면 파일을 읽었고, 클릭 순서는 안 밟았다.
- 데모 모드와 라이브 스토어 전환(`.id(isDemoMode)`) 중 업데이트 확인 Task 잔존은 확인하지 않았다.
