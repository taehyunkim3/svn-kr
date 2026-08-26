# SVN 명령 인자 규칙

기준일: 2026-08-26
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
- 작업 시작 시 `미확인` 셀 20개. 실 SVN으로 20개를 채웠고 확인 불가는 0개다.

## 명령별 규칙표

| 명령 | 앱의 인자 자리 | peg revision | 선행 `-` / `--` | 빈 문자열·생략 | NFC/NFD·인코딩 |
|---|---|---|---|---|---|
| `checkout` | 저장소 `URL` | 해석. final `@`·`%40` escape | URL 앞 `--` 필요 | 빈 값은 `E125002`로 거부 | raw Unicode 의미를 보존한 `URL.absoluteString`; 원문 운반 |
| `checkout` | 목적지 `.` | 비해석 | 같은 `--` 뒤 | 고정 `.` | cwd가 실제 목적지. argv 경로 변환 없음 |
| `info --show-item wc-root/url/kind` | 대상 생략, cwd | 해당 없음 | 해당 없음 | 생략 시 cwd | cwd filesystem 표기 사용 |
| `info --show-item revision` | 저장소 `URL` | 해석. escape 필요 | URL 앞 `--` 필요 | 빈 값은 URL이 아니라 cwd로 해석 | 원문 운반. raw/percent-encoded NFD 보존 |
| `info --xml` | WC `TARGET` | 해석 | `--` 뒤 | 빈 문자열은 `.`이므로 앱에서 거부 | 작업복사본 root 기준 원문 운반 |
| `cat` | WC `TARGET` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 작업복사본 root 기준 원문 운반 |
| `cat` | `--revision REV` | 대상 peg와 별도 operative revision | 옵션 값 | 빈 값은 `E205000`으로 거부 | SVN revision 문법의 ASCII 값. Unicode는 `E205000`으로 거부 |
| `export` | WC `PATH1` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 작업복사본 root 기준 원문 운반 |
| `export` | 로컬 `PATH2` | **해석**. literal `@` escape 필요 | `--` 뒤 | 생략 가능하나 앱은 항상 지정. 빈 값은 거부 | 표준화한 절대경로를 원문 운반 |
| `export` | `--revision REV` | PATH1 peg와 별도 | 옵션 값 | 빈 값은 `E205000`으로 거부 | SVN revision 문법의 ASCII 값. Unicode는 `E205000`으로 거부 |
| `move` WC→WC | `SRC` | 해석/검사. literal `@` escape 필요 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 기존 SVN 경로 원문 보존 |
| `move` WC→WC | `DST` | **비해석**. escape 금지 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 새 마지막 성분만 NFC. 기존 상위 성분 원문 보존 |
| `move` URL→URL | `SRC URL` | 해석/검사. literal `@`·`%40` escape 필요 | `--` 뒤 | 빈 값은 cwd인 WC 경로가 되어 URL/WC 혼합 `E200007` | URL path component는 UTF-8 percent encoding |
| `move` URL→URL | `DST URL` | **비해석**. escape 금지 | `--` 뒤 | 빈 값은 cwd인 WC 경로가 됨. log 옵션과 함께 `E205009` | NFC 목적지 component를 한 번 percent encoding |
| `move` URL→URL | `--file MESSAGE_FILE` | 해당 없음 | 옵션 영역 | 빈 메시지 허용 | 메시지 UTF-8 원문. NUL은 앱에서 거부 |
| `copy` WC→WC | `SRC` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 기존 SVN 경로 원문 보존 |
| `copy` WC→WC | `DST` | **해석**. literal `@` escape 필요 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 새 마지막 성분만 NFC |
| `copy` URL→WC | `SRC URL[@PEGREV]` | 해석. 과거 조회 시 요청 revision을 peg에도 명시 | `--` 뒤 | 빈 값은 cwd인 WC source로 실행될 수 있음. `@REV`만 있으면 `E125001` | raw/percent-encoded URL 의미 보존, 원문 운반 |
| `copy` URL→WC | WC `DST` | 해석. literal `@` escape 필요 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 새 마지막 성분만 NFC |
| `copy` URL→WC | `--revision REV` | operative revision | 옵션 값 | nil/빈 값이면 peg 미지정 | SVN revision 문법의 ASCII 값. Unicode는 `E205000`으로 거부 |
| `relocate` | `FROM-PREFIX` | **비해석** | 두 URL보다 앞에 `--` | 빈 값은 `E235000` assertion과 exit 134 | 입력 URL을 NFC로 바꾸지 않고 원문 운반 |
| `relocate` | `TO-PREFIX` | **비해석** | 같은 `--` 뒤 | 빈 값은 `E155024`로 거부 | 입력 URL을 NFC로 바꾸지 않고 원문 운반 |
| `relocate` | WC `PATH` | **비해석**. escape 금지 | 같은 `--` 뒤 | 앱은 root cwd의 고정 `.` 사용 | 하위 등록 프로젝트도 WC root URL prefix로 환산 |
| `propset` | `PROPNAME` | 해당 없음 | 옵션 영역이므로 선행 `-` 금지. 앱에서 거부 | 빈 이름 거부 | Unicode 이름은 `E195011`로 거부 |
| `propset` | `--file PROPVAL_FILE` | 해당 없음 | 옵션 값 | 0-byte 파일은 빈 property 값 | binary 원문. NUL/LF/CR 포함 가능 |
| `propset` | WC `PATH` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 작업복사본 root 기준 원문 운반 |
| `propget` | `PROPNAME` | 해당 없음 | 옵션 영역이므로 선행 `-` 금지. 앱에서 거부 | 빈 이름 거부 | Unicode 이름은 `E195011`로 거부 |
| `propget` | WC `TARGET` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 원문 운반. binary 결과는 파일로 수신 |
| `propdel` | `PROPNAME` | 해당 없음 | 옵션 영역이므로 선행 `-` 금지. 앱에서 거부 | 빈 이름 거부 | Unicode 이름은 생성 불가. 없으면 경고 후 exit 0 |
| `propdel` | WC `PATH` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 원문 운반 |
| `proplist` | WC `TARGET` | 해석 | `--` 뒤 | 빈 문자열은 앱에서 거부 | 원문 운반. XML 결과의 property 값은 bytes로 해석 |
| `list` | 저장소 `TARGET` | 해석 | `--` 뒤 | 생략 시 cwd. 앱 URL 호출은 항상 지정 | raw/percent-encoded NFD URL 보존, 원문 운반 |
| `list` | `--revision REV` | operative revision. 삭제된 경로는 같은 REV를 peg에도 명시 | 옵션 값 | nil/빈 값이면 HEAD | SVN revision 문법의 ASCII 값. Unicode는 `E205000`으로 거부 |
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
| `diff --change` | `^/REPOSITORY_PATH@PEGREV` | 의도한 peg. 자동 escape 금지 | `--` 뒤 | 빈 revision은 `E195002`. 끝의 bare `@`는 빈 peg가 아니라 escape | log의 raw suffix에서 literal `%`만 `%25`; NFD bytes 보존 |
| `update` | 대상 생략, cwd | 해당 없음 | 해당 없음 | 생략 시 cwd | cwd 경계 |
| `add` | WC `PATH...` | 해석 | `targets` 파일 내용은 옵션으로 재파싱되지 않음 | 빈 배열도 앱에서 거부 | targets 원문. commit 신규 경로는 디스크 NFC 확인 후 전달 |
| `commit` | WC `PATH...` | 해석 | `targets` 파일 내용은 옵션으로 재파싱되지 않음 | **빈 배열은 `.` 전체 commit이므로 앱에서 선제 거부** | targets 원문 |
| `commit` | `--file MESSAGE_FILE` | 해당 없음 | 옵션 값 | 빈 메시지 허용 | UTF-8 원문. NUL 거부. argv 크기 제한 없음 |

## 공통 전역 인자

| 인자 | peg revision | 선행 `-` / 종료 구분자 | 빈 값 | NFC/NFD·인코딩 |
|---|---|---|---|---|
| `--config-dir PATH` | 해당 없음 | 옵션 값 | 앱이 항상 non-empty 생성 | NFD UTF-8 bytes 보존. Unicode 경로 사용 가능 |
| `--username USERNAME` | 해당 없음 | 옵션 값 | 빈 username이면 옵션 자체를 생략 | NFD UTF-8 bytes를 `svn:author`에 그대로 저장 |
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

## 확인 방법

모든 저장소와 작업 복사본은 `/tmp/svn-argument-rules.K8ha8B` 아래에 만들었다.
사용한 바이너리와 fixture:

```console
$ svn --version --quiet
1.14.5
$ svnadmin create /tmp/svn-argument-rules.K8ha8B/repo
$ svn mkdir file:///tmp/svn-argument-rules.K8ha8B/repo/trunk -m init
Committed revision 1.
$ svn checkout file:///tmp/svn-argument-rules.K8ha8B/repo/trunk /tmp/svn-argument-rules.K8ha8B/wc
Checked out revision 1.
$ mkdir -p /tmp/svn-argument-rules.K8ha8B/wc/dir
$ touch /tmp/svn-argument-rules.K8ha8B/wc/file.txt /tmp/svn-argument-rules.K8ha8B/wc/dir/nested.txt
$ svn add /tmp/svn-argument-rules.K8ha8B/wc/file.txt /tmp/svn-argument-rules.K8ha8B/wc/dir
$ svn commit /tmp/svn-argument-rules.K8ha8B/wc -m fixture
Committed revision 2.
$ svn copy file:///tmp/svn-argument-rules.K8ha8B/repo/trunk file:///tmp/svn-argument-rules.K8ha8B/repo/branch -m branch
Committed revision 3.
$ svn checkout file:///tmp/svn-argument-rules.K8ha8B/repo/trunk '/tmp/svn-argument-rules.K8ha8B/wc@name'
Checked out revision 3.
$ mkdir -p /tmp/svn-argument-rules.K8ha8B/checkout-empty
```

빈 값과 revision 문법:

```console
$ (cd /tmp/svn-argument-rules.K8ha8B/checkout-empty && svn checkout -- '' .)
svn: E125002: '' does not appear to be a URL
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn info --show-item revision -- '')
1
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn cat --revision '' -- file.txt)
svn: E205000: Syntax error in revision argument ''
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn cat --revision '리비전' -- file.txt)
svn: E205000: Syntax error in revision argument '리비전'
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn export --revision '' -- file.txt ../export-empty)
svn: E205000: Syntax error in revision argument ''
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn export --revision '리비전' -- file.txt ../export-unicode)
svn: E205000: Syntax error in revision argument '리비전'
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn copy --revision '리비전' -- file:///tmp/svn-argument-rules.K8ha8B/repo/trunk/file.txt unicode-revision-copy)
svn: E205000: Syntax error in revision argument '리비전'
$ svn list --revision '리비전' -- file:///tmp/svn-argument-rules.K8ha8B/repo/trunk
svn: E205000: Syntax error in revision argument '리비전'
```

URL 명령의 빈 값:

```console
$ printf 'probe\n' > /tmp/svn-argument-rules.K8ha8B/message
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn move --file ../message --force-log -- '' file:///tmp/svn-argument-rules.K8ha8B/repo/trunk/empty-source-destination)
svn: E200007: Moves between the working copy and the repository are not supported
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn move --file ../message --force-log -- file:///tmp/svn-argument-rules.K8ha8B/repo/trunk/file.txt '')
svn: E205009: Local, non-commit operations do not take a log message or revision properties
$ (cd /tmp/svn-argument-rules.K8ha8B/wc/dir && svn copy --revision 2 -- '' ../copied-from-empty)
A         /private/tmp/svn-argument-rules.K8ha8B/wc/copied-from-empty
$ (cd /tmp/svn-argument-rules.K8ha8B/wc/dir && svn copy --revision 2 -- '@2' ../copied-from-empty-at2)
svn: E125001: '@2' is just a peg revision. Maybe try '@2@' instead?
```

`relocate`의 세 인자 자리:

```console
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn relocate -- '' file:///tmp/svn-argument-rules.K8ha8B/repo/trunk .); printf 'exit=%s\n' $?
svn: E235000: In file 'subversion/libsvn_subr/dirent_uri.c' line 2478: assertion failed (svn_uri_is_canonical(url, pool))
exit=134
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn relocate -- file:///tmp/svn-argument-rules.K8ha8B/repo/trunk '' .)
svn: E155024: Invalid relocation destination: '' (not a URL)
$ svn relocate -- file:///tmp/svn-argument-rules.K8ha8B/repo/trunk file:///tmp/svn-argument-rules.K8ha8B/repo/trunk '/tmp/svn-argument-rules.K8ha8B/wc@name'; printf 'exit=%s\n' $?
exit=0
$ svn relocate -- file:///tmp/svn-argument-rules.K8ha8B/repo/trunk file:///tmp/svn-argument-rules.K8ha8B/repo/trunk '/tmp/svn-argument-rules.K8ha8B/wc@name@'
svn: E155007: '/tmp/svn-argument-rules.K8ha8B/wc@name@' is not a working copy
```

Unicode property 이름. `property_name_nfd`는 UTF-8 `70 72 6f 62 65 3a 65 cc 81`이다.

```console
$ property_name_nfd=$'probe:e\u0301'
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn propset "$property_name_nfd" value -- file.txt)
svn: E195011: 'probe:é' is not a valid Subversion property name
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn propget "$property_name_nfd" -- file.txt)
svn: E195011: 'probe:é' is not a valid Subversion property name
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn propdel "$property_name_nfd" -- file.txt); printf 'exit=%s\n' $?
Attempting to delete nonexistent property 'probe:é' on 'file.txt'
exit=0
```

`diff --change`의 빈 revision과 bare `@`:

```console
$ printf 'content\n' > /tmp/svn-argument-rules.K8ha8B/wc/file.txt
$ svn commit /tmp/svn-argument-rules.K8ha8B/wc/file.txt -m content
Committed revision 4.
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn diff --change '' -- '^/trunk/file.txt@')
svn: E195002: Not all required revisions are specified
$ (cd /tmp/svn-argument-rules.K8ha8B/wc && svn diff --change 4 -- '^/trunk/file.txt@')
Index: file.txt
```

NFD 전역 인자. 두 `od` 결과의 `65 cc 81`은 NFD `e` + combining acute bytes다.

```console
$ config_nfd=$'/tmp/svn-argument-rules.K8ha8B/config-e\u0301'
$ svn --config-dir "$config_nfd" info file:///tmp/svn-argument-rules.K8ha8B/repo/trunk | sed -n '1p'
Path: trunk
$ find /tmp/svn-argument-rules.K8ha8B -maxdepth 1 -type d -name 'config-*' -print | od -An -tx1
... 63 6f 6e 66 69 67 2d 65 cc 81 0a
$ username_nfd=$'use\u0301r'
$ svn mkdir file:///tmp/svn-argument-rules.K8ha8B/repo/username-probe --username "$username_nfd" --no-auth-cache -m username-probe
Committed revision 5.
$ svn log --xml --revision HEAD file:///tmp/svn-argument-rules.K8ha8B/repo | sed -n '/<author>/p' | od -An -tx1
... 3e 75 73 65 cc 81 72 3c 2f ...
```

## 발견한 코드 위반

- `Sources/SVNCore/SVNClient.swift:70`, `:107`, `:136`: 빈 checkout URL을 거부하지
  않고 SVN에 전달한다. SVN은 `E125002`로 실패한다.
- `Sources/SVNCore/SVNClient.swift:175`, `:201`: `cat`과 `export` revision을 검증하지
  않는다. 빈 값과 Unicode 값은 `E205000`이다.
- `Sources/SVNCore/SVNClient.swift:258`: URL→WC `copy`가 빈 저장소 URL과 잘못된
  revision을 거부하지 않는다. revision이 nil/빈 값이면 cwd를 source로 복사할 수 있다.
- `Sources/SVNCore/SVNClient.swift:302`: 빈 relocate FROM/TO를 거부하지 않는다.
  빈 FROM은 SVN 1.14.5를 assertion exit 134로 종료시킨다.
- `Sources/SVNCore/SVNClient.swift:2275`: property 이름 검사가 Unicode를 허용한다.
  `propset`/`propget`은 `E195011`, `propdel`은 존재하지 않는 property 경고 뒤 성공한다.
- `Sources/SVNCore/SVNClient.swift:445`: `list`의 Unicode revision을 검증하지 않아
  `E205000`으로 실패한다.
- `Sources/SVNCore/SVNClient.swift:1672`: `diff --change`의 빈 revision과 peg를
  거부하지 않는다. 빈 revision은 `E195002`, 빈 peg는 bare `@` escape로 바뀐다.
