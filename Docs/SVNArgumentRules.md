# SVN 명령 인자 규칙

기준일: 2026-08-25  
기준 실행 파일: `/opt/homebrew/bin/svn` 1.14.5, APFS, `file://` 저장소

이 문서는 `SVNClient`가 실행하는 모든 하위 명령의 인자 자리를 다룬다. 근거는
`svn help <명령> -v` 실제 출력과 `SVNArgumentRulesIntegrationTests`의 실 저장소
재현이다. `--`는 옵션 파싱만 끝낸다. peg revision 파싱은 끝내지 않는다.

표기:

- `해석`: `@REV`를 peg revision으로 읽는다. literal `@` 또는 마지막 URL 성분의
  `%40`에는 끝 `@`가 필요하다.
- `비해석`: 끝 `@`를 붙이면 실제 이름이 오염될 수 있다.
- `원문`: UTF-8을 임시 파일과 POSIX shell로 운반한다. `Process.arguments`의 macOS
  NFD 변환을 거치지 않는다.
- `targets`: UTF-8 `--targets` 파일로 운반한다.
- `미확인`: help와 이번 실 SVN 재현만으로 확정하지 못했다. 빈칸을 추측으로
  채우지 않았다.

## 명령별 규칙표

| 명령 | 앱의 인자 자리 | peg revision | 선행 `-` / `--` | 빈 문자열·생략 | NFC/NFD·인코딩 |
|---|---|---|---|---|---|
| `checkout` | 저장소 `URL` | 해석. final `@`·`%40` escape | URL 앞 `--` 필요 | URL 빈 값: 미확인 | raw Unicode 의미를 보존한 `URL.absoluteString`; 원문 운반 |
| `checkout` | 목적지 `.` | 비해석 | 같은 `--` 뒤 | 고정 `.` | cwd가 실제 목적지. argv 경로 변환 없음 |
| `info --show-item wc-root/url/kind` | 대상 생략, cwd | 해당 없음 | 해당 없음 | 생략 시 cwd | cwd filesystem 표기 사용 |
| `info --show-item revision` | 저장소 `URL` | 해석. escape 필요 | URL 앞 `--` 필요 | 빈 URL: 미확인 | 원문 운반. raw/percent-encoded NFD 보존 |
| `info --xml` | WC `TARGET` | 해석 | `--` 뒤 | 빈 문자열은 `.`이므로 앱에서 거부 | 작업복사본 root 기준 원문 운반 |
| `cat` | WC `TARGET` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 작업복사본 root 기준 원문 운반 |
| `cat` | `--revision REV` | 대상 peg와 별도 operative revision | 옵션 값 | 빈 REV: 미확인 | 숫자/예약어 문자열. Unicode: 미확인 |
| `export` | WC `PATH1` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 작업복사본 root 기준 원문 운반 |
| `export` | 로컬 `PATH2` | **해석**. literal `@` escape 필요 | `--` 뒤 | 생략 가능하나 앱은 항상 지정. 빈 값은 거부 | 표준화한 절대경로를 원문 운반 |
| `export` | `--revision REV` | PATH1 peg와 별도 | 옵션 값 | 빈 REV: 미확인 | 숫자/예약어 문자열. Unicode: 미확인 |
| `move` WC→WC | `SRC` | 해석/검사. literal `@` escape 필요 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 기존 SVN 경로 원문 보존 |
| `move` WC→WC | `DST` | **비해석**. escape 금지 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 새 마지막 성분만 NFC. 기존 상위 성분 원문 보존 |
| `move` URL→URL | `SRC URL` | 해석/검사. literal `@`·`%40` escape 필요 | `--` 뒤 | 빈 URL: 미확인 | URL path component는 UTF-8 percent encoding |
| `move` URL→URL | `DST URL` | **비해석**. escape 금지 | `--` 뒤 | 빈 URL: 미확인 | NFC 목적지 component를 한 번 percent encoding |
| `move` URL→URL | `--file MESSAGE_FILE` | 해당 없음 | 옵션 영역 | 빈 메시지 허용 | 메시지 UTF-8 원문. NUL은 앱에서 거부 |
| `copy` WC→WC | `SRC` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 기존 SVN 경로 원문 보존 |
| `copy` WC→WC | `DST` | **해석**. literal `@` escape 필요 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 새 마지막 성분만 NFC |
| `copy` URL→WC | `SRC URL[@PEGREV]` | 해석. 과거 조회 시 요청 revision을 peg에도 명시 | `--` 뒤 | URL 빈 값: 미확인 | raw/percent-encoded URL 의미 보존, 원문 운반 |
| `copy` URL→WC | WC `DST` | 해석. literal `@` escape 필요 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 새 마지막 성분만 NFC |
| `copy` URL→WC | `--revision REV` | operative revision | 옵션 값 | nil/빈 값이면 peg 미지정 | 숫자/예약어 문자열. Unicode: 미확인 |
| `relocate` | `FROM-PREFIX` | **비해석** | 두 URL보다 앞에 `--` | 빈 URL: 미확인 | 입력 URL을 NFC로 바꾸지 않고 원문 운반 |
| `relocate` | `TO-PREFIX` | **비해석** | 같은 `--` 뒤 | 빈 URL: 미확인 | 입력 URL을 NFC로 바꾸지 않고 원문 운반 |
| `relocate` | WC `PATH` | peg 여부: 미확인 | 같은 `--` 뒤 | 앱은 root cwd의 고정 `.` 사용 | 하위 등록 프로젝트도 WC root URL prefix로 환산 |
| `propset` | `PROPNAME` | 해당 없음 | 옵션 영역이므로 선행 `-` 금지. 앱에서 거부 | 빈 이름 거부 | Unicode property name: 미확인 |
| `propset` | `--file PROPVAL_FILE` | 해당 없음 | 옵션 값 | 0-byte 파일은 빈 property 값 | binary 원문. NUL/LF/CR 포함 가능 |
| `propset` | WC `PATH` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 작업복사본 root 기준 원문 운반 |
| `propget` | `PROPNAME` | 해당 없음 | 옵션 영역이므로 선행 `-` 금지. 앱에서 거부 | 빈 이름 거부 | Unicode property name: 미확인 |
| `propget` | WC `TARGET` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 원문 운반. binary 결과는 파일로 수신 |
| `propdel` | `PROPNAME` | 해당 없음 | 옵션 영역이므로 선행 `-` 금지. 앱에서 거부 | 빈 이름 거부 | Unicode property name: 미확인 |
| `propdel` | WC `PATH` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 원문 운반 |
| `proplist` | WC `TARGET` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 원문 운반. XML 결과의 property 값은 bytes로 해석 |
| `list` | 저장소 `TARGET` | 해석 | `--` 뒤 | 생략 시 cwd. 앱 URL 호출은 항상 지정 | raw/percent-encoded NFD URL 보존, 원문 운반 |
| `list` | `--revision REV` | operative revision. 삭제된 경로는 같은 REV를 peg에도 명시 | 옵션 값 | nil/빈 값이면 HEAD | 숫자/예약어 문자열. Unicode: 미확인 |
| `status` | 대상 생략, cwd | 해당 없음 | 해당 없음 | 생략 시 cwd | cwd 경계. XML 경로 원문을 byte-aware snapshot으로 해석 |
| `cleanup` | 대상 생략, cwd | 해당 없음 | 해당 없음 | 생략 시 cwd | cwd 경계 |
| `revert` | WC `PATH...` | 해석 | 단일은 `--`; 다중은 `targets` | `""`은 `.`이므로 거부. 빈 배열도 앱에서 거부 | 원문/targets 운반 |
| `delete` | WC `PATH...` | 해석 | 단일은 `--`; 다중은 `targets` | `""` 거부. 빈 배열도 앱에서 거부 | 원문/targets 운반 |
| `lock` | WC `TARGET...` | 해석 | 단일은 `--`; 다중은 `targets` | `""` 거부. 빈 배열도 앱에서 거부 | 원문/targets 운반 |
| `lock` | `--file COMMENT_FILE` | 해당 없음 | 옵션 값 | 빈 comment 허용 | UTF-8 원문. NUL 거부. argv 크기 제한 없음 |
| `unlock` | WC `TARGET...` | 해석 | 단일은 `--`; 다중은 `targets` | `""` 거부. 빈 배열도 앱에서 거부 | 원문/targets 운반 |
| `resolve` | WC `PATH` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 원문 운반 |
| `resolve` | `--accept CHOICE` | 해당 없음 | enum 옵션 값 | 앱 enum이라 빈 값 없음 | ASCII 고정값 |
| `log` | 대상 생략, cwd | 해당 없음 | 해당 없음 | 생략 시 cwd | cwd 경계; XML 메시지는 UTF-8로 해석 |
| `log` | WC `PATH` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 원문 운반 |
| `log` | `--revision RANGE`, `--limit N` | target peg와 별도 | 옵션 값 | 앱이 항상 non-empty 생성 | ASCII 숫자/`HEAD` |
| `diff` | 대상 생략, cwd | 해당 없음 | 해당 없음 | 생략 시 cwd 전체 diff | cwd 경계 |
| `diff` | WC `TARGET` | 해석 | `--` 뒤 | 빈 optional은 대상 생략. 명시 `""`은 앱에서 거부 | 원문 운반 |
| `diff --change` | `^/REPOSITORY_PATH@PEGREV` | 의도한 peg. 자동 escape 금지 | `--` 뒤 | revision/peg 빈 값: 미확인 | log의 raw suffix에서 literal `%`만 `%25`; NFD bytes 보존 |
| `update` | 대상 생략, cwd | 해당 없음 | 해당 없음 | 생략 시 cwd | cwd 경계 |
| `add` | WC `PATH...` | 해석 | `targets` 파일 내용은 옵션으로 재파싱되지 않음 | 빈 배열도 앱에서 거부 | targets 원문. commit 신규 경로는 디스크 NFC 확인 후 전달 |
| `commit` | WC `PATH...` | 해석 | `targets` 파일 내용은 옵션으로 재파싱되지 않음 | **빈 배열은 `.` 전체 commit이므로 앱에서 선제 거부** | targets 원문 |
| `commit` | `--file MESSAGE_FILE` | 해당 없음 | 옵션 값 | 빈 메시지 허용 | UTF-8 원문. NUL 거부. argv 크기 제한 없음 |

## 공통 전역 인자

| 인자 | peg revision | 선행 `-` / 종료 구분자 | 빈 값 | NFC/NFD·인코딩 |
|---|---|---|---|---|
| `--config-dir PATH` | 해당 없음 | 옵션 값 | 앱이 항상 non-empty 생성 | UUID/앱 지원 경로. Unicode 경계는 미확인 |
| `--username USERNAME` | 해당 없음 | 옵션 값 | 빈 username이면 옵션 자체를 생략 | `Process.arguments` 전달. Unicode 정규화는 미확인 |
| `--password-from-stdin` 값 | 해당 없음 | 해당 없음 | 빈 password이면 저장값 사용을 위해 stdin 옵션 생략 | stdin UTF-8. argv·로그에 비밀번호 없음 |
| `--trust-server-cert-failures=LIST` | 해당 없음 | `=` 결합 옵션 | 빈 set이면 옵션 생략 | ASCII enum 값 |

## 실 재현으로 고정한 반대 규칙

- `svn export source@ destination@name`에서 destination escape가 없으면
  `E200009: a peg revision is not allowed here`. 끝 `@`를 붙이면 의도한 이름으로 생성.
- `svn move source@ destination@name@`의 WC destination은 끝 `@`까지 literal로 생성.
  source만 escape하고 destination은 escape하지 않아야 한다.
- URL→URL `move`도 source는 escape가 필요하고 destination은 escape하면 안 된다.
  `%40`은 SVN이 decode한 뒤 peg로 처리하므로 source final component의 `%40`도 감지한다.
- `svn copy` destination은 반대로 peg를 해석한다. literal `@`에는 escape가 필요하다.
- `svn commit --targets <빈 파일>`은 target을 `.`로 넓힌다. 선택 commit API는 빈 배열을
  실행 전에 거부한다.
- `relocate`의 FROM/TO는 peg target이 아닌 URL prefix다. escape하지 않는다. `--`는 두
  URL 앞에 두고, 하위 등록 프로젝트는 working-copy root URL prefix로 환산해 root에서 실행한다.

## 검증 위치

- 실 SVN 회귀: `Tests/SVNCoreTests/SVNArgumentRulesIntegrationTests.swift`
- peg/targets 단위 규칙: `Tests/SVNCoreTests/SVNCredentialsTests.swift`
- commit/lock 메시지 원문: `Tests/SVNCoreTests/SVNLogMessagePathnameTests.swift`
- 기존 NFD 작업복사본 경계: `Tests/SVNCoreTests/SVNUnicodeCommitIntegrationTests.swift`,
  `Tests/SVNCoreTests/SVNCanonicalAliasIntegrationTests.swift`
