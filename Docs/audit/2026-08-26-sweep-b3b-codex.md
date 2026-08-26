# B3b 전수 감사

## 읽은 파일
- Sources/SVNMac/LockConfirmation.swift — 34줄 — 명시적 잠금의 확인 대화상자와 실행 연결
- Sources/SVNMac/MainWindowActivationView.swift — 72줄 — 주 창 활성화 알림을 SwiftUI 콜백으로 전달
- Sources/SVNMac/PropertyConflictResolutionView.swift — 171줄 — 속성 충돌 내용·복구본·해결 선택 표시
- Sources/SVNMac/RepositoryBrowserView.swift — 256줄 — 저장소 URL·리비전 탐색과 비동기 목록 상태 표시
- Sources/SVNMac/RepositoryDialogs.swift — 915줄 — 인증·인증서·체크아웃·폴더 설정·저장소 이전·파일 작업 대화상자
- Sources/SVNMac/RepositoryLocksView.swift — 159줄 — 저장소 잠금 목록과 일반·강제 해제 동작
- Sources/SVNMac/RepositoryPathNormalizationView.swift — 481줄 — 저장소 경로 정규화 검사·선택·확인·결과 표시
- Sources/SVNMac/RevertConfirmation.swift — 28줄 — 되돌리기 확인 대화상자와 파괴적 버튼 연결
- Sources/SVNMac/SVNLogMessageView.swift — 41줄 — 커밋·잠금 메시지 입력 공통 화면
- Sources/SVNMac/TemporaryFileCleanupView.swift — 96줄 — 저장소 임시 파일 정리 후보 선택과 실행
- Sources/SVNMac/TreeConflictResolutionView.swift — 206줄 — 트리 충돌 영향 경로·복구본·해결 선택 표시
- Sources/SVNMac/UpdatePreviewView.swift — 272줄 — 수신 커밋 미리보기와 업데이트·재시도 진입점
- Sources/SVNMac/WorkingCopyBrowserView.swift — 394줄 — 작업 복사본 트리·검색·파일 문맥 동작
- Sources/SVNMac/WorkingCopyRecoveryView.swift — 122줄 — 유니코드 경로 복구 미리보기·대상 선택·실행
- Sources/SVNMac/WorkingCopySplitBrowserView.swift — 779줄 — 폴더·파일 분할 브라우저와 키보드·문맥 동작

총 15개, 4026줄을 전부 읽었다.

## 발견
### 폴더 설정 저장이 경로와 자격 증명을 원자적으로 처리하지 않는다
- 심각도: 중간
- 근거: Sources/SVNMac/RepositoryDialogs.swift:559,632-675; Sources/SVNMac/ProjectStore.swift:262,965-999,1381-1409
- 재현: 코드 기준 추정
- 트리거: Finder에서 작업 폴더를 옮긴 뒤 「폴더 설정」에서 새 위치와 새 계정을 함께 입력하고 저장한다. 계정 검증 실패 알림에서 「올바른 자격 증명 입력」을 누른 뒤 취소하거나, 검증 통과 뒤 Keychain 쓰기가 실패한다.
- 증상: 폴더 위치는 계정 검증 전에 이미 저장된다. 일반 취소는 `dismiss()`만 호출해 되돌리지 않는다. 「변경 사항 버리고 닫기」도 원래 폴더가 이미 없어 복귀가 실패하면 결과를 확인하지 않고 닫는다. Keychain 쓰기 실패 때도 사용자명·인증서 설정은 `projects`에 먼저 기록되어 `saveCredentials`가 `false`를 반환한 뒤 남는다. 사용자는 저장이 실패했거나 취소했다고 보지만 프로젝트 설정 일부만 바뀐다.
- 확률: 낮음. 폴더 이동과 계정 오류 또는 Keychain 쓰기 실패가 겹쳐야 한다. 다만 비밀번호 교체와 Finder 폴더 이동은 이 팀의 실제 관리 작업이다.
- 고치는 방법: 후보 경로로 작업 복사본·계정을 모두 검증한 뒤 Keychain과 프로젝트 메타데이터를 한 번에 확정하고, 중간 실패 시 모든 필드를 복구한다.

### 경로 복구 프로젝트가 세부 인증서 허용값을 잃는다
- 심각도: 낮음
- 근거: Sources/SVNMac/WorkingCopyRecoveryView.swift:90-98; Sources/SVNMac/ProjectStore+Recovery.swift:59-74; Sources/SVNMac/ProjectStore.swift:45-92
- 재현: 코드 기준 추정
- 트리거: 만료 인증서 등 세부 실패값을 프로젝트에 허용한 상태에서 유니코드 경로 복구를 실행한다.
- 증상: checkout에는 원본의 `allowedServerCertificateFailures`가 전달되어 성공한다. 새 `SVNProject` 생성에는 예전 Bool만 전달되고 세부 Set은 빠진다. 바로 이어지는 새로고침부터 같은 인증서를 다시 거부하거나 승인 화면을 다시 요구한다.
- 확률: 낮음. 경로 복구와 `.expired`·`.notYetValid` 같은 세부 인증서 예외가 함께 있어야 한다.
- 고치는 방법: 복구 프로젝트 생성 시 `allowedServerCertificateFailures: sourceProject.allowedServerCertificateFailures`를 그대로 전달한다.

### 경로 복구 checkout 실패가 대상 폴더를 재사용 불가 상태로 남긴다
- 심각도: 낮음
- 근거: Sources/SVNMac/WorkingCopyRecoveryView.swift:67-98; Sources/SVNMac/ProjectStore+Recovery.swift:55-93; Sources/SVNCore/SVNClient.swift:645-679; Sources/SVNCore/SVNWorkingCopyRecovery.swift:110-118
- 재현: 실제 재현함
- 트리거: 빈 복구 폴더를 선택하고 복구한다. checkout 도중 네트워크가 끊기거나 저장소의 `svn:externals` 대상이 사라져 checkout이 일부 진행된 뒤 실패한다. 같은 폴더로 다시 복구한다.
- 증상: 임시 `file://` 저장소에 존재하지 않는 외부 정의 `^/missing external`을 넣자 checkout이 대상에 `.svn`을 만든 뒤 `svn: E205011: Failure occurred processing one or more externals definitions`로 실패했다. 복구 코드는 이 폴더를 정리하지 않는다. 재시도는 checkout 전에 `recoveryDestinationNotEmpty`가 되어 앱에 `복구 대상 폴더는 비어 있어야 합니다.`만 표시된다. 숨은 `.svn` 때문에 사용자는 같은 폴더에서 계속할 수 없다.
- 확률: 낮음. 복구 자체가 드물고 checkout 부분 실패가 추가로 필요하다. 외부 저장소 장애나 긴 checkout의 네트워크 중단이면 발생한다.
- 고치는 방법: 실패한 대상이 검증된 작업 복사본이면 cleanup·update로 계속할 선택지를, 아니면 검증 후 비우기 선택지를 제공한다.

## 블록 경계
- `RepositoryDialogs.CredentialsView`는 `ProjectStore.relocateProject` → `verifyCredentials` → `saveCredentials`를 한 저장 동작으로 묶는다. 각 메서드는 개별 상태를 즉시 확정하므로 화면의 원자적 저장 설명과 계약이 어긋난다. 첫 발견의 경계다.
- `WorkingCopyRecoveryView` → `ProjectStore+Recovery` → `SVNClient.recoverWorkingCopy` 경계에서 인증서 Set과 실패한 대상 폴더 수명주기가 끊긴다. 둘째·셋째 발견의 경계다. 일반 checkout에는 취소된 폴더 복구 화면이 있으나 이 복구 checkout은 그 경로를 쓰지 않는다.
- `WorkingCopyBrowserView`와 `WorkingCopySplitBrowserView`는 잠금·기록·이동·복사·`svn:needs-lock` 문맥 동작과 상태 배지를 각각 구현한다. 현재 호출 대상과 비활성 조건의 사용자 결과 차이는 확인하지 못했지만, 두 구현의 동등성을 고정하는 계약이나 테스트가 없다.
- 충돌 화면들은 `ProjectStore+Conflicts`의 세션·프로젝트 유효성 검사와 복구본 생성을 사용한다. 현재 속성·트리 해결 모두 요청 ID 검사와 복구본 경로 표시를 연결한다. 배정 화면과 외부 상태 계층 사이 추가 불일치는 확인하지 못했다.
- 경로 정규화 화면은 `SVNCore`가 반환한 원문 경로를 선택 ID로 사용하고 표시만 NFC로 바꾼다. 실행 경로의 UTF-8 바이트 비교와 원문 대상 전달을 확인했다. 배정 화면에서 추가 정규화 손실은 확인하지 못했다.

## 검증 공백
- 폴더 설정 통합 흐름 테스트가 없다. 입력: 유효한 두 번째 작업 복사본 경로 + 틀린 비밀번호 또는 실패하는 `CredentialStoring`. 순서: 위치 변경 성공 → 자격 검증/Keychain 저장 실패 → 취소. 기대값: 원래 경로·사용자명·인증서 Set이 모두 유지되어야 한다.
- 복구 등록 테스트는 원본의 legacy Bool만 확인한다. 입력: `allowsUntrustedServerCertificate: false`, `allowedServerCertificateFailures: [.expired]`. 복구 프로젝트의 Set과 첫 새로고침 전달값이 `.expired`를 유지하는지 확인해야 한다.
- `SVNWorkingCopyRecoveryTests`는 성공과 시작 전 비어 있지 않은 폴더 거부만 다룬다. checkout이 대상 생성 뒤 실패하거나 apply·사후 검증이 실패하는 입력을 넣고 대상 정리 또는 이어받기 요청을 확인해야 한다.
- 작업 복사본 트리·분할 브라우저의 문맥 메뉴 동등성 테스트가 없다. 같은 노드·잠금 상태·선택으로 두 화면의 노출 동작과 비활성 조건을 비교해야 한다.
- 실제 SwiftUI 클릭·시트 닫기·포커스 전환을 구동하는 테스트가 없다. 현재 화면 테스트 상당수는 소스 문자열과 상태 모델만 검사한다.
- `swift test` 실행 결과: 12개 suite, 558개 테스트 전부 통과.

## 확인하지 않은 것
- 실제 Keychain 접근 거부를 발생시키거나 폴더 설정 UI를 클릭해 첫 발견을 재현하지 않았다.
- 만료·아직 유효하지 않은 실제 HTTPS 인증서 서버에서 둘째 발견을 재현하지 않았다.
- 셋째 발견은 실제 `file://` checkout의 부분 실패와 대상 잔존을 확인했다. 앱 UI에서 같은 복구 버튼을 두 번 누르는 과정은 실행하지 않았다.
- 소스 수정, 테스트 추가, 커밋은 하지 않았다.
