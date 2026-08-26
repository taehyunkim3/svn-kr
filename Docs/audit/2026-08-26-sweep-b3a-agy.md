# GUI 화면·작업 흐름 전수 감사 (B3a)

## 읽은 파일
- Sources/SVNMac/AppAboutView.swift — 100줄 — 앱 버전/빌드 정보 및 업데이트 확인 UI, 메뉴 커맨드 정의
- Sources/SVNMac/ChangesView.swift — 485줄 — 변경 파일 목록, diff 패널, 커밋 툴바, 컨텍스트 메뉴 및 화면 모달 배선
- Sources/SVNMac/CommitConfirmationView.swift — 158줄 — 서버 삭제 및 빈 커밋 메시지 검토 및 삭제 복원 시트
- Sources/SVNMac/CommitControlsView.swift — 80줄 — 커밋 메시지 입력, 선택 통계, 커밋 실행 제어 바
- Sources/SVNMac/CommitDeletionRestoreConfirmation.swift — 36줄 — 삭제 예정 파일 복원 확인 공통 다이얼로그 모디파이어
- Sources/SVNMac/ConflictResolutionView.swift — 281줄 — 파일 내용 충돌 해결 시트 (내 버전, 서버 버전, 작업 파일 선택 및 백업 폴더 열기)
- Sources/SVNMac/ContentView.swift — 466줄 — 최상위 윈도우 분할 뷰, 사이드바 프로젝트 관리, 상단 툴바, 탭 뷰(변경/파일/기록) 및 메인 시트 배선
- Sources/SVNMac/DeletionConfirmationView.swift — 58줄 — 선택 항목 저장소 삭제 예약 확인 시트
- Sources/SVNMac/DetailedErrorView.swift — 120줄 — 상세 에러 메시지 뷰어, 클립보드 복사 및 에러 프레젠터 모디파이어
- Sources/SVNMac/DiffTextView.swift — 33줄 — 단일 AttributedString 기반 diff 구문 강조(추가 녹색/삭제 적색) 텍스트 뷰
- Sources/SVNMac/DocumentOpenConfirmation.swift — 97줄 — 잠금 필요 문서(needs-lock 등) 열기 전 잠금 확인 다이얼로그
- Sources/SVNMac/FileHistoryView.swift — 164줄 — 단일 파일의 리비전 이력 목록, 리비전 파일 저장 및 작업 파일 복원 시트
- Sources/SVNMac/HistoryRevisionDiffView.swift — 192줄 — 선택된 커밋의 변경 경로 목록 및 리비전 diff 상세 패널
- Sources/SVNMac/HistoryView.swift — 433줄 — 전체 커밋 타임라인, 분기 그래프 렌더링(Canvas), 커밋 검색 및 요약 헤더
- Sources/SVNMac/IgnoreRulesView.swift — 233줄 — svn:ignore 목록 관리 및 .gitignore 규칙 비교/가져오기 시트

## 발견
### 과거 이력 상세에서 삭제된 파일 "작업 파일로 복원" 시 로컬 파일 부재로 무조건 실패
- 심각도: 높음
- 근거: Sources/SVNMac/HistoryRevisionDiffView.swift:42-49, Sources/SVNMac/ProjectStore+History.swift:55-73, 235-293, Sources/SVNMac/RevisionFileService.swift:121-124, 184-203
- 재현: 코드 기준 추정
- 트리거: 커밋 기록(History 탭)에서 삭제된 파일(SVNChangedPath.action == .deleted)을 선택하고, 상단에 노출된 「작업 파일을 이 리비전으로 복원」 버튼 클릭 후 확인 대화상자에서 복원 확정
- 증상: `RevisionFileService.restoreWorkingFile`이 기존 작업 파일 백업 생성을 위해 `regularWorkingFile`을 호출하지만, 로컬 파일시스템에 대상 파일이 존재하지 않아 `RevisionFileError.missingWorkingFile` 오류가 발생하고 복원 작업이 중단됨
- 확률: 중간. 삭제된 문서를 이력에서 복구하는 워크플로에서 매번 발생
- 고치는 방법: `RevisionFileService.restoreWorkingFile`에서 로컬 파일이 없는 경우 기존 파일 백업을 건너뛰고 부모 디렉터리 존재 확인 후 바로 새 파일 내용을 쓰도록 분기 처리

### ChangesView의 잠금 정보 매칭(lockInfo)이 UTF-8 바이트(Data) 비교를 사용하여 한글 NFD/NFC 차이 시 잠금 표시 누락
- 심각도: 중간
- 근거: Sources/SVNMac/ChangesView.swift:466-471
- 재현: 코드 기준 추정
- 트리거: 원격 저장소에 한글 파일명(NFC)으로 잠금이 걸려 있고, 로컬 macOS 작업 복사본의 변경 항목(NFD)이 ChangesView 목록에 표시될 때
- 증상: `Data($0.path.utf8) == Data(repositoryPath.utf8)` 바이트 비교가 false를 반환하여, 파일이 잠겨 있음에도 파일 행에 자물쇠 아이콘과 잠금 소유자 이름이 노출되지 않음
- 확률: 높음. macOS 파일시스템(NFD)과 SVN 서버 응답(NFC)의 유니코드 정규화 차이가 상시 발생
- 고치는 방법: `Data` 바이트 비교 대신 유니코드 정규화 문자열 비교(`precomposedStringWithCanonicalMapping`) 또는 `SVNPathIdentity`를 사용해 비교

### FileHistoryView의 날짜 포맷이 사용자 설정 시간대(historyTimeZone)를 무시하고 시스템 기본값으로 출력됨
- 심각도: 낮음
- 근거: Sources/SVNMac/FileHistoryView.swift:29-30, Sources/SVNMac/HistoryView.swift:324-338
- 재현: 코드 기준 추정
- 트리거: 설정에서 커밋 기록 시간대를 변경한 상태에서 파일 우클릭 → 「파일 커밋 기록」 시트 열기
- 증상: HistoryView는 설정된 시간대와 `HistoryDateFormatting`을 적용하는 반면, FileHistoryView는 `date.formatted(date: .numeric, time: .standard)`를 사용하여 로컬 시스템 시간대/기본 형식으로만 출력됨
- 확률: 낮음. 시간대 설정을 변경한 사용자에게만 발생
- 고치는 방법: `FileHistoryView`에서도 `HistoryDateFormatting.shared.string`과 `historyTimeZone` 설정을 사용하도록 통일

### ChangesView의 diff 패널이 DiffTextView 대신 일반 Text를 사용하여 변경 줄 색상 강조가 누락됨
- 심각도: 낮음
- 근거: Sources/SVNMac/ChangesView.swift:24-34, Sources/SVNMac/DiffTextView.swift:4-32, Sources/SVNMac/HistoryRevisionDiffView.swift:167-169
- 재현: 코드 기준 추정
- 트리거: 변경 사항(Changes) 탭에서 변경된 파일을 선택하여 diff 패널 확인
- 증상: `HistoryRevisionDiffView`에서는 `DiffTextView`를 통해 추가(+)/삭제(-) 줄이 녹색/빨간색으로 구문 강조되나, `ChangesView`에서는 일반 Text로 출력되어 단색으로만 보임
- 확률: 높음. Changes 탭 diff 조회 시 상시
- 고치는 방법: `ChangesView`의 diff 상세 패널에서도 `DiffTextView`를 사용하도록 교체

### ChangesView 툴바의 needs-lock 메뉴 비활성화 가드가 isWorking으로만 되어 있어 동시 작업 차단 불완전
- 심각도: 낮음
- 근거: Sources/SVNMac/ChangesView.swift:368-380
- 재현: 코드 기준 추정
- 트리거: `isSelectedProjectActionBlocked`가 true이지만 `isWorking`은 false인 상태(예: 일부 백그라운드 작업 또는 전이 상태)에서 툴바의 needs-lock 메뉴 버튼 클릭
- 증상: 인접한 잠금 버튼은 비활성화되나 needs-lock 드롭다운 메뉴는 활성 상태로 남아 잘못된 타이밍에 속성 변경 명령 제출 가능
- 확률: 낮음.
- 고치는 방법: Menu의 disabled 조건을 `store.isSelectedProjectActionBlocked`로 통일

## 블록 경계
- `HistoryRevisionDiffView` ↔ `ProjectStore+History` ↔ `RevisionFileService`: `HistoryRevisionDiffView`는 삭제된 파일(`action == .deleted`)에 대해 peg revision(rN-1)을 계산해 내용을 가져오지만, `RevisionFileService.restoreWorkingFile`의 전제조건(기존 로컬 정규 파일 필수 존재)과 불일치하여 복원이 실패함.
- `ChangesView` ↔ `WorkingCopyFileService` ↔ `SVNCore`: `ChangesView`의 `lockInfo`가 `SVNLockInfo.path`와 `entry.path`를 원시 바이트(`Data`)로 비교하여 macOS 파일시스템의 NFD와 저장소의 NFC 경로 간 불일치로 잠금 표시가 누락됨.
- `ChangesView` ↔ `WorkingCopyBrowserView` ↔ `ContentView`: `.sheet` 및 확인창 모디파이어(`documentOpenConfirmation`, `isShowingFileHistory`, `versionedFileActionRequest`, `commitDeletionRestoreConfirmation`)가 부모와 자식 뷰 계층에 중복 선언되어 있어 SwiftUI 시트 표시 충돌 위험이 존재함.
- `ContentView` ↔ `ProjectStore+Update` ↔ `AuthenticationRequiredView`: 업데이트 미리보기 시트가 열린 상태에서 인증 요청 발생 시 시트 중첩/차단 문제(선행 감사 지적 사항과 연계).

## 검증 공백
- `DiffTextView`: 전용 단위 테스트 없음 (`DiffTextViewTests` 부재). 헤더 라인(`+++`/`---`), 추가/삭제 라인(`+`/`-`), 개행 유지 등의 AttributedString 생성 로직이 테스트되지 않음.
- `FileHistoryView` / `HistoryRevisionDiffView`: 과거 삭제된 파일의 복원 시도 시 `missingWorkingFile` 실패 경로 및 peg revision 기반 복원 처리 테스트 부재.
- `ChangesView`: NFD 한글 경로가 포함된 `SVNStatusEntry`와 NFC `SVNLockInfo` 간 잠금 매칭 검증 테스트 부재.
- `FileHistoryView`: 사용자 설정 시간대(`historyTimeZoneIdentifier`) 변경 시 날짜 렌더링 일치 여부 테스트 부재.
- `IgnoreRulesView`: 상속된 규칙(`inheritedFrom != nil`)의 삭제 비활성화 및 전역 규칙 적용 확인 alert 동작에 대한 단위 테스트 부재.

## 확인하지 않은 것
- GUI 직접 실행 미확인: 실제 macOS GUI 화면을 띄워 시트 중복 렌더링, Return 단축키 포커스 동작, NSSavePanel 팝업을 눈으로 확인하지 않음 (코드 정적 분석 기준).
- 네트워크 저장소 환경에서의 실시간 잠금 동기화: 원격 SVN 서버와의 실시간 `repositoryLocks` 갱신 지연 상황 미확인.
