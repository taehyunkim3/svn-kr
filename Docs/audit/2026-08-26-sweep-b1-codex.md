# B1 전수 감사

## 읽은 파일
- `Sources/SVNCore/SVNClient.swift` — 2806줄 — SVN 명령 실행, 인증 인자, 작업 복사본 스냅샷, 저장소 경로 정규화, 복구 흐름을 담당한다.
- `Sources/SVNCore/SVNWorkingCopySnapshot.swift` — 483줄 — SVN 상태를 NFC/NFD 경로 정체성 기준으로 묶고 충돌·복구 후보를 계산한다.
- `Sources/SVNCore/SVNPathNormalization.swift` — 326줄 — 로컬 파일 시스템 경로를 원문 UTF-8 바이트 기준으로 NFC 이름으로 바꾼다.
- `Sources/SVNCore/SVNRepositoryPathNormalization.swift` — 195줄 — 저장소 NFD 경로의 정규화 대상, 검증, URL 인코딩을 계산한다.
- `Sources/SVNCore/SVNWorkingCopyRecovery.swift` — 195줄 — 복구 미리보기와 새 작업 복사본으로의 변경 이식을 담당한다.

## 발견
### 한글 사용자명이 Foundation 경계에서 NFD로 바뀌어 인증에 실패한다
- 심각도: 중간
- 근거: `Sources/SVNCore/SVNClient.swift:2492-2497`, `Sources/SVNCore/SVNClient.swift:2535-2557`
- 재현: 실제 재현함
- 트리거: 프로젝트 사용자명에 NFC 한글 계정 `홍길동`을 저장하고 자격 증명 확인, 업데이트, 커밋 등 인증이 필요한 명령을 실행한다.
- 증상: 같은 NFC 사용자명을 셸 argv로 넘기면 임시 `svnserve` 저장소 인증이 성공했다. `Foundation.Process.arguments`로 넘기면 NFD 바이트로 바뀌어 `svn: E170001: Authentication error from server: Username not found`가 발생했다. 경로만 파일 운반으로 보호하고 `--username` 값은 직접 argv에 넣는다.
- 확률: 낮음. 한글 계정을 쓰는 환경에 한정되지만 해당 계정에서는 인증 명령마다 발생한다.
- 고치는 방법: 사용자명도 원문 UTF-8 파일 운반으로 argv에 넣고 NUL을 실행 전에 거부한다.

### 저장소 경로 정규화가 대상 폴더 아래 미버전 문서를 무시한다
- 심각도: 중간
- 근거: `Sources/SVNCore/SVNClient.swift:468-489`
- 재현: 실제 재현함
- 트리거: 저장소와 작업 복사본에 NFD 한글 폴더가 있는 상태에서 그 폴더 아래 새 xlsx·hwp를 만들되 추가하지 않고, 저장소 한글 이름 정리에서 부모 폴더를 선택해 실행한다.
- 증상: 정규화 사전 검사가 `.unversioned`를 제외해 서버 URL 이동을 커밋한다. 실제 `file://` 저장소에서 후속 `svn update`는 종료 코드 0과 함께 `local dir unversioned, incoming dir add upon update` 트리 충돌을 만들었다. 새 문서는 옛 NFD 폴더에 남고 작업 복사본은 정리 전보다 복잡해진다.
- 확률: 낮음. 한글 이름 정리와 미버전 하위 문서가 동시에 있어야 한다. 이 팀은 한글 문서를 Finder에서 먼저 만드는 흐름이 있어 현실적인 조합이다.
- 고치는 방법: 선택 대상 아래 `.unversioned`도 사전 차단하고 먼저 추가·커밋하거나 폴더 밖으로 옮기도록 안내한다.

### BASE 비교 실패가 숨겨져 실제 파일을 누락으로 표시한다
- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNWorkingCopySnapshot.swift:291-292`, `Sources/SVNCore/SVNClient.swift:826-854`
- 재현: 코드 기준 추정
- 트리거: 같은 파일의 버전 경로와 로컬 경로가 NFC/NFD 별칭 관계인 상태에서 pristine 손상, 권한 오류 등으로 `svn cat --revision BASE`가 실패한다.
- 증상: 스냅샷은 미버전 별칭을 먼저 숨긴다. 이후 BASE 비교 오류도 `catch { continue }`로 버려져, 로컬 파일이 존재해도 사용자에게는 버전 파일의 `missing` 상태만 남는다. 사용자는 비교 실패를 알 수 없고 저장소 삭제 조치를 고를 수 있다.
- 확률: 낮음. NFC/NFD 파일 별칭과 BASE 읽기 실패가 겹쳐야 한다.
- 고치는 방법: BASE 비교 실패를 별도 방해 상태로 노출하고 미버전 별칭을 숨기지 말며 삭제·자동 복구를 막는다.

## 블록 경계
- `SVNClient.normalizeRepositoryPaths`는 서버 URL 이동을 먼저 커밋한다. `ProjectStore+RepositoryPathNormalization.swift:147-149`는 결과를 저장한 뒤 `update()`를 호출한다. SVN update는 트리 충돌이 생겨도 종료 코드 0일 수 있다. Core 사전 검사가 로컬 전용 하위 항목을 모두 차단하고, Store 갱신은 반환된 충돌 상태를 성공 결과와 분리해야 한다.
- `SVNClient.run`은 경로에만 원문 UTF-8 운반 계약을 적용한다. `CredentialFieldsGrid`와 `SVNCredentials`는 사용자명을 일반 `String`으로 넘긴다. UI·Core 사이에 사용자명 바이트 보존과 NUL 거부 계약이 없다.
- `SVNWorkingCopySnapshot`은 canonical alias를 숨기고 `SVNClient`가 BASE 내용으로 상태를 확정한다. 뒤 단계가 실패해도 앞 단계의 숨김을 되돌리지 않아 오류가 사용자 상태에서 사라진다.
- `SVNClient.recoverWorkingCopy`는 저장소 HEAD를 새로 checkout한 뒤 원본 작업 복사본의 변경 파일을 덮어쓴다(`Sources/SVNCore/SVNClient.swift:645-678`). 현재 production 화면에는 `beginPathRecovery()` 호출점이 없어 도달하지 않는다. 다시 연결하면 원본 base revision과 HEAD가 다른 파일의 3-way 병합 또는 차단 계약이 먼저 필요하다.
- 로그 메시지 임시 파일 처리가 `normalizeRepositoryPaths`, `commit`, `withSVNLogMessageFile` 세 곳에 중복된다(`Sources/SVNCore/SVNClient.swift:449-457`, `1724-1732`, `2102-2115`). 현재 NUL 거부와 atomic write는 일치한다. 한 구현만 바뀌면 다시 갈라질 수 있다.

## 검증 공백
- 저장소 경로 정규화 통합 테스트는 수정·잠금·NFC 목적지 충돌은 검사하지만 선택한 NFD 폴더 아래 미버전 파일은 없다. `NFD폴더/신규.xlsx`를 만든 뒤 정규화가 서버 커밋 전에 `blockedByLocalChanges`로 끝나는 입력이 필요하다.
- 자격 증명 테스트의 사용자명은 `folder-user`, `user`뿐이다. NFC 한글 사용자명을 fake executable에서 `Data(value.utf8)`로 비교하는 테스트와 사용자명 NUL 거부 테스트가 필요하다.
- canonical 파일 교체 테스트는 BASE 내용이 같거나 다른 성공 경로만 있다. `svn cat --revision BASE`가 비정상 종료할 때 로컬 별칭을 숨기지 않고 조치 가능 상태를 내는 입력이 필요하다.
- 복구 테스트는 source와 checkout 결과를 모두 revision 10으로 가정한다(`Tests/SVNCoreTests/SVNWorkingCopyRecoveryTests.swift:46-50`). source base r10 이후 서버에서 같은 파일이 r11로 바뀐 입력, checkout·복사 중간 실패 뒤 목적지 상태와 재시도 가능성을 검사하지 않는다.
- `SVNPathNormalization` 테스트는 임시 APFS 경로만 다룬다. 실제 HFS+·SMB/NFS에서 원문 바이트 rename, symlink, 중간 항목 실패 후 부분 정규화 상태는 잡지 못한다.
- 기존 테스트 검증: `SVNWorkingCopyRecoveryTests` 2개, `SVNRepositoryPathNormalization` 9개, `SVNPathNormalization` 6개, `SVNWorkingCopySnapshot` 20개, 관련 자격 증명·canonical BASE 비교 3개. 합계 40개 통과.

## 확인하지 않은 것
- 앱 GUI에서 버튼을 눌러 실행하는 흐름은 확인하지 않았다.
- HTTP(S), SASL, Kerberos 서버의 한글 사용자명 동작은 확인하지 않았다. 로컬 password-db `svnserve`만 확인했다.
- HFS+, SMB, NFS 볼륨은 확인하지 않았다.
- production 진입점이 없는 작업 복사본 전체 복구 화면을 강제로 연결해 실행하지 않았다.
- 전체 `swift test`는 실행하지 않았다. 배정 파일 관련 필터 40개만 실행했다.
