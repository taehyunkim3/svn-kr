# Sources/SVNMac 전수 감사 (B4b)

## 읽은 파일
- Sources/SVNMac/ActionProgressLabel.swift — 24줄 — 작업 실행 중 스피너와 라벨을 일관된 크기로 표시하는 SwiftUI 뷰
- Sources/SVNMac/AppContactSupport.swift — 26줄 — 고객 지원 이메일 링크 및 관련 다국어 문구 제공 열거형
- Sources/SVNMac/AppLayout.swift — 141줄 — 앱 창, 분할 뷰, 시트의 최소/이상 크기 상수 및 레이아웃 헬퍼
- Sources/SVNMac/AppSettings.swift — 216줄 — UserDefaults 설정 키, 언어/시간대/잠금 정책 열거형 및 설정 화면 뷰
- Sources/SVNMac/AppUpdateChecker.swift — 180줄 — App Store 업데이트 자동/수동 확인 및 버전 비교 서비스
- Sources/SVNMac/ConflictFileService.swift — 484줄 — 충돌 해결용 로컬/서버 파일 보존, 바이트 검증 및 원자적 대치 서비스
- Sources/SVNMac/HistoryDateFormatting.swift — 31줄 — 커밋 기록용 날짜 포맷터 캐시 및 스레드 안전 포맷팅 클래스
- Sources/SVNMac/HistoryPathPresentation.swift — 40줄 — 저장소 절대 경로를 작업 복사본 기준 상대 경로와 파일명으로 변환하는 구조체
- Sources/SVNMac/KeychainStore.swift — 130줄 — 프로젝트 UUID 기반 macOS Keychain 비밀번호 안전 저장/조회/삭제 관리자
- Sources/SVNMac/LockWorkflow.swift — 152줄 — 다중 파일 잠금 계획 수립, 강제 잠금 분기 및 일괄 잠금 해제 실행기
- Sources/SVNMac/OptionalPresentationBinding.swift — 12줄 — Optional 상태를 모달/시트용 Bool 바인딩으로 변환하는 확장
- Sources/SVNMac/OutOfDateCommitRecovery.swift — 29줄 — 최신 상태가 아닌 작업 복사본의 커밋 복구 요청 데이터 모델
- Sources/SVNMac/ProjectStatusBadges.swift — 41줄 — 사이드바 프로젝트 행의 변경/충돌/잠금/업데이트 상태 배지 뷰
- Sources/SVNMac/ProjectStatusSummary.swift — 15줄 — 로컬 변경, 충돌, 잠금 개수 요약 구조체 및 되돌리기 요청 모델
- Sources/SVNMac/PropertyConflictResolution.swift — 124줄 — 속성 충돌 해결 선택지, 검증 및 `.prej` 파일 파싱 서비스
- Sources/SVNMac/RepositoryBrowserState.swift — 297줄 — 원격 저장소 트리 탐색, URL 이동, 디렉터리 진입 및 오류 상태 관리자
- Sources/SVNMac/RepositoryPathNormalizationPresentation.swift — 103줄 — 저장소 경로의 NFD/NFC 정규화 차이 및 유니코드 코드포인트 차이 계산기
- Sources/SVNMac/RevisionFileService.swift — 208줄 — 특정 리비전 파일의 안전한 내보내기 및 작업 파일 복원 백업 액터
- Sources/SVNMac/SVNErrorLocalization.swift — 191줄 — SVN 오류 및 충돌 파일 오류를 사용자 친화적 메시지로 지역화하는 매퍼
- Sources/SVNMac/SVNMacApp.swift — 119줄 — SwiftUI 앱 엔트리포인트, 메인 윈도우, 메뉴 커맨드 및 설정/정보 창 구성
- Sources/SVNMac/ServerCertificateTrust.swift — 15줄 — 서버 인증서 검증 실패 사유 분류 및 신뢰 허용 가능 여부 판정 구조체
- Sources/SVNMac/StatusBadge.swift — 85줄 — 작업 복사본 항목 상태별 색상 톤 정책 및 캡슐형 상태 배지 뷰
- Sources/SVNMac/TemporaryFileClassification.swift — 214줄 — 오피스 잠금 파일, `.DS_Store` 등 임시 파일 식별, 숨김 및 정리 유효성 검증기
- Sources/SVNMac/TreeConflictResolution.swift — 125줄 — 트리 충돌 해결 선택지 및 되돌리기 시 사라질 하위 파일 위험도 스캔기
- Sources/SVNMac/UpdatePreviewState.swift — 51줄 — 원격 업데이트 미리보기의 커밋 목록, 리비전 펼침 상태 및 실행 가능성 관리자
- Sources/SVNMac/WorkingCopyBrowserModel.swift — 430줄 — 작업 복사본 파일 브라우저 트리 캐시, 키보드 네비게이션, 정렬 및 필터링 상태 모델
- Sources/SVNMac/WorkingCopyFileService.swift — 232줄 — 파일시스템 실측 디렉터리 읽기 및 SVN 항목 메타데이터 매핑 액터
- Sources/SVNMac/WorkingCopyRecoveryDialogs.swift — 131줄 — 작업 복사본 cleanup 및 취소된 체크아웃 복구 대화상자 뷰
- Sources/SVNMac/WorkingCopySplitBrowserState.swift — 212줄 — 분할 보기 파일 브라우저의 폴더 트리 펼침, 선택 및 포커스 상태 관리자

## 발견

### 한글 NFD/NFC 정규화 차이로 인한 잠금 충돌 오탐 및 강제 잠금 확인창 누락
- 심각도: 높음
- 근거: `Sources/SVNMac/LockWorkflow.swift:37-38`, `52-54`
- 재현: 코드 기준 추정
- 트리거:
  1. 다른 팀원이 Windows 등에서 한글 파일(예: `예산안.xlsx`, 서버 저장소에 NFC로 커밋/잠금됨)을 잠근다.
  2. 현재 사용자가 macOS 작업 복사본(APFS 파일시스템에서 NFD로 제공됨)에서 해당 파일을 선택하고 "잠금"을 실행한다.
- 증상: `ExplicitLockPlanner.pathsMatch`가 `Data(lhs.utf8) == Data(rhs.utf8)` 바이트 비교를 수행하여 NFC와 NFD 문자열 매칭에 실패한다. `conflictingLocks`가 비어있는 것으로 판정되어 `.confirmForce` 확인창 대신 `.run(force: false)`가 반환된다. SVN 클라이언트는 `--force` 없이 `svn lock`을 실행하다가 `svn: E195015: Path '...' is already locked by user '...'` 오류를 내고 실패하며, 사용자는 강제 잠금 대화상자를 안내받지 못한다.
- 확률: 높음. 한국 사무직 환경에서 Windows와 macOS 사용자가 혼재되어 한글 파일명(xlsx, hwp)을 공유 잠금하는 기본 워크플로에 해당함.
- 고치는 방법: `ExplicitLockPlanner.pathsMatch`에서 UTF-8 바이트 비교 대신 Swift 표준 문자열 동등성(`lhs == rhs`) 또는 `precomposedStringWithCanonicalMapping` 기반의 정규화 비교를 수행한다.

### 파일 브라우저에서 한글 파일의 SVN 버전 관리 상태 및 잠금 표시 누락
- 심각도: 중간
- 근거: `Sources/SVNMac/WorkingCopyFileService.swift:21-23`, `143-145`, `200`
- 재현: 코드 기준 추정
- 트리거:
  1. 저장소에 NFC로 커밋된 한글 파일(예: `보고서.hwp`)이 포함된 프로젝트를 체크아웃한다.
  2. 분할 보기 또는 트리 보기 파일 브라우저에서 해당 디렉터리를 탐색한다.
- 증상: `WorkingCopyFileService.loadChildren`이 `FileManager.contentsOfDirectory`로 읽은 NFD 파일시스템 경로를 `SVNPathIdentity`(바이트 일치) 키로만 `entriesByPath`에서 조회한다. NFC SVN 메타데이터와의 매핑이 실패하여 `WorkingCopyFileNode.svnEntry`가 `nil`이 되고 `isVersioned`가 `false`가 된다. 파일 브라우저에서 버전 관리 대상 파일이 미버전 파일로 노출되거나 SVN 상태 정보가 표시되지 않는다. 추가로 `WorkingCopyFileNode.matchesRepositoryPath`도 바이트 비교를 사용하여 `WorkingCopySplitBrowserView:758`의 잠금 아이콘 표시 매칭이 실패한다.
- 확률: 높음. macOS 파일시스템에서 한글 파일명이 decomposed(NFD)로 반환되는 모든 저장소 체크아웃 환경에 해당함.
- 고치는 방법: `WorkingCopyFileService.entriesByPath` 매핑 시 raw UTF-8 키 매핑 실패 시 `canonicalKey`(NFC) 조회를 fallback으로 적용하고, `matchesRepositoryPath`도 정규화 비교를 지원하도록 수정한다.

### 저장소 둘러보기 로딩 중 사용자 조작(새로고침/상위 이동/폴더 진입)이 무시되는 현상
- 심각도: 중간
- 근거: `Sources/SVNMac/RepositoryBrowserState.swift:160-170`, `173`, `208`, `214`
- 재현: 코드 기준 추정
- 트리거:
  1. 저장소 둘러보기 시트에서 URL 조회를 시작했거나 하위 폴더 로딩 중인 상태(`phase == .loading`)이다.
  2. 네트워크 응답이 오는 도중 사용자가 상위 폴더(↑) 버튼, 새로고침 버튼, 또는 목록의 다른 폴더를 더블클릭한다.
- 증상: `startLoading`이 이전 `loadTask`를 취소하고 새 태스크를 생성하지만, `phase`가 여전히 `.loading`인 상태에서 새 태스크의 `browse()`, `loadCurrentDirectory()`, `navigate(to:)`가 호출된다. 내부의 `guard !isLoading else { return }` 검사로 인해 새 요청이 즉시 리턴되어 버려진다. 이전 태스크가 취소되어 `phase = .idle`로 전환되면 아무 작업도 진행되지 않는 정지 상태로 남는다.
- 확률: 중간. 원격 SVN 서버 연결 지연 시 사용자가 탐색을 연타하거나 새로고침할 때 발생함.
- 고치는 방법: `startLoading` 시 새 작업을 시작하기 전에 `phase = .idle`로 전환하거나, `startLoading` 내부 실행 흐름에서는 `guard !isLoading` 검사를 생략하도록 수정한다.

## 블록 경계
- `LockWorkflow.swift` ↔ `ProjectStore+Locking.swift` ↔ `SVNCore`:
  - `ProjectStore`가 SVN 서버에서 받아온 `SVNLockInfo`와 로컬 선택 경로를 `ExplicitLockPlanner`로 전달할 때, 경로의 Unicode NFD/NFC 정규화 차이가 발생하면 타인 잠금 감지에 실패하여 강제 잠금 확인 모달 대신 일반 `svn lock` 실행으로 실패함.
- `WorkingCopyFileService.swift` ↔ `WorkingCopyBrowserView` / `WorkingCopySplitBrowserView` ↔ `SVNCore`:
  - `WorkingCopyFileService`가 파일시스템에서 읽은 NFD 경로를 `SVNPathIdentity` (raw UTF-8 바이트 해시)로만 SVN 엔트리와 매핑하여, NFC로 저장된 SVN 메타데이터와 결합되지 못함.
  - `WorkingCopyFileNode.matchesRepositoryPath`가 바이트 일치를 검사하여 파일 브라우저 UI에서 서버 잠금 정보(`store.repositoryLocks`)와의 일치 여부 판정에 실패함.
- `RepositoryBrowserState.swift` ↔ `RepositoryBrowserView.swift`:
  - `RepositoryBrowserView`의 UI 액션(새로고침, 상위 이동, 폴더 진입)이 `startLoading`을 호출할 때 이전 태스크의 취소 완료 전 새 진입점의 `guard !isLoading` 검사로 인해 사용자 조작이 누락되는 비동기 상태 경계 결함이 존재함.
- `ConflictFileService.swift` ↔ `PropertyConflictResolution.swift` ↔ `TreeConflictResolution.swift`:
  - 텍스트, 속성, 트리 충돌 해결 과정에서 작업 복구 파일 백업(`.staging` 기반 원자적 이동 및 바이트 동일성 검증)과 `.prej` 파일 파싱, 하위 트리 백업이 일관되게 계약을 유지함.
- `AppSettings.swift` ↔ `SVNMacApp.swift` ↔ `ProjectStore`:
  - `AppSettings`에 정의된 키와 기본값들이 `SVNMacApp`의 `@AppStorage` 및 `ProjectStore`의 설정 반영 흐름과 정확히 일치함.

## 검증 공백
- `Tests/SVNMacTests/LockWorkflowTests.swift`:
  - 현재 테스트는 `"Documents/a.xlsx"` 등 ASCII 영문 경로만 사용함. NFD 인코딩된 로컬 경로와 NFC 인코딩된 `SVNLockInfo.path`가 입력되었을 때의 잠금 충돌 탐지 및 강제 잠금 분기 테스트가 누락됨.
- `Tests/SVNMacTests/WorkingCopyFileServiceTests.swift`:
  - 기존 `matchesCanonicalAliasEntriesByRawPathBytes`는 로컬과 SVN 엔트리 모두 decomposed(NFD)인 특수 별칭 케이스만 검증함. SVN 메타데이터가 NFC이고 macOS 파일시스템이 NFD인 일반 체크아웃 환경에서 `tree` 및 `directoryContents`가 `svnEntry`와 `isVersioned`를 올바르게 연결하는지 검증하는 테스트가 없음.
- `Tests/SVNMacTests/ConcurrencyRepositoryBrowserTests.swift`:
  - 현재 테스트는 시트 닫힘 시의 단순 취소(`cancelLoading()`)만 검증함. `phase == .loading` 상태에서 사용자가 `beginRefresh()`, `beginNavigateUp()`, `beginEnterSelectedDirectory()`를 연속 호출했을 때 요청이 버려지지 않고 새 디렉터리를 로드하는지 검증하는 동시성 테스트가 없음.
- `Sources/SVNMac/ActionProgressLabel.swift`, `Sources/SVNMac/AppContactSupport.swift`, `Sources/SVNMac/WorkingCopyRecoveryDialogs.swift`:
  - SwiftUI 전용 프레젠테이션 컴포넌트로 개별 단위 테스트가 부재하며 상위 뷰 통합 렌더링에 의존함.

## 확인하지 않은 것
- `Sources/SVNCore` 내부의 `SVNClient` C/Process 실행 레이어 및 SQLite wc.db 직접 조작 코드 (B4b 배정 범위 외).
- `Sources/SVNMac/ProjectStore+*.swift`의 전체 상태 전이 로직 (배정된 29개 파일과의 경계 인터페이스 외의 세부 구현).
- 실제 macOS GUI 상에서의 마우스 드래그/분할선 조절 등 AppKit/SwiftUI 렌더링 애니메이션 시각 효과.
