# SVN Mac 막다른 길 감사 (2026-08-25)

읽기 전용 감사. 소스는 수정하지 않았다.

## 조사 범위와 방법

- `Sources/SVNCore/SVNClient.swift` 전문(2046줄)을 읽고 실행하는 `svn` 하위 명령과 옵션을 전수 목록화했다.
- `SVNXMLParser`, `SVNWorkingCopySnapshot`, `Models.swift`의 상태 매핑을 읽고 SVN이 반환하지만 앱이 버리는 값을 찾았다.
- `SVNErrorLocalization.swift`, `ProjectStore.handleRemoteError`, `DetailedErrorView`를 읽고 실패 경로가 사용자에게 무엇을 주는지 추적했다.
- `ProjectStore*`의 `canApplyRequest` / `selectedProjectID` 가드를 전수 확인했다.
- `/tmp`에 임시 저장소(`svnadmin create`)와 작업 복사본 3개를 만들어 잠금 충돌, 미버전 방해물, `switched`, 저장소 이전, 예약-추가 루트를 실제로 재현했다. 재현 여부는 각 항목에 명시했다.
- 환경의 실제 `svn` 은 `/opt/homebrew/bin/svn`, **1.14.5**. 하위 명령 목록과 옵션은 이 바이너리의 `svn help` 출력을 근거로 했다.

이미 처리 중이라고 안내받은 7건(트리 충돌, 속성 충돌 `props` 미파싱, `svn cleanup` 부재, 충돌 파일 되돌리기 메뉴, `unlock --force`, `obstructed` 상태, 업데이트 뱃지 지연)은 제외했다.

---

# 1부 — 발견

## 저장소 URL이 바뀌면 앱 안에서 복구할 수 없다 (`svn relocate` 부재)

- 심각도: **높음**
- 근거:
  - `Sources/SVNCore/SVNClient.swift` — `relocate` 하위 명령을 실행하는 코드가 없다. 실행하는 하위 명령 전체는 `checkout`, `info`, `list`, `status`, `log`, `diff`, `cat`, `add`, `commit`, `delete`, `revert`, `resolve`, `lock`, `unlock`, `move`(저장소 URL 간만), `propget`, `propset`, `propdel`, `update` 뿐이다.
  - `Sources/SVNMac/ProjectStore.swift:738` `relocateProject(_:to:)` — 이름은 relocate지만 **로컬 폴더 경로 교체**다. `client.validateWorkingCopy`로 새 로컬 경로를 검증할 뿐 저장소 URL은 건드리지 않는다.
- 재현: **실제 재현함.** 작업 복사본을 만든 뒤 저장소 디렉터리를 옮기자 `svn status -u`와 `svn up`이 모두 `E170013: Unable to connect to a repository at URL ...` / `E180001`로 실패했다. `svn relocate <old> <new>`를 실행하면 즉시 정상화되고, 미커밋 로컬 수정(`M 문서/보고서.txt`)도 그대로 보존됐다.
- 증상: 서버 주소가 바뀐 순간 새로고침·업데이트·커밋이 전부 실패한다. 화면에 뜨는 문구는 `"svn status 실패: svn: E170013: Unable to connect to a repository at URL 'https://구주소/svn/...'"` 영문 원문이다.
- 발생 조건: 저장소 루트 URL이 문법적으로만 바뀌는 모든 경우. 사내 NAS 교체, IP → 도메인 전환, `http` → `https` 전환(인증서 도입), 포트 변경, 호스트명 변경. 이 팀 기준으로 몇 년에 한 번이지만 **터지면 전원이 동시에** 마비된다. 관리자가 "터미널에서 svn relocate 하세요"라고 안내할 수 없는 사용자층이다.
- 막다른 길인가: **그렇다.** 앱 안의 유일한 우회는 프로젝트를 지우고 새 URL로 다시 체크아웃하는 것이다. 그러면 미커밋 로컬 수정(엑셀·한글 작업분)은 앱이 옮겨주지 않는다. 사용자가 Finder로 직접 파일을 골라 복사해야 하고, 어떤 파일이 수정본인지 앱은 이 상태에서 알려줄 수 없다(`status`가 이미 실패 중).
- 고치는 범위: `SVNClient`에 `relocate(at:from:to:)` 추가, `SVNError`에 `repositoryURLUnreachable` 계열 분기 추가(E170013/E180001/E170000 판별), `ProjectStore`에 저장소 URL 변경 시트. 기존 `relocateProject` 이름과 충돌하므로 명명 정리 필요.

---

## 만료된 SSL 인증서는 "신뢰" 체크박스로도 통과할 수 없다

- 심각도: **높음**
- 근거:
  - `Sources/SVNCore/SVNClient.swift:1764` — `globalArguments.append("--trust-server-cert-failures=unknown-ca,cn-mismatch")`
  - `svn help checkout -v` 실제 출력: 허용 값은 `unknown-ca`, `cn-mismatch`, `expired`, `not-yet-valid`, `other` 다섯 가지. 앱은 앞의 둘만 넣는다.
  - `Sources/SVNMac/RepositoryDialogs.swift:587` `UntrustedCertificateToggle` — UI는 "신뢰하지 않는 서버 인증서 허용" 하나의 토글이다. 사용자는 이 토글이 만료 인증서도 덮는다고 읽는다.
- 재현: **코드 기준 추정.** HTTPS 서버를 세우지 않았다. 옵션 값 목록은 설치된 `svn 1.14.5`의 `svn help` 출력으로 확인했다.
- 증상: 토글을 켜도 `svn: E175002` + `svn: E230001: Server SSL certificate verification failed: certificate has expired`로 계속 실패한다. 사용자는 이미 "허용" 체크를 했으므로 앱이 고장 났다고 판단한다.
- 발생 조건: 사내 저장소가 자체 서명 인증서를 쓰고 그 인증서가 만료될 때. 자체 서명 인증서의 기본 유효기간은 흔히 1년이므로 **한 번 도입하면 1년 뒤 반드시 온다.** 서버 시계가 틀어져 `not-yet-valid`가 되는 경우도 같은 경로다.
- 막다른 길인가: **그렇다.** 앱에 인증서 예외를 추가하거나 `servers` 설정을 편집할 수단이 없다(다음 항목 참조). 서버 관리자가 인증서를 갱신할 때까지 전원 정지.
- 고치는 범위: `SVNClient.run`의 인자 구성. 다만 `expired`/`other`를 무조건 켜는 것은 보안상 부적절하므로, 실패 원인을 stderr에서 판별해 "만료된 인증서입니다. 그래도 계속할까요?"를 명시적으로 한 번 더 확인받는 계층(`ProjectStore` + `SVNError` 분기)이 필요하다.

---

## 이전 리비전으로 파일을 되돌릴 방법이 앱에 전혀 없다

- 심각도: **높음**
- 근거:
  - `Sources/SVNCore/SVNClient.swift:329` `cat` 은 `--revision BASE`로만, 그것도 `canonicalFileReplacementResolution` 내부 비교용으로만 호출된다(파일 471~490). 공개 API가 아니다.
  - `SVNClient`에 `export`, `merge`, `copy`(작업 복사본 대상) 가 없다.
  - `SVNClient.update`(`checkedRun(["update"], ...)`)에 `--revision` 인자가 없다. `checkout`도 `--revision`이 없다(`["checkout", "--", repositoryURL, "."]`).
  - `Sources/SVNMac/FileHistoryView.swift` — 리비전·작성자·날짜·메시지만 나열한다. 버튼은 "닫기" 뿐이다.
  - `Sources/SVNMac/HistoryView.swift` / `HistoryRevisionDiffView.swift` — `loadHistoryDiff`로 diff 텍스트만 띄운다(`ProjectStore+History.swift:9`).
  - `Sources/SVNMac/RepositoryDialogs.swift:158` — 체크아웃 다이얼로그에 리비전 입력 필드가 없다.
- 재현: **코드 기준 추정.** UI 계층 전수 grep(`revert`, `restore`, `--revision`, `되돌리기`)로 확인했고 해당 동작이 없다.
- 증상: "김대리가 어제 보고서를 실수로 덮어써서 커밋했다. 그 전 버전으로 돌려줘"를 앱으로 할 수 없다. `revert`는 미커밋 변경만 취소한다(`svn help revert`: "This subcommand does not revert already committed changes"). 이력 화면에서 diff는 볼 수 있지만 그 내용을 파일로 되살릴 수 없다. 엑셀·한글 파일은 diff 자체가 무의미하다(바이너리라 `noTextDiff`).
- 발생 조건: 상시. 사무직 팀이 버전관리를 쓰는 첫째 이유가 "잘못 저장한 걸 되돌리기"다. 잠금 워크플로가 있어도 잠금을 쥔 사람이 잘못 저장하는 것은 막지 못한다.
- 막다른 길인가: **그렇다.** 앱 안에 우회가 없다. 이력에서 diff를 보고 손으로 다시 타이핑하는 것 외에 방법이 없고, 바이너리 문서는 그조차 불가능하다.
- 고치는 범위: `SVNClient`에 `fileContents(at:relativePath:revision:)`(=`cat -r`) 또는 `exportRevision`(=`export -r`) 추가. `ProjectStore`에 "이 리비전 내용으로 되돌리기"(작업 복사본에 덮어쓰고 `modified` 상태로 만들어 사용자가 커밋) 동작. 화면은 `FileHistoryView` / `HistoryRevisionDiffView`. 되돌리기 전 현재 파일 백업은 필수(아래 파괴적 동작 항목과 같은 원칙).

---

## 앱 전용 `--config-dir` 때문에 사내 프록시·서버 설정이 전부 무시된다

- 심각도: **높음**
- 근거:
  - `Sources/SVNCore/SVNClient.swift:1762` — `var globalArguments = ["--non-interactive", "--config-dir", configDirectory.path]`
  - `Sources/SVNCore/SVNClient.swift:1990` `svnConfigDirectory()` — `Application Support/.../Subversion` 을 만들고 그것만 쓴다.
  - `svn help update -v` 실제 출력: `--config-dir ARG : read user configuration files from directory ARG`. 즉 `~/.subversion/servers`, `~/.subversion/config`는 읽히지 않는다.
  - 앱은 `--config-option`도 쓰지 않고, 이 앱 전용 config 디렉터리에 `servers` 파일을 쓰는 코드도 없다(`grep -rn 'servers' Sources` 결과 없음).
- 재현: **코드 기준 추정.** `--config-dir` 의미는 `svn help` 출력으로 확인했다. 프록시 서버는 세우지 않았다.
- 증상: 사내 프록시를 거쳐야 외부/사내 저장소에 닿는 환경에서, 터미널 `svn`은 되는데 앱만 `E170013 Unable to connect` 또는 타임아웃으로 실패한다. IT 담당자가 `~/.subversion/servers`에 `http-proxy-host`를 넣어줘도 앱에는 반영되지 않는다.
- 발생 조건: 회사가 프록시를 강제하는 경우. 한국 사무 환경에서 드물지 않다. 같은 메커니즘으로 `http-timeout`(대용량 xlsx/hwp 전송 시 필요), `http-library`, 클라이언트 인증서(`ssl-client-cert-file`) 설정도 전부 반영되지 않는다.
- 막다른 길인가: **그렇다.** 앱 UI에 프록시나 서버 설정 항목이 없고, 사용자가 앱 전용 config 디렉터리 경로를 알 방법도 없다(경로를 표시하는 화면이 없다).
- 고치는 범위: 두 가지 중 하나. (a) 앱 config 디렉터리에 사용자 `~/.subversion/servers`를 부팅 시 한 번 반영하거나, (b) 설정 화면에 프록시/타임아웃 입력을 만들어 `--config-option servers:global:http-proxy-host=...` 형태로 넘긴다. `SVNClient.run` + `AppSettings` + 설정 화면.

---

## 모든 실패 경로가 영문 SVN 원문 덤프로 끝난다 — 다음 행동 안내가 0건

- 심각도: **높음** (다른 모든 막다른 길의 증폭기)
- 근거:
  - `Sources/SVNMac/SVNErrorLocalization.swift:7-8` — `case let .commandFailed(command, message): return language.localized("ui.failed.cb475070", command, message)`
  - `Sources/SVNMac/Resources/ko.lproj/Localizable.strings:175` — `"ui.failed.cb475070" = "%1$@ 실패: %2$@";`
  - `Sources/SVNCore/SVNClient.swift:1730`, `:1633` — 종료 코드가 0이 아니면 stderr를 그대로 담아 `.commandFailed`로 던진다.
  - `Sources/SVNCore/SVNClient.swift:1739` `isWorkingCopyOutOfDateError` — 앱 전체에서 SVN 오류 코드를 판별하는 곳은 **여기 한 군데**뿐이다(`E155011`, `E170004`). `grep -rn 'E1[0-9][0-9]' Sources`로 확인.
  - `Sources/SVNMac/ProjectStore.swift:1172` `handleRemoteError` — Keychain 접근 거부(`KeychainStoreError.isAccessDenied`)만 특별 처리하고, 나머지는 전부 `publishRefreshError` → `errorMessage`.
  - `Sources/SVNMac/DetailedErrorView.swift:58` — 표시하는 것은 제목 "오류", 원문 텍스트, "오류 세부 정보 복사", "닫기". 다음 행동 제시가 없다.
- 재현: **부분 재현.** 실제로 잠금 충돌을 만들어 SVN이 내는 문구를 확보했다:
  ```
  svn: E195022: File '/private/tmp/.../문서/보고서.txt' is locked in another working copy
  svn: E160037: Cannot verify lock on path '/문서/보고서.txt'; no matching lock-token available
  ```
  이 문자열이 `"svn commit 실패: <위 원문>"` 으로 화면에 뜬다는 것은 코드 경로 추적(`checkedRun` → `.commandFailed` → `localizedError` → `DetailedErrorView`) 기준 확인이다. 앱 실행으로는 확인하지 않았다.
- 증상: 터미널을 모르는 사용자가 영문 오류 코드를 본다. "닫기"를 누르면 아무 일도 일어나지 않고, `automaticRefreshBlockedProjectID`가 설정돼 자동 새로고침까지 멈춘다(`ProjectStore.swift:1198`). 사용자는 앱이 멈췄다고 판단한다.
- 발생 조건: 상시. 위에 적은 모든 발견과 이미 처리 중인 7건이 전부 이 경로로 끝난다.
- 막다른 길인가: **오류 자체가 막다른 길이 아니어도 이 문구 때문에 막다른 길이 된다.** 예: `E195022`(다른 작업본 잠금)는 원리상 잠금 해제로 풀리는데, 화면은 잠금 화면을 열라는 안내조차 하지 않는다. `E170001`(인증 실패)는 자격 증명 화면으로 가면 되는데(아래 항목) 그 안내가 없다.
- 고치는 범위: `SVNError`에 오류 코드 분류를 추가하거나(`SVNError.serverError(code:message:)`), `SVNErrorLocalization`에 코드 → 한국어 설명 + 다음 행동 매핑 테이블을 만든다. `DetailedErrorView`에 "권장 조치" 영역과 해당 화면으로 가는 버튼. 최소 커버 대상: E170001/E215004(인증), E170013/E180001(접속·URL), E175002/E230001(인증서), E195022/E160037/E160039(잠금), E155004/E155037(WC 잠김), E155011/E170004(구버전), E155036(WC 업그레이드), E200030(디스크·DB).

---

## 커밋 후 남는 잠금을 한 번에 풀 수 없다

- 심각도: **중간**
- 근거:
  - `svn help commit` 실제 출력: "If any targets are (or contain) locked items, those will be unlocked after a successful commit". 즉 **커밋 대상 경로의 잠금만** 풀린다.
  - `Sources/SVNCore/SVNClient.swift` `commit(at:paths:...)` — `normalizedPaths`만 `--targets`로 넘긴다. 선택하지 않은 경로의 잠금은 유지된다.
  - `Sources/SVNMac/ProjectStore+Locking.swift:155` `unlock(_ lock:)` — 잠금 하나씩만 해제한다. 여러 건 해제 API가 없다.
  - `Sources/SVNMac/RepositoryLocksView.swift:52` — `if lock.owner == store.selectedProject?.username` 일 때만 "내 잠금 해제" 버튼이 나온다. 목록 전체를 한 번에 푸는 버튼은 없다.
  - `Sources/SVNMac/ProjectStore+Locking.swift:16` `prepareToOpen` — 잠금은 "파일 열기"의 부작용으로만 걸린다. 즉 **열어본 파일 수만큼 잠금이 생긴다.**
- 재현: **코드 기준 추정.** 잠금 생성·해제·커밋 시 자동 해제는 실제 저장소로 확인했으나, 다중 잠금 누적 시나리오를 앱으로 돌려보지는 않았다.
- 증상: 사용자가 오전에 문서 8개를 열어보고(각각 잠금 획득) 그중 2개만 수정해 커밋하면, 나머지 6개 잠금이 남는다. 동료는 그 6개를 편집·커밋할 수 없다. 남은 잠금을 알아채려면 잠금 화면을 열어 목록을 보고 6번 클릭해야 한다.
- 발생 조건: `잠금 정책 = 항상 잠그고 열기`를 쓰는 팀이면 매일. `물어보기`여도 사용자가 습관적으로 "잠그고 열기"를 누르면 같다. 10명 팀이 몇 달 쓰면 잠금이 수십~수백 건 누적된다.
- 막다른 길인가: **아니다.** 하나씩 해제할 수단은 있다. 다만 소유자 이름이 `project.username`과 정확히 일치해야 버튼이 보이므로, 사용자명을 등록하지 않은 프로젝트(`username == nil`)에서는 **자기 잠금조차 해제 버튼이 나타나지 않는다.** 그 경우는 막다른 길이다(`unlock --force` 부재와 겹치지만 원인이 다르다 — 여기서는 UI가 버튼을 아예 숨긴다).
- 고치는 범위: `RepositoryLocksView`에 "내 잠금 모두 해제", `SVNClient.unlock`에 다중 경로(`--targets`) 지원. 그리고 `lock.owner == username` 판정을 `username == nil`일 때 어떻게 다룰지 결정(예: 소유자 표시 + "해제 시도" 허용).

---

## 명시적인 "이 파일 잠그기" 동작이 없다

- 심각도: **중간**
- 근거:
  - `grep -rn 'lockAndOpen' Sources/SVNMac` 결과 호출 지점은 `DocumentOpenConfirmation.swift:52`(열기 확인 시트의 버튼)와 `ProjectStore+Locking.swift:64,77`(정책에 따른 자동 호출) 뿐이다.
  - `Sources/SVNMac/ChangesView.swift:139~198` 컨텍스트 메뉴, `Sources/SVNMac/WorkingCopySplitBrowserView.swift:380~402` 컨텍스트 메뉴 모두 "잠그기" 항목이 없다. `WorkingCopySplitBrowserView.swift:385`에는 "잠금 해제"만 있다.
- 재현: **코드 기준 추정.** UI 전수 grep으로 확인.
- 증상: Finder에서 이미 열어놓은 엑셀 문서를 지금 잠그고 싶어도 앱에서 잠글 수 없다. 앱의 "파일 열기"를 다시 눌러야 하고, 그러면 문서가 한 번 더 열린다. 폴더 단위 선점 잠금(월말 마감 전 해당 폴더 잠그기)도 불가능하다.
- 발생 조건: 사용자가 Finder/최근 문서/메일 첨부로 파일을 여는 경우. 사무직 사용자에게는 오히려 이쪽이 기본 동작이다.
- 막다른 길인가: **아니다.** 앱에서 다시 열면 잠글 수 있다. 다만 우회 경로가 사용자에게 자명하지 않다.
- 고치는 범위: `ChangesView` / `WorkingCopySplitBrowserView` 컨텍스트 메뉴에 "잠그기" 추가, `ProjectStore+Locking`에 열기와 분리된 `lock(path:)`. 잠금 메시지를 사용자가 입력할 수 있으면 더 좋다(현재는 `"ui.editing.document.in.svn.kr.5e6ac9cc"` 고정 문자열, `ProjectStore+Locking.swift:88`).

---

## `switched` 상태가 화면에서 완전히 사라진다

- 심각도: **중간** (발생 확률은 낮음, 발생 시 조용히 잘못된 곳에 커밋됨)
- 근거:
  - `Sources/SVNCore/SVNXMLParser.swift` `WorkingCopyEntriesDelegate` — `wc-status`에서 `item`, `revision`, `tree-conflicted`만 읽는다. `switched` 속성을 읽지 않는다.
  - `Sources/SVNCore/SVNWorkingCopySnapshot.swift:267` `visibleStatuses` — `entry.status != "normal"`인 항목만 남긴다.
  - `SVNStatusKind`(`Sources/SVNCore/Models.swift:8`)에 switched 개념이 없다.
- 재현: **실제 재현함.** 임시 저장소에서 `svn switch`로 `문서` 하위 트리를 다른 저장소 경로로 전환한 뒤 XML을 확보했다:
  ```xml
  <entry path="문서">
  <wc-status props="none" switched="true" item="normal" revision="4">
  ```
  `item="normal"`이므로 `visibleStatuses`가 이 항목을 버린다. 앱은 "변경 없음"을 표시한다(앱 실행으로는 확인하지 않았다 — 파싱 코드 경로 기준).
- 증상: 하위 폴더가 저장소의 다른 경로를 가리키고 있는데 화면에는 아무 표시가 없다. 그 폴더에서 커밋하면 사용자가 생각한 위치가 아닌 곳으로 올라간다. 동료들에게는 파일이 "사라진" 것처럼 보인다. 루트에서 업데이트해도 그 하위 트리는 원위치로 돌아오지 않는다.
- 발생 조건: 앱은 `svn switch`를 실행하지 않으므로 앱 단독으로는 이 상태를 만들 수 없다. 누군가 터미널이나 다른 클라이언트로 switch 했거나, 예전에 `svn switch --relocate`를 쓴 작업 복사본을 가져온 경우. **이 팀에서는 확률 낮음.**
- 막다른 길인가: **그렇다.** 앱에 `switch`가 없어 원위치로 돌릴 수 없고, 애초에 이 상태임을 알려주지도 않는다. 상태를 보여주지도 않는다는 점에서 다른 발견보다 나쁘다.
- 고치는 범위: `WorkingCopyEntriesDelegate`가 `switched`를 읽고, `SVNWorkingCopyEntry`/`SVNStatusEntry`에 플래그를 실어 `visibleStatuses`가 `normal + switched`를 남기게 한다. 화면은 경고 배지로 충분하다(복구용 `switch`는 별도 판단).

---

## 서버 인증 실패가 자격 증명 입력창을 열지 않는다

- 심각도: **중간**
- 근거:
  - `Sources/SVNMac/ProjectStore.swift:1172` `handleRemoteError` — `authenticationRequest`를 세우는 조건은 `isKeychainAccessDenied(error)` 단 하나다.
  - `Sources/SVNMac/ProjectStore.swift:1216` `isKeychainAccessDenied` — `(error as? KeychainStoreError)?.isAccessDenied == true`. 즉 **macOS Keychain 거부**만 잡는다. 서버가 반환한 `E170001`/`E215004`는 여기 걸리지 않는다.
  - `Sources/SVNCore/SVNClient.swift:1762` — `--non-interactive`가 항상 붙으므로 SVN이 대화형으로 비밀번호를 묻는 경로도 없다.
- 재현: **코드 기준 추정.** 인증이 필요한 서버를 세우지 않았다.
- 증상: 서버 비밀번호가 만료·변경되면 `"svn log 실패: svn: E170001: Authentication failed"` 같은 영문 문구만 뜬다. 자격 증명 화면(`isShowingCredentials`)은 메뉴에서 따로 찾아 들어가야 한다. Keychain 거부일 때는 친절한 안내가 나오는데, 훨씬 흔한 "비밀번호 틀림"에는 안내가 없다.
- 발생 조건: 사내 계정 비밀번호 정책상 주기적 변경이 있으면 전원이 주기적으로 겪는다. **확률 중간~높음.**
- 막다른 길인가: **아니다.** 자격 증명 화면이 앱에 있다. 다만 오류 문구가 거기로 안내하지 않는다.
- 고치는 범위: `handleRemoteError`에 인증 오류 코드 판별 추가 → `authenticationRequest` 설정(기존 `resume(request)` 재개 흐름을 그대로 재사용할 수 있다). `SVNClient`에서 `E170001`/`E215004`/`E170013`+`authorization failed`를 구분해 던지는 것이 선행 조건.

---

## 요청 토큰을 거치지 않는 비동기 완료 경로들

- 심각도: **중간** (프로젝트 간 데이터 오염은 확인되지 않음)
- 근거: `canApplyRequest`를 쓰는 곳은 `refresh`, `diff`, `fileTree`, `repositoryLocks`, `conflictPreparation` 5종뿐이다(`ProjectRequestKind`, `ProjectStore.swift:68`). 아래는 `selectedProjectID == project.id`만 확인한다:
  - `Sources/SVNMac/ProjectStore.swift:999,1006,1016,1024` — `commit`
  - `Sources/SVNMac/ProjectStore+Update.swift:16,36` — `update`
  - `Sources/SVNMac/ProjectStore+Update.swift:50,59` — `previewUpdate`
  - `Sources/SVNMac/ProjectStore+Update.swift:108,124,143,155` — `confirmRepositoryTemporaryFileCleanup`
  - `Sources/SVNMac/ProjectStore+FileActions.swift:14,19,36,41` — `confirmRevert`, `loadFileHistory`
  - `Sources/SVNMac/ProjectStore+History.swift:61,66` — `loadMoreHistory`
  - `Sources/SVNMac/ProjectStore+Deletion.swift:51,66` — `confirmDeletion`
  - `Sources/SVNMac/ProjectStore+Locking.swift:34,50,98,103,165,169` — `prepareToOpen`, `lockAndOpen`, `unlock`
  - `Sources/SVNMac/ProjectStore+Ignore.swift` 전반, `ProjectStore+Recovery.swift` 전반
- 재현: **코드 기준 추정.**
- 증상: 요청을 시작한 프로젝트를 클로저가 캡처하고 있으므로 **다른 프로젝트의 상태를 덮는 경로는 찾지 못했다.** 실제 영향은 "같은 프로젝트로 돌아왔을 때 늦게 온 응답이 적용되는" 쪽이다. A → B → A로 빠르게 전환하면:
  - `loadFileHistory`의 지연 응답이 `isShowingFileHistory = true`로 파일 이력 시트를 갑자기 다시 띄운다.
  - `previewUpdate`의 지연 응답이 `isShowingUpdatePreview = true`로 업데이트 미리보기를 다시 띄운다. `resetSelectedProjectState()`(`ProjectStore.swift:1305`)가 이미 `updateState`를 비웠으므로 시트 내용과 목록이 어긋날 수 있다.
  - `confirmDeletion`의 지연 응답이 `selectedPaths.formUnion(...)`으로 **사용자가 선택하지 않은 경로를 커밋 체크박스에 자동 추가**한다(`ProjectStore+Deletion.swift:54`). 여기가 가장 나쁘다 — 커밋 대상이 사용자 의도 없이 늘어난다.
  - `loadMoreHistory`의 지연 응답이 새로 읽은 50건 위에 옛 페이지를 덧붙여 `hasMoreHistory` 판정을 흐트러뜨린다.
- 발생 조건: 원격 왕복이 느린 환경(사내 VPN, 프록시)에서 프로젝트를 빠르게 바꾸는 사용자. 흔하지 않다.
- 막다른 길인가: **아니다.** 새로고침하면 정상화된다. 다만 `confirmDeletion`의 자동 선택은 사용자가 알아채지 못한 채 커밋될 수 있다.
- 고치는 범위: `ProjectRequestKind`에 `commit`, `update`, `updatePreview`, `fileHistory`, `historyPage`, `deletion`, `lock` 추가하고 각 함수에서 `beginRequest`/`canApplyRequest`로 감싼다. `ProjectStore` 확장 파일들.

---

## `svn move` / `copy`가 없어 이름 변경이 이력을 끊는다

- 심각도: **중간**
- 근거: `Sources/SVNCore/SVNClient.swift`에서 `move`는 `normalizeRepositoryPaths`(파일 195~200)의 **저장소 URL → URL** 형태로만 쓰인다. 작업 복사본 경로 간 `move`/`copy`는 없다. 앱에서 이름 변경/이동 동작을 노출하는 화면도 없다(`ChangesView`, `WorkingCopySplitBrowserView` 컨텍스트 메뉴에 항목 없음).
- 재현: **코드 기준 추정.**
- 증상: 사용자가 Finder에서 `보고서.xlsx` → `보고서_최종.xlsx`로 바꾸면 앱은 "누락(조치 필요)" 1건 + "미버전" 1건으로 본다. 사용자가 각각 "저장소에서 삭제" + 체크 후 커밋해야 하고, 그러면 저장소에서는 삭제 + 신규 추가가 되어 **파일 이력이 끊긴다.** 이후 그 파일의 "파일 커밋 이력"에는 이름 변경 이전 기록이 나오지 않는다.
- 발생 조건: 사무 문서는 이름을 자주 바꾼다(`_최종`, `_v2`, `_20260825`, 연도별 폴더 정리). **확률 높음, 매주 수준.**
- 막다른 길인가: **아니다.** 파일은 정상적으로 올라간다. 잃는 것은 이력이고, 잃었다는 사실을 사용자가 알 방법이 없다. 조용한 손실이다.
- 고치는 범위: `SVNClient`에 작업 복사본 `move`. 앱은 "누락 + 미버전" 쌍을 이름 변경 후보로 탐지해 "이름 변경으로 처리(이력 유지)"를 제안할 수 있다. `SVNWorkingCopySnapshot` 탐지 + `ProjectStore` + `ChangesView`.

---

## 작업 복사본 메타데이터 형식이 오래되면 (`svn upgrade`) 복구할 수 없다

- 심각도: **낮음**
- 근거: `SVNClient`에 `upgrade`가 없다. `validateWorkingCopy`(`SVNClient.swift:72`)는 `info --show-item wc-root`가 0이 아니면 `SVNError.invalidWorkingCopy`를 던지고, 그 문구는 "선택한 폴더가 SVN 로컬 작업 복사본이 아닙니다"다(`SVNErrorLocalization.swift:13`).
- 재현: **코드 기준 추정.** 구버전 svn으로 만든 작업 복사본을 준비하지 않았다.
- 증상: SVN 1.6/1.7 시절 작업 복사본(백업에서 복원, 오래 쓴 공유 폴더)을 등록하면 `E155036: Working copy ... is too old`가 나는데, 앱은 "작업 복사본이 아니다"로 잘못 안내한다. 원인이 다른데 문구가 같아 사용자가 진단할 수 없다.
- 발생 조건: 낮다. 앱은 svn 1.14를 번들하므로 앱이 만든 작업 복사본에는 발생하지 않는다. 외부에서 온 작업 복사본만 해당.
- 막다른 길인가: **그렇다.** 앱 안에 `upgrade`가 없고 오류 문구도 오해를 유발한다.
- 고치는 범위: `SVNClient.upgrade` 추가 + `validateWorkingCopy`에서 `E155036`을 구분해 "형식 업그레이드가 필요합니다. 진행할까요?"로 안내.

---

## 예약-추가만 있는 폴더를 프로젝트로 등록하면 모든 새로고침이 실패한다

- 심각도: **낮음**
- 근거:
  - `Sources/SVNCore/SVNWorkingCopySnapshot.swift:121` — `let revisions = entries.compactMap(\.revision).compactMap(Int.init).filter { $0 >= 0 }` / `guard let minimum = ..., let maximum = ... else { throw SVNError.malformedResponse }`
  - `Sources/SVNCore/SVNXMLParser.swift:62` `workingCopyRevision`도 같은 구조로 `.malformedResponse`를 던진다.
  - `Sources/SVNCore/SVNClient.swift:72` `validateWorkingCopy` — `info --show-item wc-root`만 본다. 예약-추가 폴더에서도 성공한다.
- 재현: **SVN 출력은 실제 재현함, 앱 동작은 코드 기준 추정.** 작업 복사본 안에 폴더를 만들고 `svn add`만 한 뒤 그 폴더에서:
  ```
  $ svn info --show-item wc-root     → /private/tmp/svnaudit/wc   (exit 0, 등록 검증 통과)
  $ svn status --verbose --no-ignore --xml
    <wc-status item="added" revision="-1" props="none">   (모든 entry가 -1)
  ```
  즉 `revisions`가 빈 배열이 되어 `SVNWorkingCopySnapshot(entries:)`가 던진다.
- 증상: 등록은 성공하는데 이후 모든 새로고침이 `"SVN 응답을 읽을 수 없습니다."`로 끝난다. 변경 목록은 영구히 비어 있고, `automaticRefreshBlockedProjectID`가 걸려 자동 새로고침도 멈춘다. 원인 정보가 0이다.
- 발생 조건: 커밋되지 않은 예약-추가 하위 폴더를 별도 프로젝트로 등록하는 경우. 커밋 중 실패 후 `commit`의 롤백(`SVNClient.swift:1315`, `try? await ... revert`)까지 실패하면 그런 폴더가 남는다. 부서별로 하위 폴더를 각각 프로젝트로 등록하는 사용 패턴이면 마주칠 수 있다. **확률 낮음.**
- 막다른 길인가: **그렇다.** 앱이 원인을 말해주지 않고, 프로젝트를 지우는 것 외에 할 수 있는 것이 없다.
- 고치는 범위: `SVNWorkingCopySnapshot(entries:)`에서 리비전이 하나도 없을 때 `.malformedResponse` 대신 의미 있는 오류(예: `notYetCommittedRoot`)를 던지고, `validateWorkingCopy`가 등록 시점에 걸러내는 게 낫다.

---

## `svn:externals` 항목이 파싱 단계에서 버려진다

- 심각도: **낮음**
- 근거:
  - `Sources/SVNCore/SVNXMLParser.swift:12` 주석 — "정상 항목과 external은 UI에 표시할 필요가 없으므로 파싱 단계에서 제거합니다."
  - `StatusDelegate`: `if rawItem != "normal" && rawItem != "external"`
  - `SVNWorkingCopySnapshot.visibleStatuses:268`: `entry.status != "external"`
  - `SVNWorkingCopyEntry.isVersioned`(`Models.swift`)도 `external`을 비버전으로 취급한다.
  - `SVNClient.update`에 `--ignore-externals`가 없으므로 외부 참조는 실제로 내려온다.
- 재현: **코드 기준 추정.** externals를 쓰는 저장소를 만들지 않았다.
- 증상: 저장소에 `svn:externals`가 걸려 있으면 그 하위 트리가 디스크에는 있는데 앱 화면에는 없다. 그 안의 파일을 수정해도 앱은 변경을 표시하지 않고, 커밋할 수도 없다.
- 발생 조건: 이 팀이 externals를 쓸 이유는 낮다. 다만 관리자가 공용 서식 폴더를 externals로 각 부서 폴더에 붙이는 구성은 사무 환경에서도 있다. **확률 낮음.**
- 막다른 길인가: **그렇다** — 해당 트리에 대해서는 앱으로 아무것도 할 수 없다. 다만 그 트리가 앱의 관리 범위가 아니라는 설계 의도로 볼 수도 있다.
- 고치는 범위: 최소한 "외부 참조 폴더" 배지로 존재를 알리고, 그 안은 편집 대상이 아니라고 명시. 완전 지원은 별도 판단.

---

## 심볼릭 링크는 잠금 확인 없이 열린다

- 심각도: **낮음**
- 근거:
  - `Sources/SVNCore/SVNClient.swift:410` `nodeKind(at:)` — `S_IFREG`/`S_IFDIR`만 매핑하고 나머지는 `nil`. 심볼릭 링크는 `nil`.
  - `Sources/SVNMac/ChangesView.swift:147` — `isRegularFile: entry.nodeKind == .file` → 심볼릭 링크는 `false`.
  - `Sources/SVNMac/ProjectStore+Locking.swift:22` — `guard isVersioned, isRegularFile else { openFile(...); return }` → 잠금 확인을 건너뛰고 바로 연다.
- 재현: **코드 기준 추정.**
- 증상: 저장소에 `svn:special` 심볼릭 링크가 있으면 잠금 확인 없이 열린다. 링크 대상 파일이 남의 잠금 상태여도 안내가 없다.
- 발생 조건: 사무 문서 저장소에 심볼릭 링크가 들어갈 이유가 거의 없다. **확률 매우 낮음.**
- 막다른 길인가: 아니다.
- 고치는 범위: `nodeKind(at:)`에 `S_IFLNK` 분기, `prepareToOpen`의 조건. 지금 상태로 두는 것도 합리적이다.

---

## 커밋 시 NFC 디스크 이름 변경이 열려 있는 문서의 경로를 바꾼다

- 심각도: **낮음** (추정, 검증 필요)
- 근거:
  - `Sources/SVNCore/SVNPathNormalization.swift:11` `normalizeNewPaths` — 추가 대상 경로와 그 하위 항목을 **디스크에서 NFC 이름으로 실제 rename** 한다.
  - `Sources/SVNCore/SVNClient.swift:1254` — 커밋 경로에서 `additions`가 있을 때 호출된다.
- 재현: **코드 기준 추정. 확인하지 않았다.** Excel/한글로 실제 문서를 열어놓고 커밋하는 시나리오를 돌리지 않았다.
- 증상(예상): 사용자가 Excel에서 새 파일을 저장한 뒤 Excel을 닫지 않고 앱에서 커밋하면, 커밋 직전에 그 파일이 NFC 이름으로 rename 된다. Excel이 다음 저장 시 기억한 경로에 원자적 교체를 시도하면 경로가 없어 실패하거나 NFD 이름 파일을 새로 만들 수 있다.
- 발생 조건: 새로 만든 한글 이름 문서를 열어둔 채 커밋. 사무직 사용자에게는 흔한 순서다. 다만 실제로 문제가 되는지는 확인 안 했다.
- 막다른 길인가: 판단 보류 — 재현 전에 단정할 수 없다.
- 고치는 범위: 먼저 재현 테스트가 필요하다. 문제가 확인되면 rename 전에 해당 경로가 다른 프로세스에 열려 있는지 확인하고 사용자에게 알리는 계층.

---

## 발견하지 못한 것

명시적으로 적어둔다.

- **프로젝트 간 상태 오염**: 늦게 온 응답이 *다른* 프로젝트의 상태를 덮는 경로는 찾지 못했다. 모든 비동기 클로저가 시작 시점의 `project`를 캡처하고 `selectedProjectID == project.id`를 확인한다. 위의 토큰 항목은 같은 프로젝트 내 지연 응답 문제다.
- **커밋의 부분 실패**: SVN 커밋은 원자적이고, `SVNClient.commit`(`SVNClient.swift:1311~1343`)은 이 커밋이 예약한 `add`만 롤백하고 기존 예약은 건드리지 않는다. 커밋 성공 후 검증 실패는 `commitSucceededWithValidationWarning`으로 revert 없이 알린다(`SVNClient.swift:1345` 주석). 이 부분 설계는 타당하다. 유일한 구멍은 롤백 자체가 실패할 때 `try?`로 조용히 넘기는 것(`SVNClient.swift:1316`)이고, 그 결과 상태는 위 "예약-추가 루트" 항목과 겹친다.
- **충돌 해결의 백업**: `ConflictFileService`가 작업 파일을 작업 복사본 밖으로 백업하고 검증까지 한다(`ConflictFileError.workingRecoveryVerificationFailed` 등). 파괴적 동작 중 이 경로는 보호가 잘 돼 있다.
- **한글 NFD/NFC 경로**: `SVNClient`가 원문 UTF-8 바이트를 `--targets` 파일과 `/bin/sh` 우회로 운반하고, `SVNPathIdentity`가 바이트 단위 동등성을 쓴다. 새로 발견한 누락 지점은 없다. UI 계층의 문자열 비교(`selectedPaths.contains`, `statuses.first(where:)`)는 Swift `String` 동등성이 정규화 동등을 같게 취급하므로 문제 없다.
- **`revert`의 확인 강도**: `RevertConfirmation.swift`가 `role: .destructive`와 "되돌릴 수 없다"는 문구로 확인받는다. 백업은 없지만, `svn revert`에 백업을 붙이는 것은 SVN 자체 동작을 넘는 설계 결정이므로 결함으로 보지 않았다.

---

# 2부 — SVN CLI 기능 중 앱에 누락된 것 전수 조사

기준: `/opt/homebrew/bin/svn` 1.14.5의 `svn help` 출력.
`svn help`가 나열하는 하위 명령 39개 중 앱이 실행하는 것은 다음 14개다:
`checkout`, `info`, `list`, `status`, `log`, `diff`, `cat`, `add`, `commit`, `delete`, `revert`, `resolve`, `lock`, `unlock`, `update`, `propget`, `propset`, `propdel`, `move`(저장소 URL 간).
(`help`, `resolved`(폐기), `praise`/`ann`(별칭) 제외)

이미 처리 중인 5건(`cleanup`, `unlock --force`, `resolve` 관련, 속성 충돌, `obstructed`)은 이 목록에서 생략했다.

---

## svn relocate

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 저장소 루트 URL이 문법적으로만 바뀌었을 때 작업 복사본 메타데이터의 URL을 다시 쓴다.
- 없어서 생기는 상황: 사내 파일 서버를 새 NAS로 교체하거나 `http://192.168.0.10/svn` → `https://svn.company.co.kr/svn`로 바꾸면, 그날부터 전 직원의 앱이 `E170013`으로 멈춘다. 미커밋 상태로 편집 중이던 엑셀·한글 문서를 앱이 옮겨줄 수 없다.
- 실제로 겪을 확률: **중간.** 몇 년에 한 번이지만 발생 시 전원 동시 마비다. 서버 이전·HTTPS 도입은 사내 IT의 정상적인 개선 활동이다.
- 대체 수단: **없다.** 프로젝트 삭제 후 새 URL로 체크아웃하는 것뿐이고, 미커밋 변경은 사용자가 Finder로 손수 옮겨야 한다.

## svn switch

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 작업 복사본을 같은 저장소의 다른 경로(브랜치/태그)로 옮긴다.
- 없어서 생기는 상황: 이 팀은 브랜치를 쓰지 않을 것이므로 정상 용도로는 필요가 없다. 문제는 **누군가 이미 switch 해놓은 작업 복사본**을 앱이 인식조차 못 하고(1부 참조) 되돌릴 수도 없다는 점이다.
- 실제로 겪을 확률: **낮음.** 앱만 쓰면 이 상태가 생기지 않는다.
- 대체 수단: 없다. 프로젝트 재체크아웃.

## svn upgrade

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 오래된 형식의 작업 복사본 메타데이터를 현재 svn 형식으로 올린다.
- 없어서 생기는 상황: 백업에서 복원한 옛 작업 복사본, 또는 오래 방치된 공유 폴더를 등록하면 `E155036`이 나는데 앱은 "SVN 작업 복사본이 아닙니다"로 오안내한다.
- 실제로 겪을 확률: **낮음.** 앱이 svn 1.14를 번들하므로 앱이 만든 작업 복사본에는 발생하지 않는다.
- 대체 수단: 없다. 재체크아웃.

## svn merge / mergeinfo

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 저장소의 변경 집합을 작업 복사본에 적용한다. `svn merge -c -N`이 **"커밋한 리비전 하나를 취소"** 하는 표준 방법이다.
- 없어서 생기는 상황: "어제 올린 r412를 취소해 주세요"를 앱으로 할 수 없다. 브랜치 병합 용도는 이 팀에 불필요하지만 **커밋 취소 용도는 필수에 가깝다.**
- 실제로 겪을 확률: **높음** (커밋 취소 용도). 브랜치 용도는 낮음.
- 대체 수단: 없다. 1부 "이전 리비전 복원 수단 전무" 항목과 같은 구멍이다.

## svn cat --revision / svn export --revision

- 앱 지원: **없음** (`cat`은 내부 비교용 `--revision BASE`로만 존재, 공개 API 아님)
- 이 명령이 존재하는 이유: 임의 리비전의 파일 내용을 꺼낸다.
- 없어서 생기는 상황: 3일 전 버전의 `월간보고.xlsx`를 꺼내볼 수 없다. 이력 화면에서 diff만 보이는데 xlsx·hwp는 바이너리라 diff가 "텍스트 차이 없음"으로 나온다. 즉 **이력이 사실상 읽기 불가**다.
- 실제로 겪을 확률: **높음.** 매주 수준. 사무직 팀이 버전관리를 도입한 첫째 이유다.
- 대체 수단: 없다.

## svn copy (작업 복사본 / URL → WC)

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 이력을 유지한 복사, 태그·브랜치 생성, 그리고 `svn copy -r <옛리비전> <URL> <WC경로>`로 **삭제된 파일 되살리기**.
- 없어서 생기는 상황: 실수로 커밋한 삭제를 되살릴 수 없다. "작년 서식 폴더를 복사해서 올해 폴더 만들기"도 이력 없는 신규 추가가 된다.
- 실제로 겪을 확률: **중간.** 삭제 되살리기는 종종 생긴다. 연도별 폴더 복제는 연 1회 수준.
- 대체 수단: Finder로 복사한 뒤 신규 추가로 커밋. 파일은 살지만 이력은 끊긴다. 저장소에서 이미 삭제되어 로컬에도 없는 파일은 되살릴 수 없다.

## svn move (작업 복사본)

- 앱 지원: **없음** (저장소 URL 간 `move`만, 한글 이름 정규화 전용)
- 이 명령이 존재하는 이유: 이력을 유지한 이름 변경·이동.
- 없어서 생기는 상황: 1부 항목 참조. 이름을 바꿀 때마다 이력이 조용히 끊긴다.
- 실제로 겪을 확률: **높음.** `_최종`, `_v2`, 날짜 접미사 붙이기는 사무 문서의 일상이다.
- 대체 수단: 삭제 + 추가로 결과는 나온다. 이력만 잃고, 잃었다는 사실을 앱이 알려주지 않는다.

## svn update --revision

- 앱 지원: **부분.** `update`는 있으나 `--revision`이 없다(`SVNClient.swift` `update(at:)`는 `["update"]` 뿐).
- 이 명령이 존재하는 이유: 작업 복사본을 특정 과거 리비전으로 맞춘다.
- 없어서 생기는 상황: "지난주 금요일 상태로 폴더 전체를 되돌려 확인하고 싶다"가 불가능하다.
- 실제로 겪을 확률: **낮음.** 사무직 사용자가 요구할 형태는 파일 단위 복원(위 `cat -r`)이지 작업 복사본 전체 되감기가 아니다.
- 대체 수단: 없다.

## svn update --accept

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 업데이트 중 발생하는 충돌을 대화 없이 일괄 해결한다.
- 없어서 생기는 상황: 충돌 파일이 20개 생기면 앱의 충돌 해결 시트를 20번 반복해야 한다.
- 실제로 겪을 확률: **낮음.** 잠금 워크플로를 쓰면 대량 충돌 자체가 드물다.
- 대체 수단: 앱의 파일별 충돌 해결이 있다. 느리지만 막히지는 않는다. **학술적 누락에 가깝다.**

## svn update --force

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 미버전 파일이 들어오는 파일과 이름이 겹칠 때 실패하지 않고 로컬 내용을 로컬 수정으로 취급한다.
- 없어서 생기는 상황: 재현해 봤더니 svn 1.14는 이 상황을 실패가 아니라 **트리 충돌**로 만든다:
  ```
  D     C 문서/신규.txt
        >   local file unversioned, incoming file add upon update
  ```
  트리 충돌 처리는 이미 수정된 항목이므로, `--force` 없이도 앱 안에서 풀린다.
- 실제로 겪을 확률: 상황 자체는 **높음**(같은 이름의 파일을 두 사람이 각자 만드는 일은 흔하다). 하지만 `--force` 부재 때문에 막히지는 않는다.
- 대체 수단: 트리 충돌 해결 흐름. **학술적 누락.**

## svn checkout --depth / --revision

- 앱 지원: **부분.** `checkout`은 있으나 `--depth`, `--revision`이 없다(`SVNClient.swift:64`, `RepositoryDialogs.swift:158`).
- 이 명령이 존재하는 이유: 큰 저장소의 일부만(희소 체크아웃) 또는 특정 리비전을 내린다.
- 없어서 생기는 상황: 부서 폴더 하나만 필요한데 회사 전체 문서 저장소가 수십 GB면 전부 내려온다. 다만 사용자가 하위 폴더의 URL을 직접 입력하면 그 폴더만 체크아웃할 수 있으므로 완전히 막히지는 않는다.
- 실제로 겪을 확률: **중간.** 저장소 하나에 전 부서 문서를 넣는 구성이면 곧바로 문제가 된다.
- 대체 수단: 하위 폴더 URL을 직접 입력. 사용자가 URL 구조를 알아야 한다.

## svn update --set-depth

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 이미 만든 작업 복사본의 depth를 바꾼다(폴더 제외/포함).
- 없어서 생기는 상황: 다 내려받은 뒤 "이 폴더는 안 받겠다"가 불가능하다.
- 실제로 겪을 확률: **낮음.** 위 항목이 해결되면 필요도 낮아진다.
- 대체 수단: 재체크아웃.

## svn propset / propget / proplist (svn:ignore 외)

- 앱 지원: **부분.** `svn:ignore`와 `svn:global-ignores`만 읽고 쓴다(`SVNIgnorePropertyKind`, `Models.swift:50`). 다른 속성은 조회도 설정도 불가.
- 이 명령이 존재하는 이유: `svn:needs-lock`(바이너리 문서를 잠금 없이 편집하지 못하게 읽기 전용으로 만든다), `svn:mime-type`, `svn:executable`, `svn:externals` 등을 관리한다.
- 없어서 생기는 상황: **`svn:needs-lock`이 이 팀의 핵심이다.** 이 속성이 없으면 사용자가 잠금 없이 엑셀 문서를 편집할 수 있고 커밋 시점에야 충돌을 발견한다. 있으면 파일이 읽기 전용이라 Excel이 먼저 경고한다. 앱은 이 속성을 설정할 수도, 어느 파일에 걸려 있는지 보여줄 수도 없다.
- 실제로 겪을 확률: **높음.** 잠금 공유 워크플로를 쓰는 팀에게 `svn:needs-lock`은 표준 구성이다. 이걸 앱으로 켤 수 없으면 잠금 정책이 반쪽이다.
- 대체 수단: 없다. 관리자가 터미널이나 TortoiseSVN으로 설정해야 한다.

## svn propedit

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 속성 값을 에디터로 편집한다.
- 없어서 생기는 상황: `svn:ignore` 편집은 앱의 무시 규칙 화면으로 대체된다.
- 실제로 겪을 확률: **낮음.**
- 대체 수단: 있다(무시 규칙 화면). **학술적 누락.**

## svn commit --no-unlock / --keep-locks

- 앱 지원: **없음** (항상 기본 동작 = 커밋 대상의 잠금 해제)
- 이 명령이 존재하는 이유: 커밋 후에도 잠금을 유지해 연속 작업을 보호한다.
- 없어서 생기는 상황: 중간 저장을 커밋하면 잠금이 풀려 동료가 끼어들 수 있다. "오늘 하루 이 문서는 제가 잡고 있겠습니다"가 불가능하다.
- 실제로 겪을 확률: **중간.** 하루에 여러 번 저장·커밋하는 문서(진행 중 보고서)에서 실제로 문제가 된다.
- 대체 수단: 커밋 후 다시 잠그기 — 그런데 명시적 잠금 동작이 없다(1부 항목). 파일을 앱에서 다시 열어야 한다.

## svn lock --force / 다중 대상

- 앱 지원: **부분.** `lock`은 단일 경로 + 고정 메시지만(`SVNClient.swift:503`, `ProjectStore+Locking.swift:88`). `--force`(잠금 가로채기)도, `--targets`(다중)도 없다.
- 이 명령이 존재하는 이유: `--force`는 방치된 남의 잠금을 가져온다. 다중 대상은 폴더 단위 선점.
- 없어서 생기는 상황: 퇴사자나 휴가자가 잠금을 걸어놓은 문서를 아무도 편집할 수 없다. 월말 마감 전에 폴더 하나를 선점하려면 파일을 하나씩 열어야 한다.
- 실제로 겪을 확률: **중간~높음.** 퇴사·장기휴가는 사무 조직의 정상 사건이다. (`unlock --force`는 이미 처리 중이지만 `lock --force`는 별개다.)
- 대체 수단: `unlock --force`가 들어오면 "풀고 다시 잠그기" 2단계로 대체 가능. 그때까지는 없다.

## svn blame

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 텍스트 파일의 줄마다 마지막 변경 리비전·작성자를 표시한다.
- 없어서 생기는 상황: xlsx·hwp는 바이너리라 blame이 무의미하다. 텍스트 파일(csv, txt, 스크립트)에만 쓸모가 있다.
- 실제로 겪을 확률: **낮음.** 이 팀의 파일 구성상 거의 필요 없다.
- 대체 수단: 파일 커밋 이력이 있다. **학술적 누락.**

## svn export

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: `.svn` 없는 깨끗한 사본을 만든다.
- 없어서 생기는 상황: "이 폴더 전체를 외부 업체에 메일로 보내야 한다"를 할 때 `.svn`이 딸려간다. Finder로 복사하고 `.svn`을 지우면 되지만 사용자는 숨은 폴더의 존재를 모른다. 특정 리비전 시점의 전체 스냅샷 추출도 불가능하다.
- 실제로 겪을 확률: **중간.** 외부 공유는 사무직 업무의 일상이다.
- 대체 수단: Finder 복사 + `.svn` 수동 삭제. 사용자가 알아서 하기는 어렵다.

## svn import

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 버전관리되지 않은 폴더 트리를 저장소에 한 번에 올린다.
- 없어서 생기는 상황: 새 부서 폴더를 저장소에 처음 올릴 때. 다만 체크아웃 → 파일 복사 → 커밋으로 같은 결과를 낼 수 있고, 앱은 이 경로를 지원한다.
- 실제로 겪을 확률: **낮음** (초기 구축 시 1회, 보통 관리자가 한다).
- 대체 수단: 있다(체크아웃 후 복사 + 커밋). **학술적 누락.**

## svn mkdir

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 버전관리 디렉터리를 만든다(특히 URL 대상으로 서버에 직접).
- 없어서 생기는 상황: Finder에서 폴더를 만들고 파일을 넣어 커밋하면 앱이 `add --parents`로 처리한다. **빈 폴더**만 문제인데, 빈 폴더는 어차피 올릴 이유가 적다.
- 실제로 겪을 확률: **낮음.**
- 대체 수단: 있다. **학술적 누락.**

## svn patch

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: unidiff 패치를 적용한다.
- 없어서 생기는 상황: 개발 워크플로 도구다. 사무 문서 팀에는 쓸 곳이 없다.
- 실제로 겪을 확률: **매우 낮음.**
- 대체 수단: 해당 없음. **학술적 누락.**

## svn changelist

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: 변경 파일을 이름 붙인 묶음으로 나눠 부분 커밋을 관리한다.
- 없어서 생기는 상황: 앱은 체크박스로 커밋 대상을 고르므로 실질적으로 대체된다. 다만 그 선택이 저장되지 않아 앱을 다시 켜면 잃는다.
- 실제로 겪을 확률: **낮음.**
- 대체 수단: 체크박스 선택. **거의 학술적 누락.**

## svn auth

- 앱 지원: **없음**
- 이 명령이 존재하는 이유: svn이 캐시한 인증 정보를 나열·삭제한다.
- 없어서 생기는 상황: 앱 전용 config 디렉터리(`Application Support/.../Subversion/auth`)에 잘못된 자격 증명이 캐시되면, 앱에는 그것을 지울 수단이 없다. 비밀번호가 있는 경우에는 `--no-auth-cache`가 붙어 캐시가 남지 않지만(`SVNClient.swift:1771`), 사용자명만 등록하고 비밀번호는 등록하지 않은 프로젝트에서는 캐시가 사용된다.
- 실제로 겪을 확률: **낮음.** 앱의 기본 흐름(사용자명 + 비밀번호를 Keychain에)에서는 캐시를 안 쓴다.
- 대체 수단: 없다(디렉터리 경로를 앱이 알려주지 않으므로 Finder로도 찾기 어렵다).

## svn info (원격 대상 / --revision)

- 앱 지원: **부분.** `info`를 많이 쓰지만 저장소 URL 대상 조회는 인증 검증(`verifyCredentials`)과 잠금 조회(`lockInfo`, `--revision HEAD`)에만 쓴다. 사용자가 저장소를 둘러보는 화면이 없다.
- 이 명령이 존재하는 이유: 임의 대상의 메타데이터 조회.
- 없어서 생기는 상황: 사용자가 자기 프로젝트의 저장소 URL을 확인할 방법이 없다. 관리자와 통화하며 "지금 어디에 연결돼 있나요?"에 답할 수 없다. 문제 진단이 어려워진다.
- 실제로 겪을 확률: **중간** (지원 요청 시).
- 대체 수단: 없다. 저장소 URL을 표시하는 화면이 없다.

## svn list (저장소 탐색)

- 앱 지원: **부분.** `list --recursive --xml`을 한글 경로 정규화에만 쓴다(`SVNClient.swift:88`, `:158`). 사용자용 저장소 탐색 화면은 없다.
- 이 명령이 존재하는 이유: 체크아웃 전에 저장소 구조를 본다.
- 없어서 생기는 상황: 체크아웃 다이얼로그에서 URL을 직접 타이핑해야 한다(`RepositoryDialogs.swift:158`의 플레이스홀더가 `https://server/svn/project/trunk`). 어떤 폴더가 있는지 앱으로 볼 수 없어 오타나 잘못된 경로로 실패한다. 위 `checkout --depth` 대체 수단("하위 폴더 URL 직접 입력")도 이것 때문에 어렵다.
- 실제로 겪을 확률: **중간~높음.** 신규 직원이 프로젝트를 처음 등록할 때마다.
- 대체 수단: 없다. 관리자가 URL을 문자로 알려줘야 한다.

## svn status --show-updates (부분 지원)

- 앱 지원: **부분.** `status --show-updates --xml`은 쓰지만 `RemoteChangesDelegate`(`SVNXMLParser.swift`)가 `repos-status`의 `item`/`props`만 읽는다. `switched`, `<lock>`은 `StatusLocksDelegate`가 따로 처리하고, 로컬 `wc-status`의 `<lock>`(내가 이 작업본에서 쥔 잠금)은 어디서도 읽지 않는다.
- 이 명령이 존재하는 이유: 서버와의 차이 + 서버 잠금 상태를 한 번에 본다.
- 없어서 생기는 상황: 변경 목록에서 "이 파일은 내가 잠갔다"는 표시가 없다. 잠금 화면을 따로 열어야 하고, 그 화면은 네트워크 왕복을 한다.
- 실제로 겪을 확률: **중간.**
- 대체 수단: 잠금 화면. 불편하지만 막히지는 않는다.

## svn diff (리비전 범위 / 두 URL 비교)

- 앱 지원: **부분.** 로컬 diff(`diff`, `diff <경로>`)와 단일 리비전 diff(`diff --change`)만 있다(`SVNClient.swift` `diff`, `revisionDiff`). `-r N:M` 범위, `--old`/`--new`, URL 간 비교가 없다.
- 이 명령이 존재하는 이유: 임의 두 시점·두 위치를 비교한다.
- 없어서 생기는 상황: "지난주 금요일부터 지금까지 뭐가 바뀌었나"를 한 번에 볼 수 없다. 리비전을 하나씩 눌러 봐야 한다.
- 실제로 겪을 확률: **낮음.** 바이너리 문서라 diff 자체의 효용이 낮다.
- 대체 수단: 리비전별 diff를 순차 확인. **거의 학술적 누락.**

## svn log (경로 지정 / 리비전 범위 / --stop-on-copy)

- 앱 지원: **부분.** 프로젝트 전체 `log`와 파일 단위 `fileLog`가 있다. `--revision` 범위는 페이지네이션용으로만 쓰고(`log(at:limit:endingAtRevision:)`), 날짜 지정(`-r {DATE}`), 검색, `--stop-on-copy`가 없다.
- 이 명령이 존재하는 이유: 이력 조회.
- 없어서 생기는 상황: 커밋 메시지·작성자·날짜로 이력을 검색할 수 없다. 저장소가 수천 리비전이면 "더 보기"를 수십 번 눌러야 옛 기록에 닿는다(50건씩, `ProjectStore.swift:876`).
- 실제로 겪을 확률: **중간.** 저장소가 오래될수록 확실히 문제가 된다.
- 대체 수단: "더 보기" 반복. 실질적으로 옛 이력에는 도달 못 한다.

## svn delete --keep-local

- 앱 지원: **없음** (항상 `delete --force`, `SVNClient.swift:686`, `:717`)
- 이 명령이 존재하는 이유: 저장소에서만 지우고 로컬 파일은 남긴다.
- 없어서 생기는 상황: 앱의 삭제 대상은 이미 디스크에서 사라진 `missing` 항목이므로(`canScheduleRepositoryDeletion`) 로컬을 남길 파일이 없다. 예외는 `scheduleRepositoryCleanupDeletion`(임시파일 정리)인데 여기서는 지우는 것이 목적이다.
- 실제로 겪을 확률: **매우 낮음.**
- 대체 수단: 해당 없음. **학술적 누락.**

## svn resolve --accept base / mine-conflict / theirs-conflict

- 앱 지원: **부분.** `SVNConflictChoice`(`Models.swift:143`)는 `working`, `mine-full`, `theirs-full` 3개다. `base`, `mine-conflict`, `theirs-conflict`, `recommended`가 없다.
- 이 명령이 존재하는 이유: 충돌 해결 방식 선택.
- 없어서 생기는 상황: 바이너리 문서는 부분 병합(`*-conflict`)이 불가능하므로 `mine-full`/`theirs-full`이 전부다. `base`(업데이트 전 서버 버전)가 필요한 경우는 드물다.
- 실제로 겪을 확률: **낮음.** 최근 커밋(`85aa631 merge: 충돌 해결 선택지 단순화`)이 의도적으로 줄인 것으로 보인다.
- 대체 수단: 있다. **학술적 누락, 의도된 설계.**

---

# 3부 — 이 팀이 실제로 겪을 확률이 높은 순 상위 10

CLI 누락과 1부 발견을 함께 순위화했다. 기준은 "이 팀 워크플로에서 실제로 사용자가 멈추는가 × 얼마나 자주".

| # | 항목 | 왜 이 순위인가 | 막다른 길 |
|---|---|---|---|
| 1 | **이전 리비전 복원 수단 전무** (`cat -r` / `export -r` / `merge -c -` / `copy -r` 모두 없음) | 사무직 팀이 버전관리를 쓰는 첫째 이유. 실수 저장·덮어쓰기는 매주 생긴다. xlsx·hwp는 diff도 무의미해서 이력 화면이 사실상 읽기 불가. | 그렇다 |
| 2 | **모든 실패가 영문 원문 덤프로 끝난다** | 상시. 이미 처리 중인 7건을 포함해 모든 실패가 이 경로로 나온다. 오류 코드별 안내가 앱 전체에 0건(`isWorkingCopyOutOfDateError` 하나 예외). | 원인에 따라 |
| 3 | **`svn:needs-lock` 등 속성을 설정·조회할 수 없다** | 잠금 공유 워크플로의 표준 구성 요소. 없으면 사용자가 잠금 없이 편집하고 커밋 시점에야 충돌을 발견한다. 잠금 정책이 반쪽이 된다. | 그렇다(관리자 개입 필요) |
| 4 | **작업 복사본 `svn move` 없음 — 이름 변경이 이력을 끊는다** | `_최종`, `_v2`, 날짜 접미사는 사무 문서의 일상. 주 단위. 손실이 조용하다는 점이 더 나쁘다. | 아니다(조용한 손실) |
| 5 | **커밋 후 남는 잠금 / 명시적 잠그기 없음 / `lock --force` 없음** | 매일. 열어본 파일 수만큼 잠금이 쌓이고, 커밋은 선택 경로만 풀어준다. 퇴사·휴가자 잠금은 앞으로도 못 푼다. 사용자명 미등록 프로젝트는 자기 잠금도 해제 버튼이 안 뜬다. | 일부 그렇다 |
| 6 | **저장소 탐색(`list`) 화면 없음 + 저장소 URL 표시 없음** | 신규 직원 등록마다. 관리자와의 문제 진단 통화마다. URL을 타이핑해야 하고 지금 어디 붙어 있는지 볼 수 없다. | 아니다(관리자 개입) |
| 7 | **서버 인증 실패가 자격 증명 화면으로 안내하지 않는다** | 사내 비밀번호 정책상 주기적 변경이 있으면 전원이 주기적으로. Keychain 거부만 안내되고 훨씬 흔한 "비밀번호 틀림"은 영문 원문. | 아니다(안내 부재) |
| 8 | **`svn relocate` 없음** | 발생 빈도는 낮지만 발생 시 전원 동시 마비 + 미커밋 작업분 손실 위험. 서버 이전·HTTPS 도입은 정상적인 IT 활동. | 그렇다 |
| 9 | **만료 인증서를 "신뢰" 토글로 통과할 수 없다** | 자체 서명 인증서를 쓰면 유효기간(보통 1년) 만료가 **반드시** 온다. 토글이 있어 사용자가 앱 고장으로 오해한다. | 그렇다 |
| 10 | **`--config-dir`로 사내 프록시·타임아웃 설정이 무시된다** | 프록시를 강제하는 회사면 도입 첫날부터 앱만 접속 불가. 터미널 svn은 되는데 앱은 안 되므로 원인 파악이 특히 어렵다. 대용량 문서 전송 시 `http-timeout`도 같은 경로. | 그렇다 |

순위에서 빠졌지만 발생 시 심각한 것: `switched` 상태 비가시(확률 낮음, 조용히 잘못된 위치로 커밋), `svn export` 없음(외부 공유 시 `.svn` 동반), 예약-추가 루트 등록 시 전면 `malformedResponse`(확률 낮음, 정보 0).

---

## 부록 — 재현/추정 구분 요약

| 항목 | 상태 |
|---|---|
| 저장소 이전 후 실패 및 `relocate`로 복구·로컬 변경 보존 | 실제 재현 |
| 다른 작업본 잠금으로 커밋 실패(`E195022`/`E160037`) | 실제 재현 |
| 미버전 방해물이 트리 충돌로 전환됨(`--force` 불필요) | 실제 재현 |
| `switched="true" item="normal"` XML | 실제 재현 |
| 예약-추가 폴더의 `wc-root` 성공 + 전 항목 `revision="-1"` | 실제 재현(SVN 출력), 앱 동작은 코드 추정 |
| 미버전 하위 폴더는 등록 검증에서 정상 거부됨 | 실제 재현(문제 아님으로 확인) |
| `--trust-server-cert-failures` 허용 값 5종 | `svn help` 출력으로 확인, 서버 재현 없음 |
| `--config-dir` 의미 | `svn help` 출력으로 확인, 프록시 재현 없음 |
| 오류 문구 `"%1$@ 실패: %2$@"` 및 코드별 안내 부재 | 소스·리소스 전수 확인 |
| 나머지 UI 누락(잠그기 동작, 복원 동작, 저장소 탐색 등) | 소스 전수 grep 기준 |
| NFC 디스크 rename이 열린 문서에 주는 영향 | 미확인. 추정만 기록 |
