# svn 인자 구성 경계 조건 감사

날짜: 2026-08-25  
범위: 읽기 전용. `Sources/SVNCore/SVNClient.swift` 인자 배열과 그 호출부.  
재현: 이 머신 `svn` 1.14.5, 임시 `file://` 저장소 `/tmp/svnmac-argv-audit-*`.  
제외: 이미 고친 `--force-log`(커밋/잠금 메시지가 경로 이름과 같을 때 `E205005`).

`--` 구분자는 옵션 파싱만 막는다. peg revision(`PATH@REV`)은 `--` 뒤에서도 적용된다.

---

## 이름 바꾸기(move) 대상에 `@`가 있으면 파일명 끝에 `@`가 붙는다

- 심각도: 중간
- 근거: `Sources/SVNCore/SVNClient.swift:337-343` (`runWorkingCopyCopyOrMove`, move/copy 공통), `Sources/SVNCore/SVNClient.swift:2027-2049` (`escapeSecondPegSyntax` 기본값 `true`), `Sources/SVNCore/SVNClient.swift:2149-2150`, `Sources/SVNCore/SVNClient.swift:500-503` (저장소 경로 정규화 URL→URL move), `Sources/SVNMac/ProjectStore+RepositoryMaintenance.swift:46-52` (새 이름에 `@` 허용)
- 재현: 실제 재현함
- 트리거 입력: 버전 파일 이름을 `보고서@최종.hwp`로 바꿈 (이력 유지 이름 바꾸기)
- 증상: 작업 복사본에 `보고서@최종.hwp@`가 예약된다. CLI 대응:
  - `svn move -- base.txt renamed@copy.txt` → 대상 `renamed@copy.txt` (정상)
  - `svn move -- base.txt@ renamed@copy.txt@` (앱 기본값) → 대상 `renamed@copy.txt@`
  URL→URL move도 같다. dest에 접미 `@`를 붙이면 저장소 경로가 `보고서@최종.hwp@`가 된다.
- 확률: 이 레포 단위 테스트가 `보고서@최종.hwp`를 peg 예시로 쓴다. `@최종` 한글 파일명은 이 팀에서 드물지 않다. 매일은 아님.
- 고치는 방법: `move`의 대상만 `escapeSecondPegSyntax: false`. `copy` 대상은 접미 `@`가 필요하다(아래 참고).

같은 헬퍼를 쓰는 WC `copy`는 반대다. `svn copy -- base.txt@ copied@name.txt`는 `E205000: Syntax error parsing peg revision 'name.txt'`. `copied@name.txt@`여야 대상이 `copied@name.txt`가 된다. copy 쪽 기본값은 맞다.

---

## checkout·자격 확인이 URL 마지막 성분의 `@`를 peg revision으로 읽는다

- 심각도: 중간
- 근거: `Sources/SVNCore/SVNClient.swift:64-69`, `Sources/SVNCore/SVNClient.swift:100-105` (`checkout -- URL .`, peg 이스케이프 없음), `Sources/SVNCore/SVNClient.swift:572-573` (`info --show-item revision -- URL`), `Sources/SVNCore/SVNClient.swift:375-378` (`repositoryEntries`는 단일 경로 헬퍼라 peg 이스케이프 있음)
- 재현: 실제 재현함
- 트리거 입력: 저장소 URL 마지막 성분이 `프로젝트@백업`인 폴더. 저장소 둘러보기에서 그 폴더를 고른 뒤 체크아웃. 또는 그런 WC를 「기존 폴더로 추가」한 뒤 계정 저장.
- 증상:
  - checkout: `svn: E205000: Syntax error parsing peg revision '백업'`
  - `svn info --show-item url`이 돌려주는 값은 한글만 퍼센트 인코딩하고 `@`는 그대로다. 예: `file:///…/%ED%94%84…@%EB%B0%B1%EC%97%85`. 그 URL로 verifyCredentials를 치면 `E205000: Syntax error parsing peg revision '%EB%B0%B1%EC%97%85'`
  - `@`를 `%40`으로 바꿔도 SVN이 디코드한 뒤 peg를 나눈다. 체크아웃 실패는 같다.
  - 접미 `@`를 붙이면 checkout/info/list 모두 성공한다.
- 확률: 파일명 `@`보다 폴더 URL이 드물다. 다만 둘러보기(`list`)는 peg를 붙이고 체크아웃은 안 붙여, 둘러보기에서 보이는 폴더를 받는 순간 실패한다.
- 고치는 방법: checkout·verifyCredentials URL에도 `svnPathEscapingPegSyntax`를 적용한다. `user@host` userinfo는 이 버전에서 접속 URL 원문이 유지되어 별도 문제는 재현되지 않았다.

---

## relocate가 마지막 성분 `@` URL을 peg로 쪼갠다

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNClient.swift:241-247` (`relocate OLD NEW -- .`, peg 없음, URL이 `--` 앞)
- 재현: 실제 재현함
- 트리거 입력: 작업 복사본 URL 마지막 성분이 `@`를 포함하는 채 저장소 위치를 옮김. FROM은 `svn info` URL(인코딩+리터럴 `@`), TO는 사용자가 붙여 넣은 새 URL.
- 증상: `svn: E155024: Invalid relocation destination: '…@백업' (does not point to target)`. peg로 잘린 뒤 인코딩이 FROM/TO에서 어긋난다. 접미 `@`를 붙이면 이번엔 `Invalid source URL prefix: '…@'` — relocate는 접두 문자열 비교라 접미 `@`가 저장된 URL과 안 겹친다.
- 확률: 저장소 이전 자체가 드물고, 마지막 성분에 `@`까지 겹치는 경우는 더 드물다.
- 고치는 방법: relocate URL은 lookup용 접미 `@`를 붙이지 말고, 경로 성분의 `@`를 peg 파싱 전에 안전하게 다루는 쪽(명령별 처리)이 필요하다. checkout과 같은 한 줄 수정으로 안 끝난다.

중간 경로 성분 `@`(예: `…/repo@backup/trunk`)는 checkout/relocate/list 모두 마지막 성분이 `trunk`라 이 환경에서 성공했다. 마지막 성분만 해당한다.

---

## export 목적지의 `@`를 peg로 거절한다

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNClient.swift:163-169` (`escapeSecondPegSyntax: false`), `Sources/SVNMac/RevisionFileService.swift:85-99` (실제 목적지는 UUID staging)
- 재현: 실제 재현함
- 트리거 입력: `SVNClient.export` 목적지 `/tmp/saved@backup.txt`. GUI 「이 버전 저장」은 `.svn-mac-revision-save-<UUID>`로 export한 뒤 옮기므로 사용자 파일명 `@`는 지금 svn argv에 안 들어간다.
- 증상: `svn: E200009: '/tmp/saved@backup.txt': a peg revision is not allowed here`. 목적지를 `saved@backup.txt@`로 주면 파일 `saved@backup.txt`가 생긴다. copy 대상과 같은 규칙.
- 확률: 현재 GUI 경로로는 안 터진다. export API를 사용자 경로에 바로 연결하면 터진다.
- 고치는 방법: export 목적지도 `escapeSecondPegSyntax: true` (copy와 동일).

export **소스**는 단일/이중 경로 헬퍼가 peg를 붙인다. `보고서@최종.hwp` 소스는 접미 `@` 없이 `E205000`, 있으면 성공. 소스 쪽은 새 명령이 안전장치를 건너뛰지 않는다.

---

## 경계 입력 검증이 없는 명령 목록

이미 `--force-log`를 덮는 커밋/잠금 pathname 테스트(`SVNLogMessagePathnameTests`)는 제외한다.

| 명령 | 기존 테스트 입력 | 넣었어야 할 경계 입력 |
|---|---|---|
| `move` (WC) | `original.hwp` → `moved.hwp` | 대상 `보고서@최종.hwp`. 기대: 파일명이 그대로. 지금 헬퍼면 `보고서@최종.hwp@`가 되어 실패해야 맞다 |
| `copy` (WC) | `moved.hwp` → `copied.hwp` | 대상 `copied@name.txt`. 접미 `@` 없이 `E205000`인지, 앱 경로로 파일명이 `@` 없이 생기는지 |
| `copy` (URL→WC) | `source.bin` → `url-copy.bin` | URL/대상 마지막 성분 `@` |
| `cat` / `fileContents` | `document.xlsx` | `보고서@최종.hwp`, `foo@BASE` (접미 `@` 없으면 `foo`의 BASE를 읽음) |
| `export` | 소스 `document.xlsx`, 목적지 UUID/일반 경로 | 소스 `@`, 목적지 `saved@backup.txt` |
| `checkout` | ASCII `file://…/trunk` | 마지막 성분 `프로젝트@백업`. 둘러보기에서 고른 URL을 그대로 체크아웃 |
| `relocate` | ASCII `repository-moved` | 마지막 성분 `@`인 FROM/TO |
| `verifyCredentials` / `info` URL | 없음 | `svn info --show-item url`이 `@`를 남긴 URL |
| `list` / `repositoryEntries` | `업무 계획.txt`, `빈 폴더` | 디렉터리 `프로젝트@백업`, 파일 `보고서@최종.hwp` |
| `lock --force` / 다중 unlock | `a.xlsx`, `b.hwp`, 주석 `alice editing` | 경로 `-최종.xlsx`, `보고서@최종.hwp`. 주석 pathname은 별도 테스트 있음 |
| `propset` / `propdel` | `office:metadata`, `svn:needs-lock` | GUI는 속성 이름이 고정. 경로 `@`/`-` 접두 |
| `cleanup` | WC 경로만 | 사용자 argv 없음. 경계 입력 해당 없음 |
| `commit` / `add` / `delete` / `revert` | `--targets`, 한글 메시지 | `--targets`에 `-최종.xlsx`, `--force`라는 파일명, `보고서@최종.hwp`. CLI로는 `--targets`가 `-`/`--force` 파일명을 옵션으로 안 읽음을 확인함. 앱 테스트는 없음 |
| `revisionDiff` | `^/trunk/…@42` 형태 단위 테스트 | 변경 경로 `보고서@최종.hwp` → `^/보고서@최종.hwp@REV` (마지막 `@`가 peg) |

이 버그(`E205005` 메시지=경로)가 테스트에 안 잡힌 이유와 같다. 새 명령 통합 테스트가 안전한 ASCII/한글 이름만 쓴다. `move`에 `보고서@최종.hwp` 대상을 넣었으면 파일명 끝 `@`가 바로 보였을 것이다. checkout에 `프로젝트@백업`을 넣었으면 `E205000`이 바로 보였을 것이다.

---

## 확인하지 않은 것

- `svn+ssh://user@host/…` / `https://user@host/…` userinfo `@`. `svn info` 오류 URL이 userinfo를 유지해 peg 분할로는 안 보였다. 실제 ssh/https 서버로는 접속 성공까지 확인하지 않음.
- HTTP(S) 한글 경로의 이중 퍼센트 인코딩. Foundation `URL.absoluteString`은 이미 인코딩된 `%ED%95%9C%EA%B8%80`을 다시 인코딩하지 않음을 Swift로 확인. 원격 서버 list/checkout는 안 함.
- HFS+ NFD 볼륨에서 relocate/checkout `Process.arguments` 정규화. 이 머신 APFS. 새 명령 중 relocate만 URL을 파일 운반이 아니라 `Process.arguments`로 넣는다. 한글 `file://` relocate는 APFS에서 성공.
- `revisionDiff` + `@` 포함 로그 경로. 코드는 `^path@peg`를 만들고 `escapePegSyntax: false`. 마지막 `@` 규칙상 동작해야 하나, 이번 임시 저장소 fixture가 꼬여 CLI까지 못 맞춤. 코드 기준 추정.
- ARG_MAX. `getconf ARG_MAX` = 1048576. 다중 경로는 commit/add/delete/revert/lock/unlock이 `--targets` 사용. 대량 unlock·needs-lock은 한 경로씩 루프. 한 명령에 경로를 수천 개 넣는 호출은 없음.
- 빈 커밋 메시지, `-검토요청` 메시지, 개행 메시지, 빈 잠금 주석. CLI는 `--message`+`--force-log`로 모두 성공. 앱 TextField는 단일 줄.
- 속성 이름이 `-`로 시작. GUI는 `svn:needs-lock`만 넘김. `svn propset -- -foo`는 `E195011: not a valid Subversion property name`.
- `propset` PROPVAL이 경로처럼 보일 때. 앱은 `--file`을 써서 pathname 검사가 없음. CLI에서도 `--file` 없이 경로처럼 보이는 값을 넣어도 이 버전에서는 성공.

---

## 인자 구성 지점 (목록, 발견 아님)

사용자 입력이 argv에 들어가는 경로만.

| 지점 | 사용자 값 | 운반 | `--` | peg | `--targets` |
|---|---|---|---|---|---|
| checkout | URL | `Process.arguments` + `URL.absoluteString` | URL 앞 | 없음 | 없음 |
| cat / fileContents | WC 경로, revision | 파일 운반 | 있음 | 있음 | 없음 |
| export | WC 경로, 목적지, revision | 파일 운반 2개 | 있음 | 소스만 | 없음 |
| move / copy (WC) | 소스·대상 상대 경로 | 파일 운반 2개 | 있음 | 둘 다 | 없음 |
| copy (URL→WC) | URL, 대상, revision | 파일 운반 2개 | 있음 | 둘 다 | 없음 |
| relocate | FROM/TO URL | `Process.arguments`, NFC만 | URL **뒤** (`.`만) | 없음 | 없음 |
| propset / propdel / propget / proplist | 속성 이름(GUI 고정), 값은 `--file`, 경로 | 경로 파일 운반 | 있음 | 경로 | 없음 |
| list (둘러보기) | URL, revision | 파일 운반 | 있음 | 있음 | 없음 |
| list (경로 정규화) | `svn info` URL | `Process.arguments` | 있음 | 있음 | 없음 |
| URL move (경로 정규화) | 메시지, URL 두 개 | `Process.arguments` | 있음 | 둘 다 | 없음 |
| verifyCredentials | `svn info` URL | `Process.arguments` | 있음 | 없음 | 없음 |
| lock / unlock | 경로, 주석(로컬라이즈 문자열), `--force` | `--targets` | 없음 (파일 내용) | `--targets` 안에서 | 있음 |
| commit / add / delete / revert | 경로, 메시지 | `--targets` | 없음 | `--targets` 안에서 | 있음 |
| cleanup / status / update / log(WC) | 없음 또는 `.` | cwd | 해당 없음 | 해당 없음 | 없음 |
| diff / log(파일) / resolve / info | WC 경로 | 파일 운반 | 있음 | 있음 | 없음 |
| revisionDiff | `^path@peg` | 파일 운반 | 있음 | 호출부가 직접 붙임 | 없음 |
| `--username` / `--message` | 옵션 ARG | `Process.arguments` | 해당 없음 | 해당 없음 | 해당 없음 |

`--targets` 파일 줄이 `-최종.xlsx`이거나 `--force`여도 이 svn 1.14.5는 옵션이 아니라 대상으로 처리했다.

ignore 패턴 `--dangerous`는 이미 `--file`로 우회하는 테스트가 있다.
