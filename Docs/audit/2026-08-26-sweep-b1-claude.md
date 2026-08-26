# B1 블록(SVNCore 명령 실행·스냅샷·경로 정규화·복구) 전수 감사

기준일: 2026-08-26
기준 실행 파일: `/opt/homebrew/bin/svn` 1.14.5, APFS(대소문자 무시·정규화 무시 확인), `file://` 저장소
실행한 테스트: `swift test --filter 'Recovery|PathNormalization|SnapshotTests'` — 67개 통과(3 suite). 소스는 수정하지 않았다.

## 읽은 파일

- `Sources/SVNCore/SVNClient.swift` — 2806줄 — 모든 svn 하위 명령의 실행 진입점. 원문 UTF-8 경로 운반, 커밋/삭제/잠금/정규화/복구 절차, 오류 분류.
- `Sources/SVNCore/SVNWorkingCopySnapshot.swift` — 483줄 — `svn status --verbose --no-ignore --xml`을 바이트 기준 정체성으로 해석해 표시 목록·충돌·별칭 수리 대상·대치 후보를 만든다.
- `Sources/SVNCore/SVNPathNormalization.swift` — 326줄 — 커밋 직전 새 경로를 디스크에서 `rename(2)`로 NFC로 바꾸고, 실패한 경로를 보고한다.
- `Sources/SVNCore/SVNRepositoryPathNormalization.swift` — 195줄 — 저장소(서버) 쪽 NFD 경로 대상 선정, 유효성 검사, URL 조립, 커밋 리비전 파싱.
- `Sources/SVNCore/SVNWorkingCopyRecovery.swift` — 195줄 — 손상된 작업 복사본의 변경을 새 체크아웃으로 옮기는 미리보기와 복사 실행.

참고로 읽은 외부 파일(발견 보고 대상 아님): `Sources/SVNCore/Models.swift`(상태 enum), `Sources/SVNMac/ProjectStore+Recovery.swift`, `ProjectStore+RepositoryPathNormalization.swift`, `ProjectStore+Update.swift`, `ProjectStore+Deletion.swift`, `SVNErrorLocalization.swift`, `ChangesView.swift`, `Docs/SVNArgumentRules.md`, `Docs/audit/2026-08-25-audit-ui.md`, `-audit-concurrency.md`, `-audit-state.md`.

**중요한 전제**: 경로 복구 기능(`recoveryPreview`/`recoverWorkingCopy`)은 현재 UI 진입점이 없다. `beginPathRecovery()`를 부르는 화면이 Sources에 없고 `ChangesViewPerformanceTests`가 "부르지 않음"을 고정한다. 이 사실 자체는 `Docs/audit/2026-08-25-audit-ui.md:122`에 이미 보고됐으므로 다시 발견으로 올리지 않는다. 다만 그 보고서의 수정 방향이 "수리 불가면 `beginPathRecovery()`를 부른다"이므로, 아래 복구 관련 결함은 진입점을 연결하는 순간 그대로 사용자 피해가 된다. 각 항목의 `확률`에 이 사실을 명시했다.

## 발견

### 복구는 HEAD로 새로 체크아웃한 뒤 로컬 파일을 덮어써서 다른 사람의 커밋을 조용히 지운다

- 심각도: 높음
- 근거: `Sources/SVNCore/SVNClient.swift:660-668`(리비전 없이 `checkout` 후 `apply`), `Sources/SVNCore/SVNWorkingCopyRecovery.swift:134-136`(수정 파일을 그대로 복사), `Sources/SVNCore/SVNClient.swift:56-77`(`checkout`에 revision 인자 자체가 없음)
- 재현: 실제 재현함(svn 수준). `svnadmin create` → wc1 체크아웃 후 `보고서.txt` r1 커밋 → wc2에서 같은 파일에 줄 추가해 r2 커밋 → wc1은 r1 상태에서 로컬 수정 → 새 폴더에 HEAD로 체크아웃하고 wc1의 파일을 그대로 복사 → 커밋. 서버 최종 내용에서 r2에서 추가한 줄이 사라졌다. 대조로 wc1에서 직접 커밋하면 `svn: E155011: File '…/보고서.txt' is out of date`로 막힌다. SVNClient를 거친 전체 흐름은 코드 기준 추정.
- 트리거: 작업 복사본이 손상돼 update가 안 되는 상태에서 경로 복구를 실행한다. 손상 상태로 방치된 동안 동료가 같은 파일을 커밋했다.
- 증상: 복구는 성공으로 끝나고 "경로 복구 완료" 안내가 뜬다. 이후 커밋하면 out-of-date 검사가 걸리지 않고 통과한다. 동료가 그 사이 올린 내용이 경고 없이 사라진다. 충돌 표시도 없다.
- 확률: 진입점이 없는 동안은 0. 연결되면 중간. 복구가 필요한 상태는 대개 며칠 방치된 작업 복사본이고, 그동안 HEAD가 앞서 나가는 것이 정상이다. xlsx는 잠금으로 일부 보호되지만 txt·hwp·잠금 없는 문서는 그대로 노출된다.
- 고치는 방법: 복구 체크아웃을 `snapshot.revision.minimum`(원본 BASE)으로 하고, 파일을 옮긴 뒤 사용자가 직접 update해 충돌을 보게 한다.

### 속성만 바뀐 파일은 복구 미리보기에 세지 않고, 복사도 하지 않으면서 "복구했다"고 보고한다

- 심각도: 중간
- 근거: `Sources/SVNCore/SVNWorkingCopyRecovery.swift:69-101`(매핑 생성), `:137-139`(`.unknown`은 아무것도 하지 않고 `break`), `:20-30`(세 카운트 모두 `.unknown`을 세지 않음), `Sources/SVNCore/SVNClient.swift:677`(`migratedPaths`에는 포함), `Sources/SVNCore/Models.swift:350-355`(`isSelectableForCommit`가 통과시킴)
- 재현: 코드 기준 추정. `svn status`의 `item="normal" props="modified"`는 `SVNStatusKind(rawValue:"normal")` = `.unknown("normal")`로 들어오고(`Models.swift`의 init 기본 분기), `SVNWorkingCopySnapshot.visibleStatuses`가 속성 변경 때문에 목록에 남긴다.
- 트리거: 파일에 `svn:needs-lock`이나 `svn:mime-type`만 바꿔 놓은 상태(내용 변경 없음)에서 경로 복구를 실행한다. `obstructed`, `incomplete`, switched 항목도 같은 경로를 탄다.
- 증상: 미리보기의 수정/새로 추가/누락 숫자 어디에도 그 파일이 안 나온다. 복구 후 속성 변경은 사라졌는데 `migratedPaths`에는 "옮겼다"고 들어가 있다. 사용자는 잃은 것을 알 방법이 없다.
- 확률: 진입점 연결 전에는 0. 연결되면 중간. 이 팀은 `svn:needs-lock`을 문서 잠금 흐름에서 실제로 쓴다.
- 고치는 방법: 속성 변경·`obstructed`·`incomplete`·switched 항목은 매핑이 아니라 `blockingPaths`로 보내고(`normalizeRepositoryPaths`가 이미 그렇게 한다), 복사하지 않은 경로는 `migratedPaths`에서 뺀다.

### 복구 대상 폴더를 원본 작업 폴더 안에 만들면 저장소 전체가 중첩 복사된다

- 심각도: 중간
- 근거: `Sources/SVNCore/SVNClient.swift:652-668`(목적지가 원본 하위인지 검사 없음), `Sources/SVNCore/SVNWorkingCopyRecovery.swift:110-119`(빈 폴더면 통과·생성), `:69-101`(미등록 폴더도 매핑 대상), `:155-167`(디렉터리 재귀 복사), `Sources/SVNMac/ProjectStore+Recovery.swift:46-49`(이미 등록된 경로만 거부)
- 재현: 실제 재현함 — 작업 복사본 안에 빈 폴더 `복구`를 만들면 `svn status --verbose --no-ignore --xml`이 `item="unversioned"`로 보고한다(즉 복구 매핑 대상이 된다). 중첩 복사 자체는 코드 기준 추정.
- 트리거: 복구 대화상자에서 "복구할 빈 폴더 선택"으로 현재 프로젝트 폴더 하위에 새 폴더를 만들어 지정한다.
- 증상: 그 폴더에 저장소를 체크아웃한 뒤, 같은 폴더가 원본의 미등록 항목으로 잡혀 있어 방금 만든 체크아웃 전체가 자기 안으로 한 번 더 복사된다. 새 프로젝트에 정체불명의 미등록 파일이 저장소 크기만큼 생기고, 원본 폴더도 그만큼 커진다. "원본 작업 폴더는 그대로 유지했습니다" 안내는 사실이 아니게 된다.
- 확률: 진입점 연결 전에는 0. 연결되면 중간. 폴더 선택 창이 현재 프로젝트에서 열리면 그 안에 새 폴더를 만드는 것이 가장 자연스러운 조작이다.
- 고치는 방법: 목적지가 원본 경로와 같거나 그 하위/상위면 시작 전에 거부한다.

### 읽기 API인 `workingCopySnapshot`이 자동으로 `revert`를 실행하고, actor가 명령을 직렬화한다는 주석 보증은 사실이 아니다

- 심각도: 중간
- 근거: `Sources/SVNCore/SVNClient.swift:709-722`(스냅샷 조회가 정리 단계를 포함), `:732-760`(`revert --depth infinity` 실행, 실패는 삼키고 재조회), `:15-19`(주석: "actor로 선언해 update와 commit 같은 명령이 동시에 작업 복사본을 변경하지 않도록 보장합니다")
- 재현: 코드 기준 추정. actor는 `await` 지점마다 재진입을 허용하므로 `commit`의 다단계 절차(스냅샷 → `add` → `commit`) 중간에 다른 메서드가 들어올 수 있다. 동시 svn 명령이 `E155004`를 만드는 것은 `Docs/audit/2026-08-25-audit-concurrency.md`에서 이미 재현됐다.
- 트리거: 추가 파일이 있는 커밋을 진행하는 동안 화면 새로고침이 겹친다. 새로고침은 읽기 작업으로 취급돼 커밋 진행 중에도 막히지 않는다.
- 증상: 새로고침 쪽 `svn revert`와 커밋 쪽 `svn add`/`svn commit`이 겹쳐 한쪽이 `svn: E155004: Working copy '…' locked.`로 실패한다. 사용자는 커밋 실패와 "정리(cleanup) 필요" 안내를 함께 받는다. 정리 대상 판정과 실제 revert 사이에 상태가 바뀌면 예약된 추가가 취소될 수 있다.
- 확률: 낮음~중간. 커밋이 느릴 때(원격 저장소, 큰 xlsx) 자동 새로고침과 겹칠 시간이 길어진다.
- 고치는 방법: 정리 revert를 스냅샷 조회에서 떼어내 명시적 쓰기 API로 옮기고, 주석의 보증을 실제 직렬화(작업 복사본별 큐)로 구현하거나 주석을 사실에 맞게 고친다.

### 저장소 경로 정규화가 속성만 바뀐 로컬 변경을 차단 대상에서 빠뜨린다

- 심각도: 중간
- 근거: `Sources/SVNCore/SVNClient.swift:469-489`(`case .unversioned, .ignored, .unknown: return nil`), `Sources/SVNCore/Models.swift:344-357`+`SVNStatusKind.init`(속성 전용 변경은 `.unknown("normal")`), `Sources/SVNCore/SVNWorkingCopySnapshot.swift:275-278`(속성 변경 항목을 목록에 남김)
- 재현: 코드 기준 추정
- 트리거: NFD 이름 파일에 `svn:needs-lock`만 설정해 커밋하지 않은 상태에서 "저장소 경로 정규화"를 실행한다. switched 항목도 같다.
- 증상: 로컬 변경 차단 검사를 통과해 서버에서 그 경로가 이동된다. 뒤이은 `update`에서 그 파일은 "로컬 편집 / 들어오는 삭제" 트리 충돌이 되거나 속성 변경이 사라진다. 차단 메시지("로컬 변경 때문에 정규화할 수 없습니다")를 미리 볼 기회가 없다.
- 확률: 낮음. 속성만 바꿔 놓고 커밋 전에 정규화를 돌리는 조합이 필요하다. 다만 이 팀은 `svn:needs-lock`을 실제로 쓴다.
- 고치는 방법: 차단 판정을 `item` 대신 "커밋할 것이 있는가"(`propertyState != .none`, `isSwitched` 포함)로 바꾼다.

### 복구가 중간에 실패하면 앱이 만든 폴더가 남아 재시도가 막힌다

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNWorkingCopyRecovery.swift:110-119`(없으면 폴더를 만든다), `Sources/SVNCore/SVNClient.swift:654-668`(체크아웃 성공 후 `apply` 실패 시 정리 없음), `Sources/SVNMac/ProjectStore+Recovery.swift:90-94`(오류만 표시하고 프로젝트 등록 안 함)
- 재현: 코드 기준 추정
- 트리거: 복구 중 디스크 공간 부족·권한 오류·네트워크 끊김으로 `apply`가 중간에 실패한다. 그 뒤 같은 폴더로 다시 시도한다.
- 증상: 두 번째 시도는 "복구 대상 폴더는 비어 있어야 합니다."로 즉시 실패한다. 그 폴더는 앱이 만들고 앱이 채운 것이며, 어디까지 복사됐는지 목록도 없다. 터미널을 안 쓰는 사용자는 Finder에서 지워야 한다는 것을 안내받지 못한다.
- 확률: 진입점 연결 전에는 0. 연결되면 낮음.
- 고치는 방법: 실패 시 앱이 만든 목적지를 되돌리거나, 부분 복구 사실과 "이 폴더를 지우고 다시 시도하세요"를 오류에 함께 담는다.

### 삭제 예약은 복구 뒤 "누락"으로 격하되고, 사용자는 다시 예약해야 한다

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNWorkingCopyRecovery.swift:129-133`(삭제 예약을 디스크 삭제로만 재현), `Sources/SVNCore/SVNClient.swift:1775-1780`(누락 경로가 있으면 커밋 거부)
- 재현: 코드 기준 추정
- 트리거: 삭제 예약한 파일이 있는 상태에서 복구한다.
- 증상: 새 작업 폴더에서 그 파일은 "삭제 예약"이 아니라 "누락"으로 표시된다. 그대로 커밋하면 `unresolvedMissingPaths` 오류가 난다. 삭제 예약 대화상자를 다시 거쳐야 한다. 같은 이유로 `added`는 미등록으로 격하된다.
- 확률: 진입점 연결 전에는 0. 연결되면 중간(삭제 예약은 흔하다). 앱에 누락 항목 삭제 예약 UI가 있어 복구는 가능하다.
- 고치는 방법: 복구 뒤 삭제/추가 예약을 `svn delete`/`svn add`로 다시 세우거나, 미리보기에서 "예약은 다시 해야 합니다"를 명시한다.

### NFC 정규화 실패 목록을 아무도 읽지 않는다

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNPathNormalization.swift:4-8`(`unnormalizedPaths`), `:28-31`, `:201-209`, `:245-256`(실패 보고 지점들), `Sources/SVNCore/SVNClient.swift:1786-1794`(결과에서 `didRename`만 읽는다). Sources 전체에서 `unnormalizedPaths` 소비자는 없다(테스트에만 있다).
- 재현: 실제 재현함(정규화 동작 자체). APFS에서 `rename(NFD→NFC)`는 저장 이름을 NFC로 바꾼다(바이트로 확인). 실패 경로는 HFS+/SMB나 권한 오류가 필요해 재현하지 않았다.
- 트리거: 작업 복사본이 HFS+ USB·네트워크 볼륨에 있거나 상위 경로가 심볼릭 링크여서 rename이 실패한 상태에서 한글 이름 새 파일을 커밋한다.
- 증상: 커밋은 성공하지만 저장소에 NFD 이름으로 올라간다. Windows·웹에서 다른 이름으로 보이고, 나중에 같은 이름을 NFC로 추가하면 "유니코드 경로 충돌"이 된다. 커밋 시점에는 아무 표시가 없다.
- 확률: 낮음. 볼륨 단위 문제는 `SVNVolumeNormalizationProbe` 배너가 따로 경고하므로 대부분 덮인다. 남는 건 경로별 실패다.
- 고치는 방법: `unnormalizedPaths`를 커밋 결과 경고로 올려 어느 파일이 NFD로 올라갔는지 보여준다. 쓰지 않을 것이면 계산 자체를 지운다.

### 인자 오류는 지역화되지 않고 영어 원문으로 노출된다

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNClient.swift:2094-2100`, `:449-451`, `:1721-1726`, `:2218-2220`(`SVNClientArgumentError` 발생), `Sources/SVNCore/SVNAdditionalModels.swift:3-17`(영어 `errorDescription`), `Sources/SVNMac/ProjectStore.swift:1637-1640`(`SVNError`만 지역화하고 나머지는 `localizedDescription`)
- 재현: 코드 기준 추정
- 트리거: 속성 대화상자에서 이름을 비우거나 `-`로 시작하는 이름으로 속성을 추가한다.
- 증상: `Unsupported SVN property name: -x` 같은 영어 문장이 그대로 뜬다. 한국어 사무직 사용자에게 다음 조치가 전달되지 않는다.
- 확률: 낮음. 속성 이름을 직접 입력하는 화면에서만 닿는다.
- 고치는 방법: `SVNClientArgumentError`도 `SVNErrorLocalization`에서 분기해 한국어 안내를 준다.

### `normalizedCommitPaths`만 바이트 대신 String 동등성을 쓴다

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNClient.swift:2055-2070`(`Set<String>`과 `contains`), 대조: 같은 파일의 다른 모든 경로 비교는 `SVNPathIdentity`/`Data(utf8)`를 쓴다(`:1769-1783`, `:2040-2048`)
- 재현: 실제 재현함(동작 자체). Swift에서 `Set(["보고서.xlsx" NFC, 같은 이름 NFD]).count == 1`이다(바이트는 다름). 사용자 피해로 이어지는 경로는 재현하지 못했다 — 이 볼륨의 APFS는 한 폴더에 두 정규화 형태를 동시에 두지 못하고(둘째 생성이 첫째를 덮었다), `resolvedPath(for:)`가 두 형태를 같은 원문 경로로 접어주기 때문이다.
- 트리거: 커밋 대상 목록에 정규화만 다른 두 원문 경로가 동시에 들어오는 경우.
- 증상: 한쪽이 조용히 목록에서 빠져 커밋되지 않는다(또는 롤백 대상에서 빠진다). 오류는 없다.
- 확률: 매우 낮음. 현재 호출 경로에서는 재현되지 않는다. 정규화 무시가 아닌 볼륨(HFS+ 외부 디스크, 일부 SMB)에서 전제가 깨질 수 있다.
- 고치는 방법: `normalizedCommitPaths`도 `SVNPathIdentity` 기준으로 중복 제거·상위 경로 판정을 한다.

### 죽은 코드

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNClient.swift:2422-2428`(`isLockConflictError` 두 오버로드 — Sources 호출자 없음, 테스트만), `:2446-2452`(`isWorkingCopyFormatTooOldError` — 같음), `Sources/SVNCore/SVNWorkingCopySnapshot.swift:22-42`의 `rawPaths`(프로덕션 소비자 없음), `Sources/SVNCore/SVNWorkingCopyRecovery.swift:20-30`의 세 카운트(죽은 복구 시트에서만 사용)
- 재현: 실제 재현함(grep 기준 호출자 없음)
- 트리거: 작업 복사본 형식이 오래된 상태(`E155036`)로 명령을 실행한다. 잠금 충돌(`E195022`/`E160037`)이 난다.
- 증상: 분류 함수가 있는데도 두 상황 모두 일반 명령 실패로만 표시된다. "svn 버전 업그레이드가 필요합니다" 같은 구체 안내가 나오지 않는다.
- 확률: 낮음. `E155036`은 다른 도구로 만든 오래된 작업 복사본을 등록할 때 나온다.
- 고치는 방법: 두 분류 함수를 `SVNErrorLocalization.failureCode`에 연결하거나, 쓰지 않을 것이면 함수와 테스트를 함께 지운다.

### 같은 일을 하는 코드가 두 벌 이상 있다

- 심각도: 낮음
- 근거:
  - 로그 메시지 임시 파일 작성 3벌: `Sources/SVNCore/SVNClient.swift:452-457`, `:1727-1732`, `:2109-2114`(`withSVNLogMessageFile`)
  - 경로 해석 2벌: `Sources/SVNCore/SVNWorkingCopySnapshot.swift:188-205`(`resolvedPath(for:)`)와 `:333-348`(`resolveNewPath`)
  - 스냅샷 조회 2벌: `Sources/SVNCore/SVNClient.swift:693-707`(`workingCopyEntries`)와 `:709-722`(`workingCopySnapshot`) — 같은 `svn status`를 읽지만 전자는 누락 추가 정리와 노드 종류 주석을 건너뛴다
  - `svn list` 운반 2벌: `:391`, `:511`은 저장소 URL을 `Process.arguments`에 직접 넣고 `:421`은 원문 파일 운반을 쓴다. `Docs/SVNArgumentRules.md`의 `list` 규칙은 원문 운반이다
  - `pathComponents` 3벌: `:1528`, `:2090`, `SVNWorkingCopySnapshot.swift:475`
- 재현: 실제 재현함(코드 대조)
- 트리거: 한쪽만 고치는 다음 수정.
- 증상: 지금은 동작이 같다. NUL 검사·경로 해석·정리 시점 중 한쪽만 바뀌면 커밋 목록과 파일 브라우저가 같은 작업 복사본을 다르게 표시하거나, 한 명령만 NFD 경로를 잃는다.
- 확률: 낮음(현재 사용자 피해 없음). 이 세션 결함 다수가 이 종류의 갈라짐에서 나왔다.
- 고치는 방법: 로그 메시지는 `withSVNLogMessageFile`로 통일, 경로 해석은 한 함수로, `workingCopyEntries`는 `workingCopySnapshot`을 재사용, `svn list` URL도 원문 운반으로 통일한다.

## 블록 경계

- **`SVNClient` → `SVNMac` 오류 타입 계약**: `SVNClient`는 `SVNError` 외에 `SVNClientArgumentError`(`:449`, `:1722`, `:2098`, `:2219`, `:2301`)와 `SVNRepositoryPathNormalizationError`를 던진다. `ProjectStore.localizedError`는 `SVNError`와 `ConflictFileError`만 분기하므로 첫 타입은 영어로 새어 나간다(발견 항목 참조). 세 번째 타입은 `ProjectStore+RepositoryPathNormalization`이 따로 처리해 정상.
- **좌표계 계약(정규화 대상 ↔ 로컬 상태)**: `SVNClient.normalizeRepositoryPaths`는 `entry.path`(등록 프로젝트 상대)와 `target.repositoryPath`(`svn list <프로젝트 URL>` 상대)를 같은 공간으로 비교한다(`:469-507`). 이 계약은 `SVNXMLParser.repositoryListEntries`가 조회한 URL 기준 상대 경로를 준다는 가정에 전부 의존한다. 파서가 저장소 루트 기준 절대 경로로 바뀌면 차단 검사와 skip 판정이 조용히 전부 빗나간다(오류 없이 통과). 파서 쪽에 이 계약을 고정하는 주석이나 테스트가 없다.
- **커밋 롤백 ↔ 디스크 rename**: `SVNClient.commit`의 실패 롤백(`:1868-1879`)은 `svn add`만 되돌린다. 그 앞에서 `SVNPathNormalization`이 디스크에서 수행한 NFD→NFC `rename(2)`는 되돌리지 않는다. 커밋이 실패해도 사용자 파일 이름은 이미 바뀌어 있다(Finder에서는 같아 보인다). 의도된 것으로 보이지만 어디에도 적혀 있지 않다.
- **정규화 실패 판단이 두 곳**: 볼륨 단위는 `SVNVolumeNormalizationProbe`(ProjectStore 배너), 경로 단위는 `SVNPathNormalizationResult.unnormalizedPaths`(소비자 없음). 같은 사실을 두 경로로 판단하는데 한쪽만 화면에 닿는다.
- **읽기/쓰기 계약**: `workingCopySnapshot`은 이름과 사용처(새로고침, 미리보기, 검증)가 모두 읽기인데 내부에서 `revert`를 실행한다(`:740-757`). `ProjectStore`는 새로고침을 쓰기 작업으로 막지 않으므로 커밋·update와 겹칠 수 있다.
- **`ProjectStore+Recovery` ↔ `SVNWorkingCopyRecovery`**: 목적지 안전성 검사가 양쪽에 나뉘어 있고 둘 다 "원본 하위인가"를 보지 않는다. UI는 "이미 등록된 폴더"만 막고(`:46-49`), 코어는 "비어 있는가"만 본다(`:110-119`).
- **`svn` 출력 언어 의존**: `SVNRepositoryPathNormalization.committedRevision`(`:160-170`)은 영어 `Committed revision N.`을 정규식으로 읽는다. `SVNClient.run`이 `LANG`/`LC_ALL`을 `en_US.UTF-8`로 고정하기 때문에 성립한다(`:2475-2477`). 두 파일에 걸친 암묵 계약이고 이를 고정하는 테스트가 없다.

## 검증 공백

- **HFS+/정규화 미보존 볼륨의 커밋 경로**: `SVNPathNormalization`의 실패 분기(`:201-209`, `:245-256`)와 `SVNClient.commit`의 "rename 안 됨" 분기는 실 볼륨 테스트가 없다. `SVNUnicodeCommitIntegrationTests`의 4개는 모두 APFS에서 `didRename == true` 쪽만 지난다. `SVNVolumeNormalizationProbeTests`가 이미 `hdiutil`로 HFS+ 디스크 이미지를 만들므로, 같은 방식으로 HFS+ 볼륨 작업 복사본에 한글 새 파일을 커밋해 `unnormalizedPaths`가 채워지는지 확인했어야 잡혔다.
- **복구 미리보기 입력 다양성**: `SVNWorkingCopyRecoveryTests`의 2개는 가짜 `svn` 스크립트로 modified/unversioned/missing/별칭만 다룬다. 넣었어야 할 입력: `item="normal" props="modified"`(속성 전용), `item="obstructed"`, `item="incomplete"`, `wc-status`에 `switched`, 심볼릭 링크, 목적지가 원본 하위인 경우, 체크아웃 내용이 원본 BASE보다 앞선 경우(가짜 체크아웃이 다른 내용을 쓰게 하면 된다). 앞의 발견 3건은 모두 이 입력들로 잡힌다.
- **복구 부분 실패**: `apply` 중간 실패(권한·용량) 뒤 목적지 상태와 재시도 동작에 대한 테스트가 없다. 목적지 하위를 읽기 전용으로 만들어 두면 재현 가능하다.
- **저장소 정규화 중간 실패**: `SVNRepositoryPathNormalizationIntegrationTests`는 차단·skip·성공만 덮는다. `SVNRepositoryPathNormalizationError.failed`의 부분 결과(`renamedTargets`, `committedRevisions`)와 그 뒤 남은 pending의 경로 접두사 재작성(`SVNClient.swift:594-605`)은 검증되지 않는다. 세 단계 트리에서 두 번째 move만 실패시키면(예: 목적지 이름을 미리 만들어 충돌) 잡힌다.
- **차단 검사의 상태 종류**: `realSVNRejectsRepositoryNormalizationWhenTargetTreeHasLocalChanges`는 내용 수정만 쓴다. `svn propset svn:needs-lock`만 한 상태를 넣었어야 위 발견이 잡혔다.
- **`run`의 취소 경합**: `Task.checkCancellation()`(`:2597`) 이후 `process.run()`(`:2641`) 사이에 취소가 들어오면 명령은 끝까지 실행되고 호출자는 `CancellationError`를 받는다. 커밋에서 이 창이 열리면 "취소했는데 반영된" 상태가 된다. 이 순서를 겨냥한 테스트가 없다.
- **`cleanupMissingScheduledAdditions` 실패 경로**: `:755-757`(revert 실패 후 재조회, 오류 삼킴)를 지나는 테스트가 없다. 대상 경로를 읽기 전용 상위 폴더에 두면 재현 가능하다.
- **`SVNWorkingCopySnapshot.init`의 `malformedResponse`**: `:126-128`(숫자 리비전이 하나도 없을 때)를 지나는 테스트가 없다. 사용자에게는 "서버 응답을 해석할 수 없습니다"로만 보인다.
- 반대로 잘 덮인 곳: `SVNWorkingCopySnapshotTests` 16개가 별칭·트리 충돌·모호한 정규화 충돌을 바이트 단위로 검증하고, `SVNRepositoryPathNormalization`의 대상 선정 4개와 실 저장소 5개가 정상·차단·skip을 덮는다.

## 확인하지 않은 것

- `SVNXMLParser`의 실제 파싱 결과(위 좌표계 계약)는 코드를 읽지 않고 호출 관계만 봤다. 배정 범위 밖이다.
- HFS+·SMB·exFAT 볼륨에서의 `rename(2)` 실제 동작. 이 세션에서는 APFS 부트 볼륨만 확인했다.
- `recoverWorkingCopy` 전체 흐름을 실제 `SVNClient`로 돌리지 않았다. 복구 관련 4건은 svn 수준 재현 + 코드 추적이다.
- `run`의 취소 경합과 `materializeCanonicalFileReplacements` 복구 실패 경로는 재현을 시도하지 않았다.
- `swift test` 전체(558개)를 돌리지 않았다. 필터한 67개만 확인했다.
- 성능은 보지 않았다(`normalizeDescendants`가 새 폴더 전체를 두 번 훑는 비용 등).
