# SVN Mac 막다른 길 감사

날짜: 2026-08-25  
범위: 읽기 전용. 이미 처리 중인 7건(트리 충돌 해결, 속성 충돌, `cleanup` 부재, 충돌 파일 되돌리기 메뉴, `unlock --force`, `obstructed`, 업데이트 뱃지 지연)은 다시 적지 않는다.

재현 환경: 이 머신에 설치된 `svn` 1.x CLI, 임시 `file://` 저장소 `/tmp/svnmac-audit-repro`. APFS 볼륨.

---

# 1. 막다른 길 · 실패 경로

심각도 높은 순.

## SVN 인증 실패가 계정 재입력으로 이어지지 않는다

- 심각도: 높음
- 근거: `Sources/SVNMac/ProjectStore.swift:1172-1183`, `Sources/SVNMac/ProjectStore.swift:60-64`, `Sources/SVNMac/SVNErrorLocalization.swift:7-8`, `Sources/SVNMac/ProjectStore+Locking.swift:102-105`, `Sources/SVNCore/SVNClient.swift:1762`
- 재현: 코드 기준 추정 (비밀번호가 틀린 HTTP 서버는 이 환경에 없음)
- 증상: 비밀번호가 바뀌거나 만료되면 `svn commit`/`update`/`log`가 `--non-interactive` 때문에 `E170001`/`E215004`로 바로 실패한다. 화면에는 `svn commit 실패: …` 원문만 뜬다. 인증 시트는 열리지 않는다. 자동 새로고침은 `automaticRefreshBlockedProjectID`로 멈춘다.
- 발생 조건: 도메인 비밀번호 주기 변경, Keychain에 옛 비밀번호가 남은 경우. 이 팀에서 흔하다.
- 막다른 길인가: 완전 차단은 아니다. 머리글 「폴더 설정」에서 계정을 바꿀 수 있다. 다만 오류가 그 화면으로 안내하지 않고, `handleRemoteError`는 Keychain 접근 거부일 때만 인증 시트를 연다. 잠금·파일 기록·ignore는 `handleRemoteError`를 거치지 않아 재시도 대상(`SVNAuthenticationAction`)에도 없다.
- 고치는 범위: `SVNClient.checkedRun`에서 인증 오류 코드를 구분하고, `ProjectStore.handleRemoteError`가 SVN 인증 실패에도 시트를 열게 한다. `SVNAuthenticationAction`에 lock/log를 넣는다.

## 기록에 보이는 과거 문서를 꺼낼 수 없다

- 심각도: 높음
- 근거: `Sources/SVNMac/FileHistoryView.swift` 전체 (목록만 표시), `Sources/SVNMac/HistoryRevisionDiffView.swift:115-142` (텍스트 diff만), `Sources/SVNCore/SVNClient.swift:479` (`cat`은 BASE 복구 내부용), `Sources/SVNCore/SVNClient.swift:1141-1151` (`update`에 `-r` 없음)
- 재현: 코드 기준 추정. `/tmp/svnmac-audit-repro`에서 xlsx를 두 번 커밋하면 기록은 남지만 앱에 해당 리비전 바이트를 저장할 API가 없다.
- 증상: 커밋 기록·파일 기록은 보인다. xlsx/hwp는 「텍스트 diff 없음」이다. 지난주 양식으로 되돌리거나 그 버전을 다른 이름으로 저장할 버튼이 없다.
- 발생 조건: 잘못 저장한 엑셀/한글을 이전 커밋에서 되살릴 때. 이 팀의 핵심 워크플로.
- 막다른 길인가: 앱 안에서 빠져나올 수단이 없다. 터미널의 `svn cat -r N` / 역머지가 필요하다.
- 고치는 범위: `SVNClient`에 리비전 `cat`(또는 `export`)을 추가하고, 기록/파일 기록 UI에서 「이 버전 저장」·「작업 파일로 되돌리기」를 제공한다.

## 체크아웃을 취소하면 같은 폴더로 재개할 수 없다

- 심각도: 중간
- 근거: `Sources/SVNMac/ProjectStore.swift:668-674`, `Sources/SVNMac/Resources/ko.lproj/Localizable.strings` (`ui.the.checkout.was.canceled…`), `Sources/SVNCore/SVNClient.swift:65-71`
- 재현: 실제 재현함. `/tmp/svnmac-audit-repro/wc-kill` 체크아웃을 중간에 죽이면 `item="incomplete"`이고, 같은 경로에 다시 `svn checkout`/`svn update` 하면 `E155004` (WC locked). `svn info`는 성공한다.
- 증상: 안내 문구는 「일부 파일이 남아 있을 수 있다」만 말한다. 프로젝트 목록에 넣지 않는다. 같은 폴더로 체크아웃을 다시 누르면 실패한다. `cleanup`이 앱에 없는 현재(처리 중)와 겹치면 폴더가 잠긴 채 남는다.
- 발생 조건: 큰 저장소를 받다가 취소. 네트워크가 느린 사무실에서 가능.
- 막다른 길인가: 빈 다른 폴더를 고르면 우회된다. 이미 받은 폴더를 이어받으려면 「기존 작업 폴더로 추가」→(처리 중인) cleanup → 업데이트가 필요한데 앱이 그 순서를 알려 주지 않는다.
- 고치는 범위: 취소 후 대상 폴더를 기존 작업 복사본으로 등록할지 묻고, incomplete면 업데이트로 이어 받게 한다. cleanup 작업과 맞춘다.

## incomplete 상태가 알 수 없는 문자열로만 보이고 되돌리기 메뉴가 뜬다

- 심각도: 중간
- 근거: `Sources/SVNCore/Models.swift:8-30` (`incomplete` 없음 → `.unknown`), `Sources/SVNMac/ChangesView.swift:190-199` (unknown은 되돌리기 대상), `Sources/SVNMac/ChangesView.swift:292`, `Sources/SVNCore/SVNWorkingCopySnapshot.swift:267-269`
- 재현: 실제 재현함. 중단된 체크아웃 XML에 `item="incomplete"`.
- 증상: 변경 목록에 영어 `incomplete` 배지가 회색으로 뜬다. 체크박스는 없고(커밋 불가), 컨텍스트 메뉴에는 「로컬 변경 되돌리기」가 있다. 디렉터리 revert(`--depth infinity`)는 받은 파일을 날릴 수 있다. 「이어서 받기」는 없다. 툴바 업데이트는 잠금이 풀린 뒤에만 통한다.
- 발생 조건: 위 체크아웃 취소와 동일. 드물지만 걸리면 안내가 없다.
- 막다른 길인가: 업데이트로 빠져나올 수는 있다. 다만 상태가 설명되지 않고, 잘못된 되돌리기가 더 잘 보인다.
- 고치는 범위: `SVNStatusKind.incomplete` 추가, 되돌리기 숨김, 「업데이트로 이어서 받기」 안내.

## 변경 목록에 잠금이 없고, 남이 잠근 파일을 잠금 없이 열도록 둔다

- 심각도: 중간
- 근거: `Sources/SVNMac/ChangesView.swift` (잠금 배지·잠금 메뉴 없음), `Sources/SVNMac/ProjectStore+Locking.swift:69-80`, `Sources/SVNMac/RepositoryLocksView.swift:56-66`, `Sources/SVNMac/DocumentOpenConfirmation.swift:48-63`, `Sources/SVNCore/SVNClient.swift:789-817` (`lock`/`unlock`에 `--force` 없음 — `--force` 자체는 처리 중이므로 여기서는 다루지 않음)
- 재현: 코드 기준 추정. 잠금 XML 경로는 `/tmp/svnmac-audit-repro`에서 `svn lock` 후 `status --show-updates --xml`에 나타남을 확인함.
- 증상:
  - 커밋 화면에서 누가 잠갔는지 보이지 않는다. 커밋이 잠금에 막히면 `commandFailed` 원문만 본다.
  - 「항상 잠그고 열기」인데 이미 다른 사람 잠금이면 `openWithoutLock`으로 그냥 연다.
  - 잠금 목록에서 내 계정과 소유자 문자열이 다르면 잠금 해제 버튼이 없다.
  - `svn:needs-lock`을 걸 방법이 없어, Finder/엑셀로 연 파일은 읽기 전약이 아니다.
- 발생 조건: 공유 xlsx/hwp. 이 팀에서 흔하다.
- 막다른 길인가: 머리글 「잠금」시트에서 내 잠금은 풀 수 있다. 남의 잠금·다른 작업본의 내 잠금은 `--force` 처리 분과 겹친다. 변경 탭만 쓰는 사용자는 커밋 실패 원문을 읽어야 한다.
- 고치는 범위: 변경 행에 잠금 소유자 표시, 커밋 전 잠금 검사, 「항상 잠그고 열기」가 남의 잠금일 때 열기를 막거나 명확히 경고, `svn:needs-lock` 설정 UI.

## 파일 탐색기가 NFC/NFD 바이트가 다르면 버전 파일을 미버전으로 본다

- 심각도: 중간
- 근거: `Sources/SVNMac/WorkingCopyFileService.swift:140-145,200`, `Sources/SVNMac/WorkingCopyFileService.swift:21-23` (`matchesRepositoryPath`는 UTF-8 바이트 동등), `Sources/SVNCore/SVNWorkingCopySnapshot.swift:6-19`, `Tests/SVNMacTests/WorkingCopyFileServiceTests.swift:47-66,68-87`
- 재현: 코드 기준 추정 + 기존 단위 테스트. 이 머신 APFS에서 `svn checkout`한 한글 파일명은 NFC였고 디스크와 일치했다. HFS+이거나 Finder가 NFD로 만들고 저장소 경로가 NFC인 충돌은 테스트가 이미 전제한다.
- 증상: 탐색기 항목의 `svnEntry`가 비어 `isVersioned == false`가 된다. `prepareToOpen`이 잠금 확인을 건너뛰고 그냥 연다. 잠금 아이콘도 안 붙는다. 명령 경로 해석(`resolveWorkingCopyCommandPath`)은 NFC/NFD를 시도하지만, 탐색기 매칭은 그 로직을 쓰지 않는다.
- 발생 조건: 한글 파일명 + NFD 볼륨 또는 정규화 충돌. 머리글에 NFD 볼륨 경고가 뜨는 폴더에서 더 잘 난다.
- 막다른 길인가: 변경 탭의 스냅샷은 canonical key로 일부 맞춘다. 탐색기에서 문서를 여는 잠금 워크플로만 뚫린다.
- 고치는 범위: 탐색기 매칭을 `canonicalKey`로 하고, 충돌(동일 키에 원문 경로 둘)일 때만 바이트를 쓴다. 잠금 비교도 동일.

## 저장소 루트 URL이 바뀌면 원격 작업이 전부 실패한다

- 심각도: 중간
- 근거: `Sources/SVNMac/ProjectStore.swift:734-739` (`relocateProject`는 로컬 폴더 위치 변경), `svn help relocate` (이 환경), `Sources/SVNCore/SVNClient.swift`에 `relocate` 호출 없음
- 재현: 코드 기준 추정
- 증상: 서버가 `http`→`https`이거나 호스트 이름이 바뀌면 update/commit/history가 `commandFailed`로만 실패한다. 앱의 「위치 변경」은 Finder에서 폴더를 옮긴 뒤 경로를 고치는 기능이다.
- 발생 조건: 사내 SVN 이전. 자주 있지는 않지만 한 번 나면 팀 전체가 멈춘다.
- 막다른 길인가: 앱 안에 `svn relocate`가 없다.
- 고치는 범위: `SVNClient.relocate` + 폴더 설정에서 저장소 URL 변경.

## 앱 전용 Subversion config-dir이 시스템 프록시·auto-props를 무시한다

- 심각도: 중간
- 근거: `Sources/SVNCore/SVNClient.swift:1762,1941-1952`
- 재현: 코드 기준 추정 (프록시가 필요한 네트워크에서 돌려 보지 않음)
- 증상: 모든 `svn` 호출이 `Application Support/SVN KR/Subversion`을 `--config-dir`로 쓴다. `~/.subversion/servers`의 `http-proxy-host`와 auto-props(`svn:needs-lock` 등)를 읽지 않는다. 빈 config면 프록시 없이 원격이 실패하고, 추가 시 잠금 필수 속성도 안 붙는다.
- 발생 조건: HTTP 프록시 사무실. 있으면 체크아웃부터 막힌다.
- 막다른 길인가: 앱에 프록시 UI가 없다. 우회는 그 config-dir에 파일을 손으로 넣는 것뿐이다.
- 고치는 범위: 프록시 설정 UI, 또는 사용자 `servers`를 읽어 오되 인증 캐시는 격리. 문서 확장자에 `svn:needs-lock` auto-props.

## 트리 충돌 「서버 버전 복원」이 작업 복사본 전체를 업데이트한다

- 심각도: 낮음
- 근거: `Sources/SVNMac/ProjectStore+Conflicts.swift:88-100`, `Sources/SVNMac/TreeConflictResolution.swift:10-12`
- 재현: 코드 기준 추정
- 증상: 파일 하나 트리 충돌을 서버 쪽으로 풀 때 `revert` 후 **루트 `svn update`**를 실행한다. 다른 로컬 변경·다른 파일 충돌을 같이 끌어올 수 있다.
- 발생 조건: 트리 충돌 + 로컬에 다른 수정이 있을 때. 속성/트리 충돌 처리와 별개.
- 막다른 길인가: 아니다. 부작용이 큰 복구 동작이다.
- 고치는 범위: 해당 경로만 `update` 하거나, 전체 업데이트 전에 확인.

## switched 하위 경로가 화면에 없다

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNXMLParser.swift:372-380` (`item==normal`이면 속성 무시), `Sources/SVNCore/SVNWorkingCopySnapshot.swift:267-269`
- 재현: 실제 재현함. `svn switch`한 `문서`는 `svn status --xml`에 `switched="true" item="normal"`로 나온다. 앱 파서는 이 항목을 버린다.
- 증상: 하위 폴더가 다른 URL을 가리켜도 변경 목록·탐색기에 표시가 없다. `switch`로 되돌릴 UI도 없다.
- 발생 조건: 누군가 터미널에서 `svn switch`를 쓴 작업본. 사무 문서 팀에서는 드물다.
- 막다른 길인가: 그 상태에 들어가면 앱만으로는 원인 파악과 복구가 안 된다.
- 고치는 범위: `switched` 속성 파싱, 배지, `svn switch`로 부모 URL에 맞추기.

## 신뢰하지 않는 인증서 허용 범위가 unknown-ca/cn-mismatch뿐이다

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNClient.swift:1763-1764`
- 재현: 코드 기준 추정
- 증상: 폴더 설정의 인증서 허용은 `unknown-ca,cn-mismatch`만 넘긴다. 만료·아직 유효하지 않음·기타 SSL 실패는 계속 `commandFailed`다.
- 발생 조건: 사내 인증서 만료. 드물다.
- 막다른 길인가: 만료 서버면 원격 작업이 전부 실패하고, 앱이 더 허용할 방법이 없다.
- 고치는 범위: `expired` 등을 옵션으로 추가하거나 오류에 설정 화면을 안내.

## 같은 프로젝트에서 파일 기록을 빠르게 바꾸면 늦은 응답이 덮을 수 있다

- 심각도: 낮음
- 근거: `Sources/SVNMac/ProjectStore+FileActions.swift:24-41` (`beginRequest`/`canApplyRequest` 없음, 경로 토큰 없음)
- 재현: 코드 기준 추정. 프로젝트 전환 레이스는 `Tests/SVNMacTests/ProjectStoreTests.swift` `staleFileHistoryDoesNotOpenOnNewProject`가 막고, 같은 프로젝트·다른 파일은 막지 않는다.
- 증상: 파일 A 기록을 연 뒤 바로 B를 열면 A 응답이 B 목록을 덮을 수 있다.
- 발생 조건: 빠른 연속 클릭. 드물다.
- 막다른 길인가: 아니다. 잘못된 기록이 잠깐 보인다.
- 고치는 범위: `ProjectRequestKind.fileHistory`와 요청 경로 가드. `diff`와 같은 패턴.

---

# 2. svn CLI 대비 앱 지원

근거: 이 환경 `svn help` / `svn help <명령>`, `Sources/SVNCore/SVNClient.swift`가 실제로 넘기는 인자.

처리 중인 항목은 「부분 (처리 중)」으로만 적고, 1장의 중복 서술은 피한다.

## svn add

- 앱 지원: 부분. 커밋 시 미버전 경로에 `add --parents`만 한다. `--force`, `--no-ignore`, `--auto-props`, `--depth` 없음. 단독 「추가」버튼 없음.
- 이 명령이 존재하는 이유: 커밋 전에 버전 관리 대상으로 예약한다.
- 없어서 생기는 상황: 커밋하지 않고 추가만 예약하거나, 무시 규칙을 깨고 임시파일을 추가하기 어렵다. 이 팀은 보통 커밋 화면으로 충분하다.
- 실제로 겪을 확률: 낮음. 커밋 흐름이 추가를 포함한다.
- 대체 수단: 변경 탭에서 미버전을 골라 커밋.

## svn auth

- 앱 지원: 부분. 프로젝트별 Keychain. `svn auth --remove` / 인증서 캐시 목록 없음.
- 이 명령이 존재하는 이유: 캐시된 비밀번호·클라이언트 인증서를 관리한다.
- 없어서 생기는 상황: 앱 config-dir에 남은 잘못된 인증서가 남으면 폴더 설정과 별개로 실패할 수 있다. 확인하지 않음.
- 실제로 겪을 확률: 낮음
- 대체 수단: 폴더 설정의 비밀번호 삭제. SVN 인증 캐시 전체는 불가.

## svn blame

- 앱 지원: 없음
- 이 명령이 존재하는 이유: 줄 단위 작성자를 본다.
- 없어서 생기는 상황: 텍스트 소스에는 아쉽다. xlsx/hwp에는 무의미하다.
- 실제로 겪을 확률: 낮음 (학술)
- 대체 수단: 없음. 이 팀에는 필요 없다.

## svn cat

- 앱 지원: 부분. 내부에서 `cat --revision BASE`만. 임의 리비전·저장 없음.
- 이 명령이 존재하는 이유: 특정 리비전의 파일 바이트를 꺼낸다.
- 없어서 생기는 상황: 지난 주간보고서를 파일로 저장하지 못한다. 1장 두 번째 발견과 동일.
- 실제로 겪을 확률: 높음
- 대체 수단: 없음

## svn changelist

- 앱 지원: 없음
- 이 명령이 존재하는 이유: 커밋 대상을 이름 있는 묶음으로 나눈다.
- 없어서 생기는 상황: 변경 탭 체크박스로 충분하다.
- 실제로 겪을 확률: 낮음 (학술)
- 대체 수단: 선택 커밋

## svn checkout

- 앱 지원: 부분. `checkout -- URL .` 만. `-r`, `--depth`, `--force`, `--ignore-externals` 없음. 진행 로그·취소는 있음.
- 이 명령이 존재하는 이유: 작업 복사본을 만든다.
- 없어서 생기는 상황: 옛 리비전만 받거나 얕은 체크아웃이 안 된다. `--force`가 없어 비어 있지 않은 폴더는 실패한다. 취소 재개는 1장.
- 실제로 겪을 확률: 중간 (취소·기존 폴더). `-r`/depth는 낮음.
- 대체 수단: 빈 폴더를 고른다. 특정 리비전 WC는 불가.

## svn cleanup

- 앱 지원: 없음 (처리 중)
- 이 명령이 존재하는 이유: 중단된 작업이 남긴 WC write lock을 푼다.
- 없어서 생기는 상황: E155004로 앱 전체가 멈춘다.
- 실제로 겪을 확률: 높음 (이미 터진 버그)
- 대체 수단: 없음

## svn commit

- 앱 지원: 부분. `--message`와 `--targets`. `--no-unlock`, `--depth`, 외부 편집기 없음. 대량 경로는 `--targets`로 다룬다.
- 이 명령이 존재하는 이유: 로컬 변경을 저장소에 보낸다.
- 없어서 생기는 상황: 커밋 후에도 잠금을 유지(`--no-unlock`)할 수 없다. 문서를 이어서 고칠 때 잠금이 풀려 다른 사람이 잠글 수 있다.
- 실제로 겪을 확률: 중간
- 대체 수단: 커밋 후 파일을 다시 열어 잠근다.

## svn copy

- 앱 지원: 없음 (경로 정규화는 `move`만)
- 이 명령이 존재하는 이유: 이력을 유지한 채 복사·분기한다.
- 없어서 생기는 상황: `2025양식.xlsx`를 `2026양식.xlsx`로 복사하면 Finder 복사 → 미버전 추가로 이력이 끊긴다.
- 실제로 겪을 확률: 중간
- 대체 수단: Finder 복사 후 새 파일 커밋. 이력은 끊긴다.

## svn delete

- 앱 지원: 부분. 누락 항목·임시파일 정리에 `delete --force`. 탐색기에서 임의 파일을 지우는 UI는 약하다.
- 이 명령이 존재하는 이유: 저장소에서 경로를 삭제 예약한다.
- 없어서 생기는 상황: 정상 파일을 앱에서 삭제 예약하려면 먼저 Finder에서 지워 missing으로 만든 뒤 「저장소에서 삭제」를 고른다.
- 실제로 겪을 확률: 중간
- 대체 수단: Finder 삭제 후 변경 탭 메뉴.

## svn diff

- 앱 지원: 부분. 로컬 diff, 기록 `--change REV`. 임의 `-r N:M`, `--git`, 외부 diff 도구 없음.
- 이 명령이 존재하는 이유: 텍스트 차이를 본다.
- 없어서 생기는 상황: 두 옛 리비전 비교, 바이너리는 원래 불가.
- 실제로 겪을 확률: 낮음 (문서가 바이너리)
- 대체 수단: 로컬 텍스트 파일만 변경 탭.

## svn export

- 앱 지원: 없음
- 이 명령이 존재하는 이유: `.svn` 없이 한 리비전을 폴더로 뽑는다.
- 없어서 생기는 상황: 외주에 「이 리비전 스냅샷」을 줄 때.
- 실제로 겪을 확률: 낮음
- 대체 수단: Finder에서 복사하면 `.svn`이 따라갈 수 있다.

## svn import

- 앱 지원: 없음
- 이 명령이 존재하는 이유: WC 없이 폴더를 저장소에 넣는다.
- 없어서 생기는 상황: 새 저장소 첫 업로드. 체크아웃 후 추가·커밋으로 우회.
- 실제로 겪을 확률: 낮음
- 대체 수단: 체크아웃 후 커밋.

## svn info

- 앱 지원: 부분. wc-root, url, revision, kind, HEAD 잠금, 충돌 XML. 일반 정보 화면 없음.
- 이 명령이 존재하는 이유: URL, 리비전, 잠금, 충돌 메타데이터를 본다.
- 없어서 생기는 상황: switched/incomplete를 사용자가 직접 확인하기 어렵다.
- 실제로 겪을 확률: 중간 (문제 진단 시)
- 대체 수단: 없음

## svn list

- 앱 지원: 부분. 저장소 경로 정규화용 `list --recursive --xml`만. 원격 브라우저 없음.
- 이 명령이 존재하는 이유: 체크아웃 없이 저장소 트리를 본다.
- 없어서 생기는 상황: 받기 전에 폴더 구조를 미리 보기 어렵다.
- 실제로 겪을 확률: 낮음
- 대체 수단: 체크아웃.

## svn lock

- 앱 지원: 부분. 파일 열 때 `lock --message` (문구 고정). `--force`(훔치기) 없음 — 처리 중. 여러 파일 일괄 잠금 없음.
- 이 명령이 존재하는 이유: 커밋을 한 작업본에 독점한다.
- 없어서 생기는 상황: 폴더의 xlsx를 한꺼번에 잠글 수 없다. 변경 탭에서 잠글 수 없다.
- 실제로 겪을 확률: 높음
- 대체 수단: 파일을 하나씩 연다.

## svn log

- 앱 지원: 부분. `--xml --verbose --with-all-revprops --limit`와 범위. `--search`, `--stop-on-copy`, `--diff`, 날짜 `-r {DATE}` 없음.
- 이 명령이 존재하는 이유: 커밋 이력을 본다.
- 없어서 생기는 상황: 메시지/작성자 검색은 앱 검색창이 클라이언트에서 걸러 줄 수는 있다. 서버측 `--search`는 없다. 복사 시작점(`--stop-on-copy`) 없음.
- 실제로 겪을 확률: 낮음
- 대체 수단: 기록 탭 검색.

## svn merge / svn mergeinfo

- 앱 지원: 없음
- 이 명령이 존재하는 이유: 분기 통합, **이미 커밋한 변경을 되돌리기**(역머지).
- 없어서 생기는 상황: 잘못된 문서 커밋을 저장소에서 되돌리려면 역머지가 정석이다. `cat`으로 파일을 덮어 커밋하는 우회와 같다.
- 실제로 겪을 확률: 중간 (되돌리기). 기능 분기는 낮음 (학술).
- 대체 수단: 없음. 터미널.

## svn mkdir

- 앱 지원: 없음
- 이 명령이 존재하는 이유: 버전 폴더를 만든다.
- 없어서 생기는 상황: Finder에서 폴더를 만들면 미버전으로 커밋 시 `add --parents`된다.
- 실제로 겪을 확률: 낮음
- 대체 수단: Finder + 커밋.

## svn move

- 앱 지원: 부분. 저장소 한글 경로 정규화 커밋에만 `move`. 사용자 이름 변경 UI 없음.
- 이 명령이 존재하는 이유: 이력을 유지한 채 이름/위치를 바꾼다.
- 없어서 생기는 상황: Finder에서 `주간보고서.xlsx` → `주간보고서_2026.xlsx`로 바꾸면 missing + unversioned. 재현함. 「로컬 복원」은 옛 이름을 되살리고 새 파일은 남는다. 「저장소에서 삭제」+새 파일 커밋은 이력을 끊는다.
- 실제로 겪을 확률: 높음
- 대체 수단: 불완전. 위 두 메뉴.

## svn patch

- 앱 지원: 없음
- 이 명령이 존재하는 이유: unidiff를 적용한다.
- 없어서 생기는 상황: 개발 워크플로. 이 팀과 무관.
- 실제로 겪을 확률: 낮음 (학술)
- 대체 수단: 없음

## svn propdel / propedit / propget / proplist / propset

- 앱 지원: 부분. `svn:ignore` / `svn:global-ignores`만. `svn:needs-lock`, `svn:mime-type`, `svn:eol-style` 없음. 속성 충돌 편집은 처리 중.
- 이 명령이 존재하는 이유: 잠금 필수, MIME, 무시 규칙을 저장소에 붙인다.
- 없어서 생기는 상황: 사무 문서에 `svn:needs-lock`이 없으면 Finder에서 연 파일이 읽기 전약이 아니어서 잠금 워크플로가 쉽게 뚫린다.
- 실제로 겪을 확률: 높음 (`needs-lock`). 나머지 속성은 낮음.
- 대체 수단: ignore UI만.

## svn relocate

- 앱 지원: 없음 (`relocateProject`는 로컬 경로만)
- 이 명령이 존재하는 이유: 저장소 루트 URL만 바꿔 WC를 살린다.
- 없어서 생기는 상황: 1장 URL 변경 발견.
- 실제로 겪을 확률: 중간
- 대체 수단: 폴더를 지우고 새로 체크아웃 (로컬 변경 위험).

## svn resolve / resolved

- 앱 지원: 부분. `--accept working|mine-full|theirs-full`. `base`, `mine-conflict`, `theirs-conflict`, 대화형, `--depth` 없음. 속성 충돌은 처리 중.
- 이 명령이 존재하는 이유: 충돌을 해제해야 커밋할 수 있다.
- 없어서 생기는 상황: 텍스트 충돌의 부분 병합 선택지가 없다. 바이너리에는 mine/theirs-full로 충분한 경우가 많다.
- 실제로 겪을 확률: 낮음 (바이너리 문서)
- 대체 수단: 충돌 시트의 전체 버전 선택.

## svn revert

- 앱 지원: 부분. `--depth infinity`. `--remove-added` 없음. 충돌 파일 메뉴는 처리 중.
- 이 명령이 존재하는 이유: 커밋 전 로컬 변경을 버린다.
- 없어서 생기는 상황: 디렉터리 되돌리기가 하위 전부 삭제인데 확인 문구가 파일과 같다 (`RevertConfirmation.swift:19-20`).
- 실제로 겪을 확률: 중간
- 대체 수단: 확인 알림은 있다. 범위 설명은 약하다.

## svn status

- 앱 지원: 부분. `--xml`, `--verbose --no-ignore`, `--show-updates`. `props`, `switched`, `wc-locked`, 저장소 잠금 열(K/O/T/B)은 변경 목록 파서가 안 읽거나 다른 API로만 본다. `obstructed`는 처리 중.
- 이 명령이 존재하는 이유: WC와 서버 상태를 보여 준다.
- 없어서 생기는 상황: switched/incomplete/속성만 변경이 안 보이거나 오해된다. 속성 충돌은 처리 중.
- 실제로 겪을 확률: 중간
- 대체 수단: 잠금은 별도 시트(`status -u` 파싱).

## svn switch

- 앱 지원: 없음
- 이 명령이 존재하는 이유: WC를 다른 갈래 URL에 맞춘다.
- 없어서 생기는 상황: 1장 switched. 브랜치 전환은 이 팀에 거의 없다.
- 실제로 겪을 확률: 낮음
- 대체 수단: 없음

## svn unlock

- 앱 지원: 부분. `unlock`만. `--force` 없음 (처리 중).
- 이 명령이 존재하는 이유: 잠금을 푼다. `--force`는 남의 잠금·다른 WC의 내 잠금을 깬다.
- 없어서 생기는 상황: 처리 중인 버그.
- 실제로 겪을 확률: 높음
- 대체 수단: 내 잠금 + 같은 WC만 시트에서 해제.

## svn update

- 앱 지원: 부분. 인자 없는 `update`만. `-r`, `--set-depth`, `--ignore-externals`, `--force`, 경로 단위 업데이트 없음. 미리보기는 `status -u`.
- 이 명령이 존재하는 이유: 서버 변경을 가져오거나 특정 리비전으로 WC를 맞춘다.
- 없어서 생기는 상황: 어제 상태로 WC를 되돌릴 수 없다. 파일 하나 update로 트리 충돌을 좁혀 풀 수도 없다.
- 실제로 겪을 확률: 중간 (`-r`). depth/externals는 낮음.
- 대체 수단: 최신으로만 업데이트.

## svn upgrade

- 앱 지원: 없음
- 이 명령이 존재하는 이유: 옛 WC 형식을 현재 클라이언트가 쓰게 올린다.
- 없어서 생기는 상황: 아주 옛 Tortoise 작업본을 열면 `E155036`으로 전부 실패.
- 실제로 겪을 확률: 낮음
- 대체 수단: 없음

---

## 이 팀이 겪을 확률이 높은 순 — 상위 10

이미 처리 중인 것도 목록에는 남긴다. 우선순위 판단용이다.

1. **svn cat -r / 역머지** — 지난 문서를 기록에서 못 꺼냄
2. **svn move** — Finder 이름 변경이 이력 없는 삭제+추가로 떨어짐
3. **propset svn:needs-lock** — 잠금이 권고에 그침
4. **unlock/lock --force** — 처리 중. 남의 잠금·다른 PC 잠금
5. **svn cleanup** — 처리 중. 취소·충돌 후 E155004
6. **인증 실패 재입력** — 비밀번호 변경 후 원문 오류만
7. **svn lock UI (일괄·변경 탭)** — 열기 전에만 잠금
8. **svn relocate** — 서버 URL 이전
9. **svn copy** — 연도별 양식 복사 시 이력 단절
10. **commit --no-unlock / update -r** — 커밋 후 잠금 유지, 특정 리비전 WC

학술적으로만 빈 것: blame, patch, changelist, mergeinfo, export/import, switch/upgrade, sparse depth, externals. 사무 문서 팀에 막히지 않으면 위 10 밖에 둔다.

---

# 3. 확인하지 않은 것

- HTTP 인증 실패·프록시·만료 인증서를 실제 서버에 붙여 보지 않음
- HFS+ 볼륨에서 탐색기 NFD 불일치를 다시 재현하지 않음 (단위 테스트와 코드만)
- `svn:externals` 실패, merge 진행 중 WC, 대용량 파일 커밋 시간 초과를 재현하지 않음
- 앱 GUI를 띄워 클릭 경로는 확인하지 않음. CLI 재현과 소스 추적만 했다.
