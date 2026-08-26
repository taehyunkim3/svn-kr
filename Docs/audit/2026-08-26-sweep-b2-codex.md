# B2 ProjectStore 상태 계층 전수 감사

## 읽은 파일
- Sources/SVNMac/DemoMode.swift — 337줄 — 데모 프로젝트·상태·가짜 SVN 동작을 구성한다.
- Sources/SVNMac/ProjectDependencies.swift — 353줄 — ProjectStore 의존성 프로토콜과 실제 어댑터를 정의한다.
- Sources/SVNMac/ProjectDomainState.swift — 58줄 — 변경·이력·파일 브라우저 도메인 상태를 분리한다.
- Sources/SVNMac/ProjectRecoveryState.swift — 42줄 — 복구 요청과 커밋 중복 제출 게이트를 보관한다.
- Sources/SVNMac/ProjectStore+Cleanup.swift — 228줄 — working copy 정리와 취소된 checkout 복구를 수행한다.
- Sources/SVNMac/ProjectStore+Conflicts.swift — 453줄 — 충돌 분류·준비·해결·사후 검증을 수행한다.
- Sources/SVNMac/ProjectStore+Deletion.swift — 171줄 — 삭제 요청·확인과 missing 항목 처리를 수행한다.
- Sources/SVNMac/ProjectStore+FileActions.swift — 249줄 — 복원·되돌리기·파일 이력·Finder 동작을 수행한다.
- Sources/SVNMac/ProjectStore+FileBrowser.swift — 212줄 — 로컬 파일 트리 조회·캐시·선택 복원을 수행한다.
- Sources/SVNMac/ProjectStore+History.swift — 299줄 — 이력 diff와 과거 리비전 저장·복원을 수행한다.
- Sources/SVNMac/ProjectStore+Ignore.swift — 207줄 — SVN ignore와 `.gitignore` 변환을 수행한다.
- Sources/SVNMac/ProjectStore+Locking.swift — 366줄 — 단건·일괄 잠금과 문서 열기 정책을 수행한다.
- Sources/SVNMac/ProjectStore+Recovery.swift — 96줄 — 한글 경로 별칭 수리와 나란히 복구를 수행한다.
- Sources/SVNMac/ProjectStore+RepositoryMaintenance.swift — 411줄 — relocate·저장소 move/copy·needs-lock을 수행한다.
- Sources/SVNMac/ProjectStore+RepositoryPathNormalization.swift — 208줄 — 저장소 NFD 경로 점검·정규화·부분 실패 표시를 수행한다.
- Sources/SVNMac/ProjectStore+Update.swift — 280줄 — update 미리보기·실행·재시도·임시 파일 정리를 수행한다.
- Sources/SVNMac/ProjectStore.swift — 1845줄 — 프로젝트 수명주기·인증·새로고침·checkout·요약 상태를 총괄한다.

## 발견
### 커밋 이력의 NFD 파일 경로를 NFC로 바꿔 과거 리비전 저장·복원이 실패한다
- 심각도: 중간
- 근거: Sources/SVNMac/ProjectStore+History.swift:112-127, Sources/SVNMac/ProjectStore+History.swift:260-274
- 재현: 실제 재현함
- 트리거: 저장소 한글 이름 정리를 하지 않은 working copy에서 NFD 이름 `보고서.xlsx`의 커밋 이력을 열고 과거 리비전 저장 또는 복원을 누른다.
- 증상: 경로가 `보고서.xlsx`로 강제 변환된다. 임시 `file://` 저장소에서 NFD 파일을 커밋한 뒤 같은 NFC 경로로 `svn cat -r 1`을 실행하면 `svn: E155010: The node '.../보고서.xlsx' was not found.`가 발생했다. 원래 NFD 바이트 경로는 `historical bytes`를 반환했다.
- 확률: 중간. macOS에서 만든 한글 파일과 정규화 기능 도입 전 저장소가 이 팀의 주요 입력이다.
- 고치는 방법: 저장소 루트 포함 여부만 정규화 비교하고, SVN에 넘길 하위 경로는 원래 UTF-8 바이트를 보존한다.

### Keychain 저장 실패 전에 프로젝트 인증 설정이 먼저 영구 저장된다
- 심각도: 중간
- 근거: Sources/SVNMac/ProjectStore.swift:1387-1409, Sources/SVNMac/ProjectStore.swift:1438-1458
- 재현: 코드 기준 추정
- 트리거: 설정에서 사용자 이름·인증서 허용 설정·새 비밀번호를 바꾸고 저장한다. 서버 검증은 성공하지만 Keychain 쓰기가 거부된다.
- 증상: 화면은 저장 실패로 남지만 사용자 이름과 인증서 허용 설정은 이미 프로젝트 목록에 저장된다. 기존 비밀번호 또는 비밀번호 없음과 새 사용자 이름이 조합되어 다음 SVN 명령이 다시 실패할 수 있다. 인증 재입력 경로도 사용자 이름을 먼저 바꾼 뒤 Keychain 실패 시 되돌리지 않는다.
- 확률: 낮음. Keychain 거부는 흔하지 않지만 macOS 권한 변경·잠금·손상 때 발생한다.
- 고치는 방법: Keychain 쓰기를 먼저 끝낸 뒤 프로젝트 메타데이터를 한 번에 교체하거나, 실패 시 이전 값을 복구한다.

### 서버 인증서 예외 허용 후 실패했던 작업을 재개하지 않는다
- 심각도: 낮음
- 근거: Sources/SVNMac/ProjectStore.swift:1496-1508, Sources/SVNMac/ProjectStore.swift:1573-1595
- 재현: 코드 기준 추정
- 트리거: update·commit·이력 새로고침 중 만료 또는 신뢰되지 않은 인증서 오류가 나면 프로젝트에 예외 허용을 누른다.
- 증상: 예외는 저장되고 시트는 닫히지만 실패했던 작업은 끝난 상태다. 안내도 작업을 다시 실행하라고 말하지 않는다. 같은 요청의 Keychain 재시도는 `resume`을 호출하므로 인증서 경로와 동작이 갈린다.
- 확률: 낮음. 인증서 장애 때만 발생하지만 허용을 선택하면 매번 발생한다.
- 고치는 방법: 예외 저장 후 요청 유효성을 확인하고 `resume(request)`를 호출하거나 명시적 재시도 동작을 제공한다.

### 속성만 충돌한 파일이 프로젝트 사이드바에서 일반 변경으로 표시된다
- 심각도: 낮음
- 근거: Sources/SVNMac/ProjectStore.swift:1699-1707
- 재현: 코드 기준 추정
- 트리거: 두 사용자가 `svn:needs-lock` 또는 ignore 같은 속성을 다르게 바꿔 `item=normal`, `props=conflicted` 상태를 만든 뒤 프로젝트 사이드바를 본다.
- 증상: `conflictCount`가 0이라 빨간 충돌 배지가 없고 주황 변경 배지만 보인다. 변경 화면은 같은 항목을 충돌로 처리해 두 화면의 의미가 다르다.
- 확률: 낮음. 속성 충돌 빈도는 텍스트 충돌보다 낮지만 공유 문서의 `svn:needs-lock` 운영에서 가능하다.
- 고치는 방법: `item == .conflicted || propertyState == .conflicted`를 같은 충돌 집계 규칙으로 사용한다.

### 취소된 checkout 복구 검사가 다음 checkout의 복구 요청을 덮을 수 있다
- 심각도: 낮음
- 근거: Sources/SVNMac/ProjectStore.swift:749-762, Sources/SVNMac/ProjectStore.swift:833-856, Sources/SVNMac/ProjectStore+Cleanup.swift:94-127
- 재현: 코드 기준 추정
- 트리거: checkout A를 취소하고 working copy 검증이 끝나기 전에 checkout B를 즉시 시작·취소한다.
- 증상: A의 분리된 검증이 늦게 끝나도 취소 여부나 checkout 세션을 확인하지 않고 단일 `canceledCheckoutRecoveryRequest`와 세션 비밀번호를 쓴다. B 뒤에 A 복구 시트가 나타나거나 B의 복구 요청을 A가 덮을 수 있다.
- 확률: 낮음. 취소 직후 재시도와 느린 디스크·네트워크 검증이 겹쳐야 한다. 복구 실행에는 별도 확인이 있어 자동 데이터 삭제까지 이어지지는 않는다.
- 고치는 방법: checkout 세션 ID를 복구 준비에 전달하고 detached await 뒤 `!Task.isCancelled`와 현재 세션 일치를 확인한다.

## 블록 경계
- `ProjectStore+History`는 저장소 경로를 로컬 상대 경로로 바꾼다. `SVNCore/SVNClient.resolveWorkingCopyCommandPath`는 프로젝트가 working copy 루트면 이 상대 경로를 그대로 사용한다. 앞단의 NFC 변환을 뒤에서 원래 NFD 바이트로 되돌리지 못한다.
- `ProjectStore.saveCredentials`의 외부 화면 `RepositoryDialogs`는 “확인 전에는 아무것도 바꾸지 않는다”와 저장 성공 후 닫힘을 계약으로 둔다. Keychain 실패 전에 `projects`가 저장되어 이 계약과 어긋난다.
- `ProjectStore.allowServerCertificateFailure`는 `SVNAuthenticationRequest.action`을 보존하지만 사용하지 않는다. 같은 요청을 다루는 Keychain 경로와 외부 인증서 시트의 완료 의미가 다르다.
- `ProjectStore.updateLocalSummary`, `ChangesView`, `ProjectStatusBadges`가 충돌 판정을 나눠 가진다. 변경 화면만 속성 충돌을 포함해 사이드바 배지와 갈라졌다.
- checkout 취소는 `SVNClient` 프로세스 취소 뒤 `ProjectStore+Cleanup`의 별도 working copy 검증으로 넘어간다. 로그에는 세션 ID가 있으나 복구 요청에는 없어 다음 checkout과 경합한다.
- `ConflictFileService`, `RevisionFileService`, `TemporaryFilePolicy`, `LockWorkflow`, `WorkingCopyFileService`, 저장소 경로 정규화 API의 호출 경계도 확인했다. 이전 감사에서 다룬 항목 외 새 계약 불일치는 찾지 못했다.

## 검증 공백
- 전체 `swift test`: 558개 테스트, 12개 suite, 통과. 아래 입력은 기존 테스트에 없다.
- 이력 동작 테스트는 NFD 저장소 경로를 NFC 상대 경로로 바꾸는 값만 단언한다. 실제 NFD `file://` 저장소에서 `saveHistoryRevision`과 `confirmHistoryRevisionRestore`를 실행해야 한다.
- 자격 증명 테스트는 서버 검증 실패 시 무변경과 checkout 후 Keychain 실패를 다룬다. 서버 검증 성공 뒤 `StubCredentialStore(setError:)`로 `saveCredentials`·`useCredentials`의 사용자 이름, 인증서 허용 집합, 영속 저장값을 확인해야 한다.
- 인증서 테스트는 예외 집합 저장만 확인한다. `.update`, `.commit`, `.refreshHistory` 요청 각각을 허용한 뒤 해당 client 호출 횟수가 1회 증가하는지 확인해야 한다.
- 속성 충돌 테스트는 파싱·선택·해결을 다룬다. `item=.normal`, `propertyState=.conflicted` 하나를 `updateLocalSummary`에 넣어 `conflictCount == 1`을 확인해야 한다.
- checkout 취소 테스트는 한 요청만 실행한다. A의 `validateWorkingCopy`를 지연시키고 B를 시작·취소한 뒤 최신 세션의 복구 요청만 남는지 확인해야 한다.

## 확인하지 않은 것
- 실제 Keychain 쓰기 거부와 실제 HTTPS 인증서 장애는 재현하지 않았다. 해당 두 발견은 코드 기준 추정이다.
- GUI를 실행해 사이드바 배지와 인증 시트를 눈으로 확인하지 않았다.
- NFD 이력 실패는 로컬 APFS의 임시 `file://` 저장소에서 재현했다. SMB·HFS+ 볼륨은 확인하지 않았다.
- 소스와 테스트는 수정하지 않았다. 새 테스트도 추가하지 않았다.
