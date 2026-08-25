# 감사 B: 동시성 — 늦게 도착한 응답과 상태 오염

## 검증 요약

- 기준: `ProjectStore.beginRequest`는 요청 종류별 최신 UUID와 선택 프로젝트를 함께 확인한다. `beginOperation`은 실행 표시만 기록하며 응답 유효성을 보장하지 않는다.
- 실제 재현 환경: SVN 1.14.5, 임시 `file://` 저장소, 동일 작업 복사본.
- 동시 `svn commit` 2개: 1개 성공, 1개 실패. 오류 원문은 `svn: E155004: Working copy '…/wc-a' locked.`였다.
- 동시 `svn update` 2개: 1개가 같은 `E155004`로 실패했다.
- 폴러와 같은 `svn status --show-updates --xml`을 11,500개 파일 작업 복사본의 1,500개 파일 update와 18회 겹쳤다. status 실패 0회, update 실패 0회. 뱃지 폴러 자체가 update와 겹쳐 `E155004`를 만드는 현상은 재현하지 못했다.
- `swift test`: 493개 통과.

## 커밋 메시지 Return이 버튼 비활성화를 우회해 커밋을 중복 실행한다

- 심각도: 중간
- 근거: `Sources/SVNMac/CommitControlsView.swift:13-16`, `Sources/SVNMac/CommitControlsView.swift:31-45`, `Sources/SVNMac/CommitControlsView.swift:63-75`, `Sources/SVNMac/ProjectStore.swift:1217-1237`
- 재현: 실제 재현함 — 동일 작업 복사본에서 동시 `svn commit` 2개 중 1개가 `E155004`로 실패했다. 앱에서 Return 연타가 두 Task를 만드는 부분은 코드 기준 추정이다.
- 트리거: 삭제 대상 없는 변경을 선택하고 커밋 메시지 입력칸에서 Return을 누른다. 첫 커밋 진행 중 입력칸에서 Return을 다시 누른다. 버튼만 `isSelectedProjectActionBlocked`로 비활성화되고 `TextField.onSubmit`은 계속 호출된다.
- 증상: 첫 커밋은 성공해도 두 번째 커밋이 `svn: E155004: Working copy '…' locked.`로 실패한다. 사용자는 성공과 cleanup 요구를 동시에 보게 된다.
- 확률: 중간. 느린 커밋에서 응답이 없어 Return을 다시 누르는 조작은 자연스럽다.
- 고치는 방법: `commit` 진입점에서 같은 프로젝트의 활성 `.commit`을 원자적으로 거부하고, 메시지 입력칸도 작업 중 submit을 무시한다.

## 후속 await 뒤 프로젝트 재검증이 빠져 A 결과가 B 전역 상태를 쓴다

- 심각도: 중간
- 근거: `Sources/SVNMac/ProjectStore+RepositoryMaintenance.swift:373-378`, `Sources/SVNMac/ProjectStore+Cleanup.swift:64-87`, `Sources/SVNMac/ProjectStore+RepositoryMaintenance.swift:187-204`, `Sources/SVNMac/ProjectStore+Deletion.swift:100-113`, `Sources/SVNMac/ProjectStore.swift:1253-1263`, `Sources/SVNMac/ProjectStore.swift:1687-1719`
- 재현: 코드 기준 추정
- 트리거: 다음 중 하나를 A에서 시작하고 마지막 후속 조회 중 B로 전환한다. `svn:needs-lock` 변경 실패 후 상태 복구, cleanup, relocate 실패 후 현재 URL 재조회, 삭제 예약 후 로컬 refresh, 커밋 성공·검증 경고 후 refresh. 한 창의 sheet가 전환을 막아도 `WindowGroup`이 공유하는 다른 창에서는 전환할 수 있다.
- 증상: B가 불필요하게 refresh되고 A 오류·완료 notice·cleanup 해제·relocate 요청이 B 화면에 나타난다. 삭제 경로명이 겹치면 B 선택 집합까지 오염될 수 있다. `resetSelectedProjectState()`가 먼저 비운 값을 늦은 A 응답이 다시 채운다.
- 확률: 낮음~중간. `svn:needs-lock`은 팀 문서 흐름에서 자주 쓰지만 실패와 전환이 겹쳐야 한다. 나머지는 실패·검증 경고·다중 창까지 필요해 드물다.
- 고치는 방법: 모든 후속 `await` 직후 원래 project ID와 작업·요청 ID를 다시 확인하고, 복구 helper가 현재 선택 프로젝트를 다시 읽지 않게 한다.

## 업데이트 미리보기는 같은 프로젝트의 최신 요청을 구분하지 않는다

- 심각도: 중간
- 근거: `Sources/SVNMac/ProjectStore+Update.swift:98-149`, `Sources/SVNMac/ContentView.swift:134-158`, `Sources/SVNMac/ProjectStore.swift:541-546`, `Sources/SVNMac/ProjectStore.swift:567-593`
- 재현: 코드 기준 추정
- 트리거: A에서 업데이트 버튼을 누르고 완료 전에 다시 누른다. `.previewUpdate`는 progress 표시는 하지만 `isSelectedProjectActionBlocked`에 포함되지 않아 버튼이 계속 활성화된다.
- 증상: 두 요청이 공용 `updatePreview`와 `remoteChanges`를 각각 초기화하고 쓴다. 먼저 시작한 느린 응답이 나중 요청의 커밋 목록·원격 변경·오류를 덮거나 서로 다른 시점의 두 결과를 한 팝업에 섞는다.
- 확률: 중간. 서버가 느릴 때 같은 활성 버튼을 다시 누르기 쉽고, 최근 미리보기가 두 원격 명령을 순차 실행해 겹침 시간이 길다.
- 고치는 방법: `ProjectRequestKind.updatePreview` 최신 토큰을 추가하고 버튼도 `isPreviewingSelectedProjectUpdate` 동안 비활성화한다.

## 파일 기록을 연속으로 열면 느린 첫 파일 기록이 둘째 파일을 덮는다

- 심각도: 중간
- 근거: `Sources/SVNMac/ProjectStore+FileActions.swift:163-183`, `Sources/SVNMac/WorkingCopyBrowserView.swift:172-185`, `Sources/SVNMac/WorkingCopySplitBrowserView.swift:427-440`, `Sources/SVNMac/ProjectStore.swift:537-539`, `Sources/SVNMac/ProjectStore.swift:567-593`
- 재현: 코드 기준 추정
- 트리거: 같은 프로젝트에서 기록이 많은 파일 A의 “파일 커밋 기록”을 누른 직후 파일 B의 기록을 연다. 파일 기록은 읽기 작업이라 다른 액션을 막지 않고 요청 토큰도 없다.
- 증상: B 응답 뒤 A 응답이 도착하면 팝업 제목과 목록이 A로 돌아간다. 사용자는 B 기록을 열었다고 생각하고 A 리비전을 저장·복원할 수 있다.
- 확률: 중간. 문서가 많고 서버 log가 느린 팀에서 빠른 연속 조회가 가능하다.
- 고치는 방법: `ProjectRequestKind.fileHistory`를 추가해 최신 path 요청만 `fileHistory`, `fileHistoryPath`, sheet 상태를 쓰게 한다.

## 여러 작업 폴더 등록 Task가 완료 순서대로 프로젝트 선택을 빼앗는다

- 심각도: 중간
- 근거: `Sources/SVNMac/ProjectStore.swift:722-729`, `Sources/SVNMac/ProjectStore.swift:900-920`, `Sources/SVNMac/ProjectStore.swift:732-754`
- 재현: 코드 기준 추정
- 트리거: “기존 로컬 폴더 등록”에서 여러 폴더를 한 번에 고르거나, 검증 중 사이드바에서 다른 프로젝트를 선택한다. 각 폴더는 보관하지 않는 독립 `Task`로 검증된다.
- 증상: 완료할 때마다 `selectedProjectID`가 그 폴더로 바뀐다. 느린 첫 검증이 마지막에 끝나면 사용자가 보고 있던 프로젝트를 강제로 전환한다. 늦은 실패도 현재 프로젝트 화면에 전역 오류를 쓴다.
- 확률: 중간. 다중 선택을 명시적으로 허용하며 여러 작업 복사본을 처음 등록할 때 발생하기 쉽다.
- 고치는 방법: 등록 batch/session ID와 Task 컬렉션을 보관하고, 자동 선택은 batch의 명시적 1개 결과 또는 사용자가 이후 선택을 바꾸지 않은 경우에만 적용한다.

## 임시파일 cleanup과 강제 잠금 작업은 UI 상태만 중복 실행을 막는다

- 심각도: 낮음
- 근거: `Sources/SVNMac/ProjectStore+Update.swift:160-167`, `Sources/SVNMac/TemporaryFileCleanupView.swift:58-71`, `Sources/SVNMac/ProjectStore+Locking.swift:335-348`, `Sources/SVNMac/RepositoryLocksView.swift:88-98`, `Sources/SVNMac/ProjectStore+Locking.swift:45-49`, `Sources/SVNMac/LockConfirmation.swift:15-24`
- 재현: 코드 기준 추정
- 트리거: cleanup commit 버튼 또는 force lock/unlock 확인을 빠르게 두 번 전달해 첫 Task가 상태를 바꾸기 전에 두 Task를 만든다. executor는 같은 operation 또는 request가 이미 실행 중인지 거부하지 않는다.
- 증상: 동일 경로에 삭제 예약·commit·force lock/unlock 명령이 두 번 간다. 둘째 명령이 `E155004`나 “이미 잠김/잠기지 않음” 오류로 첫 성공을 덮을 수 있다.
- 확률: 낮음. SwiftUI가 첫 상태 변경 뒤 버튼·alert를 닫지만 빠른 이중 입력 창은 남는다. bulk unlock은 요청을 await 전에 비워 같은 문제가 없다.
- 고치는 방법: 확인 request를 await 전에 원자적으로 소비하고 operation kind별 중복 진입 guard를 executor에 둔다.

## 저장소 탐색 버튼 Task는 화면을 닫아도 svn list를 계속 실행한다

- 심각도: 낮음
- 근거: `Sources/SVNMac/RepositoryBrowserView.swift:44-50`, `Sources/SVNMac/RepositoryBrowserView.swift:62-63`, `Sources/SVNMac/RepositoryBrowserView.swift:76-89`, `Sources/SVNMac/RepositoryBrowserView.swift:211-232`, `Sources/SVNMac/RepositoryBrowserState.swift:175-192`, `Sources/SVNMac/ProjectStore.swift:732-763`
- 재현: 코드 기준 추정
- 트리거: 저장소 탐색에서 “탐색” 또는 “새로고침”을 누르고 로딩 중 닫기를 누른다. 최초 `.task`는 화면 수명에 묶이지만 버튼이 만든 `Task`는 보관·취소하지 않는다.
- 증상: 닫힌 화면의 `svn list` 프로세스와 인증·네트워크 작업이 끝날 때까지 백그라운드에서 계속 돈다. 다시 탐색하면 이전 요청과 새 요청이 동시에 서버 비용을 쓴다.
- 확률: 낮음. 저장소가 느리거나 끊긴 경우에만 사용자가 로딩 중 닫는다.
- 고치는 방법: 탐색 Task를 상태에 보관하고 dismiss/onDisappear에서 취소하거나 모든 실행을 화면 수명에 묶인 `.task(id:)`로 통일한다.

## 확인하지 않은 것

- GUI 이벤트 주입은 하지 않았다. Return 연타·이중 클릭·다중 창 전환이 실제 SwiftUI 이벤트 큐에서 몇 번 전달되는지는 확인하지 않았다.
- cleanup·relocate·삭제·검증 경고의 A→B 오염은 지연 주입 테스트가 없어 코드 기준 추정으로 남겼다.
- 실제 원격 사내 서버의 응답 지연·인증 프롬프트·잠금 정책은 재현하지 않았다. `file://` 저장소만 사용했다.
- 뱃지 폴러와 update의 `E155004`는 18회 중첩에서 재현하지 못했다. 더 큰 작업 복사본, externals, 네트워크 저장소에서는 확인하지 않았다.
- 트리/속성/텍스트 충돌 해결은 request/session ID와 완료 후 재검증을 모두 사용했다. 이번 추적에서 상태 오염 경로를 찾지 못했다.
- 과거 리비전 저장·복원은 `historyRevisionOperation` ID로 중복과 프로젝트 전환을 막았다. 저장 Task 취소는 없지만 사용자가 고른 외부 목적지 저장을 화면 종료 시 중단해야 하는지는 제품 계약을 확인하지 못해 발견으로 올리지 않았다.
