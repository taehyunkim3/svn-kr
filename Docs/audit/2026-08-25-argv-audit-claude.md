# SVN 명령 인자 구성 경계 조건 감사 (2026-08-25)

읽기 전용 감사. 소스는 수정하지 않았다.

## 조사 범위와 방법

- `Sources/SVNCore/SVNClient.swift` 전문(2641줄)에서 인자 배열을 만드는 지점을 전수 목록화했다(아래 "인자 구성 지점 전수 목록"). 각 지점이 받는 사용자 입력과 통과하는 이스케이프 계층을 추적했다.
- 호출부는 `Sources/SVNMac`의 `ProjectStore*`, `RevisionFileService`, `RepositoryBrowserState`, `ProjectStore+Ignore`, `ProjectStore+RepositoryMaintenance`를 읽어 값의 출처(사용자 입력 / svn 출력 / 하드코딩 상수)를 확인했다.
- `svn` 은 `/opt/homebrew/bin/svn` **1.14.5**. 인자 해석 규칙은 이 바이너리의 실제 동작과 `svn help <명령>` 출력을 근거로 했다. 기억이 아니라 실행 결과다.
- `/tmp/svnaudit` 에 `svnadmin create` 로 `file://` 저장소를 만들고 `dir@2026/`, `file@2026.xlsx`, `-leading.txt`, `매출 50%.xlsx`, `보고서%2010.txt`, `회의#3.txt`, `질문?.txt`, `공간 있는 파일.txt`, 탭 포함 이름을 넣어 CLI로 직접 재현했다.
- 앱 코드 경로 자체를 통과하는 재현은 `/tmp/svnprobe` 에 이 레포를 `.package(path:)` 로 의존하는 별도 SwiftPM 실행 타깃을 만들어 `SVNCore.SVNClient` 를 직접 호출했다. 레포 안에는 아무 파일도 만들지 않았다.
- 각 항목의 "재현" 줄은 **실제 재현함**(위 두 방법 중 하나로 오류/결과를 눈으로 확인) 과 **코드 기준 추정** 을 구분해 적었다. 앱 코드 경로까지 재현한 것과 CLI 수준만 재현한 것도 구분해 적었다.
- 이미 고쳐진 `--force-log`(E205005) 건은 제외했다.

발견 7건. 높음 1, 중간 3, 낮음 3.

---

# 1부 — 발견

## 한글 커밋 메시지가 저장소에 NFD로 저장된다

- 심각도: **높음**
- 근거:
  - `Sources/SVNCore/SVNClient.swift:1786` — `["commit", "--message", message, "--force-log"]`. 메시지가 인자 배열 안에 들어간다.
  - `Sources/SVNCore/SVNClient.swift:2104` — 이 배열은 `checkedRunWithMultipleWorkingCopyPathArguments` 에서 `arguments + ["--targets", ...]` 로 합쳐져 `checkedRun` 으로 넘어간다. 경로만 `--targets` 파일로 원문 보존되고 **메시지는 보존 경로를 타지 않는다**.
  - `Sources/SVNCore/SVNClient.swift:2391` — `process.arguments = globalArguments + arguments`. Foundation `Process.arguments` 는 macOS에서 모든 인자를 NFD로 변환한다.
  - 같은 성격: `Sources/SVNCore/SVNClient.swift:1106`, `1124` — `["lock", "--message", comment, "--force-log"]`. 잠금 코멘트도 동일하다.
  - 이 레포는 경로에 대해서는 이 문제를 이미 알고 처리하고 있다(`SVNClient.swift:2069-2071` 주석, `--targets` 파일 운반, `run(svnPathArgument:)` 의 `/bin/sh` 원문 운반). 메시지·코멘트만 빠져 있다.
- 재현: **실제 재현함(앱 코드 경로).** `SVNClient.commit(at:paths:message:)` 에 NFC 문자열 `"결산 자료 반영"`(`eab2b0ec82b020ec9e90eba38c20ebb098ec9881`)을 넘겼을 때 저장소에 남은 `svn log --xml` 의 `<msg>` 바이트는 `e18480e185a7e186af e18489e185a1e186ab 20 e1848ce185a1 e18485e185ad 20 e18487e185a1e186ab e1848be185a7e186bc` 였다. 입력 NFC와 불일치, 입력의 NFD 변환과 정확히 일치. 잠금 코멘트도 같은 방식으로 재현했다(`"편집 중"` NFC 입력 → 저장된 `<comment>` 는 NFD).
  - `Process.arguments` 자체의 NFD 변환도 별도로 확인했다. `/bin/sh` 로 argv 바이트를 그대로 덤프해 비교했다.
  - svn 쪽은 받은 바이트를 그대로 저장한다(CLI에서 NFD 메시지로 커밋 후 `svn log --xml` 바이트 동일).
- 트리거 입력: 커밋 메시지나 잠금 코멘트에 한글을 한 글자라도 쓰면 된다. 예: `결산 자료 반영`.
- 증상: 오류가 나지 않는다. 조용히 잘못된 바이트가 저장소에 영구 기록된다. macOS 화면에서는 NFD도 같은 글자로 보이므로 앱 안에서는 드러나지 않는다.
  - 저장소에 들어간 뒤에는 클라이언트가 고칠 수 없다. `svn:log` 리비전 속성 수정은 서버의 `pre-revprop-change` 훅 허용이 필요하다.
  - 다른 클라이언트(TortoiseSVN 등)와 서버측 로그 검색·훅에서 이 팀의 커밋 메시지 전체가 조합 자모 바이트로 보인다. **다른 클라이언트에서의 실제 렌더링 결과는 이 환경에서 확인하지 못했다**(아래 "확인하지 않은 것" 참조). 확인한 것은 저장된 바이트가 NFD라는 사실까지다.
- 확률: 이 팀 워크플로에서 **한글 커밋 메시지를 쓰는 모든 커밋**. 사실상 전건이다.
- 고치는 방법: 메시지·코멘트도 경로와 같은 방식으로 운반한다. 임시 파일에 원문 UTF-8 바이트를 쓰고 `--message` 대신 `--file <path> --force-log` 를 쓰면 `Process.arguments` 를 거치지 않는다(`svn help commit`/`svn help lock` 모두 `-F [--file] ARG` 지원).

---

## `commit(paths: [])` 이 작업 복사본 전체를 커밋한다

- 심각도: **중간**
- 근거:
  - `Sources/SVNCore/SVNClient.swift:1980` `normalizedCommitPaths([])` → `[]`.
  - `Sources/SVNCore/SVNClient.swift:2153` `svnTargetsFileContents([])` → `Data(("" + "\n").utf8)`, 즉 개행 한 줄만 든 `--targets` 파일.
  - `Sources/SVNCore/SVNClient.swift:1786` — `commit` 은 대상이 비면 svn 기본 대상 `.` 로 동작한다. `commit` 에는 대상 개수 가드가 없다.
- 재현: **실제 재현함(앱 코드 경로).** `one.txt` 를 커밋해 둔 작업 복사본에서 `one.txt` 를 수정한 뒤 `SVNClient.commit(at:paths:[], message:"empty selection")` 을 호출했더니 `Sending one.txt / Committed revision 2.` 가 나왔다. 선택하지 않은 변경이 커밋됐다.
  - svn 하위 명령별로 다르다. `commit` 만 빈 `--targets` 에서 `.` 로 폴백한다. `add`, `delete`, `revert`, `lock`, `unlock` 은 모두 `svn: E205001: Not enough arguments provided` 로 실패한다. 0바이트 파일과 개행 한 줄 파일 둘 다 같다.
- 트리거 입력: `paths` 가 빈 배열인 커밋 호출. 현재 UI 두 호출부는 모두 막혀 있다 — `ProjectStore.swift:1217` 은 `canCommitSelectedPaths`(`ProjectStore.swift:666` 의 `!selectedPaths.isEmpty`)를 통과해야 하고, `ProjectStore+Update.swift:211` 은 `guard !scheduledPaths.isEmpty` 를 통과해야 한다. **현재 화면에서 도달하는 경로는 찾지 못했다.**
- 증상: 사용자가 선택하지 않은 파일이 저장소에 올라간다. 오류는 없고 성공으로 보고된다. 되돌리려면 서버 리비전을 역머지해야 한다.
- 확률: 지금은 0에 가깝다. `SVNClient.commit` 은 public API이고 가드가 호출부 두 곳에만 있으므로, 커밋 호출부가 하나 더 생기는 순간 재발한다. 저장소에 잘못 올라간 커밋은 이 사용자층이 스스로 되돌릴 수 없어 잠재 심각도만 중간으로 뒀다.
- 고치는 방법: `commit` 진입부에 `guard !paths.isEmpty else { throw ... }` 를 두거나, `svnTargetsFileContents` 가 빈 배열을 오류로 거부하게 한다(후자는 다른 명령까지 함께 막아 준다).

---

## 파일명에 `%XX` 형태가 들어가면 히스토리 diff가 실패한다

- 심각도: **중간**
- 근거:
  - `Sources/SVNCore/SVNClient.swift:1429` — `let repositoryRevisionPathArgument = "^\(repositoryRevisionPath)@\(pegRevision)"`.
  - `Sources/SVNCore/SVNClient.swift:1444-1462` `revisionTargetPath` — 작업 복사본 root 부분만 `svn info --show-item relative-url` 의 **퍼센트 인코딩된** 값으로 바꾸고, 그 아래 이름은 원문 그대로 이어 붙인다. 즉 `^/` URL 인자 안에 인코딩되지 않은 이름이 들어간다.
  - `repositoryPath` 의 출처는 `Sources/SVNMac/ProjectStore+History.swift:42` 의 `changedPath.path` = `svn log --verbose --xml` 의 `<path>` 값이며, 이 값은 퍼센트 인코딩되지 않은 원문이다(`svn list --xml` 도 동일하게 원문을 준다).
  - 앱은 같은 일을 하는 정확한 인코더를 이미 두 곳에 갖고 있다 — `SVNRepositoryPathNormalization.percentEncodePathComponent`(`SVNRepositoryPathNormalization.swift:182`)와 `RepositoryBrowserState.appending`(`RepositoryBrowserState.swift:216`, `URL.appendingPathComponent` 가 `%` 를 `%25` 로 인코딩한다). `revisionTargetPath` 만 빠져 있다.
- 재현: **실제 재현함(앱 코드 경로).** 저장소에 `보고서%2010.txt` 를 넣고 두 번 커밋한 뒤 `SVNClient.revisionDiff(at:revision:"3", repositoryPath:"/보고서%2010.txt", workingCopyRepositoryPath:"/", pegRevision:"3")` 를 호출한 결과:
  ```
  svn: E160013: Diff target 'file:///tmp/svnprobe/pct-nfc/repo/trunk/%EB%B3%B4%EA%B3%A0%EC%84%9C%2010.txt' was not found in the repository at revisions '2' and '3'
  ```
  svn이 `%20` 을 유효한 이스케이프로 해석해 `보고서 10.txt` 를 찾았다. 올바른 인자는 `%2520` 이다(`svn info --show-item relative-url` 은 `^/%EB%B3%B4%EA%B3%A0%EC%84%9C%252010.txt` 를 준다).
  - 같은 조건에서 `정상파일.txt`, `매출 50%.xlsx`(`%` 뒤가 16진수 두 자리가 아님), `파일@2026.txt` 는 정상 동작했다. 즉 트리거는 **`%` 뒤에 16진수 두 자리가 오는 이름**으로 한정된다. 공백, `#`, `?`, `@`, 한글은 svn이 알아서 인코딩하므로 문제없다.
- 트리거 입력: 저장소에 `%` + 16진수 두 자리가 들어간 이름의 파일이 있고, 그 파일의 히스토리 항목을 클릭해 diff를 열 때. 예: `회의자료%20최종.pdf`, `보고서%2010.txt`. 웹에서 내려받은 파일을 그대로 커밋하면 이런 이름이 생긴다.
- 증상: 히스토리 diff 패널에 `svn diff 실패: svn: E160013: Diff target '...' was not found in the repository at revisions 'N' and 'M'` 이 뜬다. 파일은 저장소에 정상적으로 있는데도 "없다"고 나오므로 사용자는 파일이 유실됐다고 읽는다. 같은 파일의 저장/복원(`cat`, `export`)은 작업 복사본 경로 운반을 쓰므로 정상 동작한다 — diff만 실패한다.
- 확률: 낮다. 이 팀에서 `%2x` 형태 이름이 생기는 유일한 현실적 경로는 웹 다운로드 파일을 이름 그대로 커밋하는 경우다. 다만 한 번 커밋되면 그 파일의 히스토리 diff는 영구히 실패한다.
- 고치는 방법: `revisionTargetPath` 의 suffix 구성요소도 root와 같은 방식으로 퍼센트 인코딩한다(`SVNRepositoryPathNormalization.percentEncodePathComponent` 재사용).

---

## 저장소 URL 마지막 구성요소에 `@` 가 있으면 체크아웃과 자격 증명 검증이 실패한다

- 심각도: **중간**
- 근거:
  - `Sources/SVNCore/SVNClient.swift:69`, `105` — `["checkout", "--", repositoryURL, "."]`. `svnPathEscapingPegSyntax` 를 거치지 않는다.
  - `Sources/SVNCore/SVNClient.swift:573` — `["info", "--show-item", "revision", "--", repositoryURL]`. 같이 빠져 있다. 이 URL은 `workingCopyRepositoryURL`(= `svn info --show-item url`)에서 온다.
  - `Sources/SVNCore/SVNClient.swift:2149` `svnPathEscapingPegSyntax` 는 존재하고, `list`(354, 456), `copy`(URL 인자), `repositoryEntries`, 단일/이중 경로 인자 공통 함수는 모두 이것을 거친다. 위 세 지점만 빠져 있다.
  - `--` 는 peg 파싱을 막지 못한다. 아래 재현 참조.
- 재현: **실제 재현함(CLI).** 앱 코드는 문자열을 그대로 넘기는 통과 경로라 CLI 결과가 그대로 적용된다.
  ```
  $ svn co "file:///tmp/svnaudit/repo@2026" wc2
  svn: E160006: No such revision 2026
  $ svn info -- "file:///tmp/svnaudit/repo@2026"
  svn: E160006: No such revision 2026
  $ svn co "file:///tmp/svnaudit/repoX@abc" wc4
  svn: E205000: Syntax error parsing peg revision 'abc'
  ```
  이스케이프하면 정상 동작한다(`svn co "file:///tmp/svnaudit/repo@2026@"` 성공, `svn info --show-item revision -- "...repo@2026@"` → `14`).
  - peg 파싱은 **마지막 `/` 이후의 `@`** 만 본다. 따라서 `svn+ssh://user@host/svn/repo` 는 안전하다(CLI로 확인).
  - 사용자가 붙여넣은 URL의 한글은 `URL(string:)?.absoluteString` 에서 퍼센트 인코딩되지만 `@` 는 그대로 남는다(Swift로 확인: `https://h/svn/제안서@2026` → `https://h/svn/%EC%A0%9C%EC%95%88%EC%84%9C@2026`).
- 트리거 입력: 체크아웃 대화상자에 `https://svn.example.com/svn/제안서@2026` 처럼 마지막 폴더 이름에 `@` 가 든 URL을 넣을 때. 이미 등록된 프로젝트라면 자격 증명 검증(`verifyCredentials`)이 같은 이유로 실패한다.
- 증상: 체크아웃이 `No such revision 2026` 또는 `Syntax error parsing peg revision 'abc'` 로 거부된다. URL은 정확한데 리비전 이야기를 하므로 원인을 짐작할 수 없다. 앱 안에 우회 수단이 없다(URL 입력이 유일한 경로).
- 확률: 낮다. 저장소 폴더 이름에 `@` 를 쓰는 팀은 드물다. 다만 걸리면 그 프로젝트는 앱에 등록 자체가 불가능하다.
- 고치는 방법: 세 지점의 URL 인자를 `Self.svnPathEscapingPegSyntax(...)` 로 감싼다. `relocate`(244)는 감싸면 **안 된다** — 아래 "확인했고 문제 없던 지점" 참조.

---

## `export` 목적지 경로만 peg 이스케이프가 꺼져 있다

- 심각도: **낮음**
- 근거:
  - `Sources/SVNCore/SVNClient.swift:169` — `escapeSecondPegSyntax: false`. 이 값을 `false` 로 두는 이유는 코드에 적혀 있지 않다. 첫 인자(작업 복사본 경로)는 이스케이프된다.
  - `Sources/SVNCore/SVNClient.swift:2027-2049` `checkedRunWithTwoSVNPathArguments`(기본값 `escapeSecondPegSyntax: true`, 2032) — `escapeSecondPegSyntax` 가 `true` 면 목적지도 이스케이프된다.
- 재현: **실제 재현함(앱 코드 경로).** `SVNClient.export(..., destinationPath: "/tmp/svnprobe/export/out@5.txt")`:
  ```
  svn: E200009: '/tmp/svnprobe/export/out@5.txt': a peg revision is not allowed here
  ```
  `out@abc.txt` 도 같다. CLI에서 `--` 뒤에 놓아도, 목적지를 이스케이프(`out2.txt@`)하면 정상 동작한다.
  - `@` 가 **상위 디렉터리 이름**에만 있으면(`/tmp/svnaudit/dest@2026/out.txt`) 문제없다. 마지막 구성요소에 있을 때만 터진다.
- 트리거 입력: `export` 목적지 파일명에 `@` 가 든 경우. **현재 화면에서 도달하는 경로는 찾지 못했다** — 유일한 호출부 `Sources/SVNMac/RevisionFileService.swift:91` 은 목적지를 `.svn-mac-revision-save-<UUID>` 로 만들고(`RevisionFileService.swift:85`) 사용자가 고른 이름으로는 나중에 `FileManager` 가 옮긴다. UUID에는 `@` 가 없다.
- 증상: (도달 시) `svn export 실패: svn: E200009: '...': a peg revision is not allowed here`.
- 확률: 현재 0. 목적지를 사용자 지정 이름으로 직접 export하도록 바꾸는 순간 발생한다. 사용자가 저장 대화상자에서 `견적@2026.xlsx` 같은 이름을 쓰는 것은 충분히 있을 수 있다.
- 고치는 방법: `escapeSecondPegSyntax: false` 를 지우거나(기본값 `true`), 지금 값을 유지해야 하는 이유를 주석으로 남긴다.

---

## 큰 커밋 메시지는 SVN 오류가 아니라 POSIX 오류로 실패한다

- 심각도: **낮음**
- 근거: `Sources/SVNCore/SVNClient.swift:1786`, `2391` — 메시지가 `argv` 로 가므로 `ARG_MAX`(macOS 1MB, argv+envp 합산)에 걸린다. NFD 변환(위 첫 발견) 때문에 한글은 저장 바이트가 2~3배로 늘어 실효 한도가 그만큼 낮아진다(`가` U+AC00: NFC 3바이트 → NFD 자모 2개 6바이트).
- 재현: **실제 재현함(앱 코드 경로).** 한글 40만 자(NFC 1.2MB) 메시지로 `SVNClient.commit` 호출 시:
  ```
  Error Domain=NSPOSIXErrorDomain Code=7 "Argument list too long"
  ```
  같은 경로에서 한글 12만 자(NFC 360KB)와 ASCII 36만 자는 정상 커밋됐다. 즉 한도는 그 사이에 있다.
- 트리거 입력: 커밋 메시지 입력란에 수십만 자를 붙여넣기. 문서 전체를 실수로 붙여넣는 경우.
- 증상: `SVNError` 가 아닌 `NSPOSIXErrorDomain Code=7` 이 올라오므로 `SVNErrorLocalization` 의 분기를 타지 않는다. 사용자는 영문 `Argument list too long` 을 본다.
- 확률: 매우 낮다.
- 고치는 방법: 첫 발견과 같다. 메시지를 `--file` 로 넘기면 한도가 사라진다.

---

## 빈 경로 인자는 svn이 `.` 로 해석한다

- 심각도: **낮음**
- 근거:
  - `Sources/SVNCore/SVNClient.swift:1225` `resolveWorkingCopyCommandPath` — `projectRelativePath` 가 빈 문자열이면 `svnPathRelativeToWorkingCopyRoot` 도 빈 문자열이 된다(프로젝트 접두사가 있으면 `"접두사/"`).
  - `Sources/SVNCore/SVNClient.swift:2161` `svnPathsUnsafeForLineDelimitedTransport` — 빈 문자열도 그대로 `-- ""` 로 전달된다. `svnPathsUnsafeForLineDelimitedTransport`(2161)는 NUL/LF/CR만 거부하고 빈 문자열은 통과시킨다.
- 재현: **실제 재현함(CLI).** `svn info -- ""` 는 `.` 의 정보를 출력한다. 수정된 파일이 있는 작업 복사본에서 `svn revert --depth infinity -- ""` 는 `Reverted 'test.txt'` 로 **대상이 아닌 전체를 되돌렸다**. `svn delete --force -- ""` 는 작업 복사본 루트라서 `E155035` 로 막혔지만, 프로젝트가 작업 복사본의 하위 폴더면 대상이 루트가 아니라 프로젝트 폴더가 된다.
- 트리거 입력: `revert(relativePath:)`, `scheduleRepositoryCleanupDeletion(relativePath:)`, `diff(relativePath:)` 등 단일 경로 API에 빈 문자열이 들어오는 경우. **현재 호출부는 모두 `svn status` 가 준 경로를 넘기므로 도달 경로는 찾지 못했다.**
- 증상: (도달 시) 사용자가 파일 하나를 되돌렸다고 생각하는데 프로젝트 전체 수정분이 사라진다. 오류가 없다.
- 확률: 현재 0. 되돌리기는 미커밋 작업분을 지우는 비가역 동작이라 낮음 중에서는 우선순위를 둘 만하다.
- 고치는 방법: `svnPathsUnsafeForLineDelimitedTransport` 에 빈 문자열 거부를 추가한다(단일 경로·`--targets` 양쪽이 이 함수를 공유하므로 한 곳으로 해결된다).

---

# 2부 — 인자 구성 지점 전수 목록

`svn` 인자 배열을 만드는 지점과 각 지점의 경로 운반 방식이다. "원문 운반"은 `/bin/sh` 로 UTF-8 바이트를 그대로 argv에 넣는 경로(`run(svnPathArgument:)` / `svnPathArguments:`)를, "targets 파일"은 `--targets` 파일 운반을 뜻한다.

| 줄 | 명령 | 경로 운반 | peg 이스케이프 | 사용자 입력이 argv로 직접 |
|---|---|---|---|---|
| 69, 105 | `checkout` | 없음(URL을 argv로) | **없음** — 발견 4 | 저장소 URL |
| 114, 119, 1478, 1497 | `info --show-item` | 대상 없음(cwd) | 해당 없음 | — |
| 137 | `cat --revision` | 원문 운반 | 있음 | 리비전 |
| 163 | `export --revision` | 원문 운반(2인자) | 첫 인자만 — 발견 5 | 리비전, 목적지 경로 |
| 221 | `copy` (URL→WC) | 원문 운반(2인자) | 있음 | 저장소 URL, 리비전 |
| 244 | `relocate` | 없음(URL을 argv로) | 없음(**의도대로 맞음**) | 두 URL |
| 264, 975 | `propset --file` | 원문 운반 | 있음 | 속성 값(파일 운반), 속성 이름 |
| 283, 299, 312, 944, 2174 | `propget`/`propdel`/`proplist` | 원문 운반 | 있음 | 속성 이름 |
| 354, 456 | `list --recursive --xml` | 없음 | **있음** | — |
| 371 | `list --xml` | 원문 운반 | 있음 | 저장소 URL, 리비전 |
| 501 | `move --message --force-log` | 없음(퍼센트 인코딩된 URL) | 있음 | 메시지(argv, NFD — 발견 1) |
| 573 | `info --show-item revision` | 없음(URL을 argv로) | **없음** — 발견 4 | 저장소 URL |
| 626, 638, 672, 881, 1070, 1469, 1569, 1585 | `status` 계열 | 대상 없음(cwd) | 해당 없음 | — |
| 634 | `cleanup` | 대상 없음(cwd) | 해당 없음 | — |
| 693, 864, 1623, 1797, 1887 | `revert` | targets 파일 / 원문 운반 | 있음 | — |
| 784 | `cat --revision BASE` | 원문 운반 | 있음 | — |
| 889 | `propget ... .` | 없음(대상 리터럴 `.`) | 해당 없음 | — |
| 1014, 1048 | `delete --force` | targets 파일 / 원문 운반 | 있음 | — |
| 1087, 1279, 1335 | `info --xml` | 원문 운반 | 있음 | — |
| 1106, 1124 | `lock --message --force-log` | targets 파일 / 원문 운반 | 있음 | **코멘트(argv, NFD — 발견 1)** |
| 1159, 1179 | `unlock` | targets 파일 / 원문 운반 | 있음 | — |
| 1389 | `resolve --accept` | 원문 운반 | 있음 | 선택지(enum) |
| 1406, 1639 | `log --xml` | 없음 / 원문 운반 | 있음 | 리비전 범위, limit |
| 1431 | `diff --change` | 원문 운반 | **끔(수동 `@peg` 부착, 맞음)** | 리비전, 저장소 경로 — 발견 3 |
| 1601 | `update` | 대상 없음(cwd) | 해당 없음 | — |
| 1611, 1614 | `diff` | 없음 / 원문 운반 | 있음 | — |
| 1777 | `add --parents` | targets 파일 | 있음 | — |
| 1786 | `commit --message --force-log` | targets 파일 | 있음 | **메시지(argv, NFD — 발견 1)** |

다중 대상 명령은 `commit`, `add`, `delete`, `revert`, `lock`, `unlock` 여섯 개이고 **모두 `--targets` 파일을 쓴다.** argv로 경로 목록을 직접 넘기는 지점은 없다. 따라서 대상 개수·경로 길이 한계 문제는 없다. argv 길이 한계가 남는 유일한 값은 커밋 메시지와 잠금 코멘트다(발견 6).

## 확인했고 문제 없던 지점

부풀리지 않기 위해, 의심해서 확인했지만 발견이 아니었던 항목을 남긴다.

- **`relocate` 의 peg 미이스케이프는 맞는 동작이다.** `svn relocate` 는 FROM/TO 접두사를 peg 파싱하지 않는다. CLI 확인: `svn relocate file:///tmp/svnaudit/repo file:///tmp/svnaudit/repo@2026 -- .` 는 성공하고, 이스케이프한 `repo@2026@` 를 넘기면 `E170013: Unable to connect to a repository at URL 'file:///tmp/svnaudit/repo@2026@@2026'` 로 실패한다. 지금 이스케이프하지 않는 것이 정답이다.
- **`revisionDiff` 의 `@` 처리도 맞다.** peg 파싱은 마지막 `@` 를 쓰므로 `^/파일@2026.txt@3` 은 정상 해석된다. 앱 코드 경로로 `파일@2026.txt` 히스토리 diff를 재현해 성공을 확인했다.
- **`svnPathEscapingPegSyntax` 가 `@` 를 문자열 끝에 붙이는 방식은 안전하다.** `@` 가 중간 구성요소에만 있어도(`dir@2026/inner.txt@`), 이름이 `@` 로 끝나도(`trail@@`) svn이 올바르게 해석한다. CLI 확인.
- **`--targets` 파일은 공백·`-`·`%`·`#`·`?` 이름을 안전하게 운반한다.** `공간 있는 파일.txt`, `-leading.txt`, `퍼센트 50%.txt` 모두 CLI에서 정상 add됐다. `-` 로 시작하는 경로가 옵션으로 파싱되는 문제는 없다(단일 경로는 `--` 뒤, 다중 경로는 targets 파일).
- **속성 이름이 `-` 로 시작하면 옵션으로 파싱되지만(`propset` 은 `["propset", name, ...]` 로 이름이 `--` 앞에 온다) 도달 경로가 없다.** 앱이 쓰는 속성 이름은 `svn:needs-lock`(`ProjectStore+RepositoryMaintenance.swift:345,353`), `svn:ignore` / `svn:global-ignores`(`SVNIgnorePropertyKind`) 뿐이고 전부 하드코딩 상수다. 사용자가 속성 이름을 입력하는 화면은 없다.
- **속성 값은 `--file` 로 운반하므로 안전하다.** 바이너리(`00 FF 0A 41 0D 42`), 비 UTF-8(`FF FE`), 빈 값 모두 CLI에서 통과했다. `svn:eol-style`/`svn:mime-type` 값 검증 실패는 svn의 정당한 거부다(`E135001`, `E125004`).
- **URL 이중 인코딩은 없다.** `svn list --xml` 의 `<name>` 은 인코딩되지 않은 원문이고(CLI 확인: `매출 50%.xlsx`, `보고서%2010.txt` 가 원문으로 나온다), `SVNRepositoryPathNormalization.repositoryURL` 은 이 원문을 한 번만 인코딩한다. `RepositoryBrowserState.appending` 도 `%` 를 `%25` 로 정확히 인코딩한다.
- **`.gitignore` 가져오기의 CRLF는 처리된다.** `GitIgnoreParser.parse`(`GitIgnoreParser.swift:38`)가 `trimmingCharacters(in: .newlines)` 로 `\r` 을 제거한다. 또한 svn 자체가 `svn:` 속성 값의 CRLF를 LF로 정규화한다(CLI 확인).
- **경로 안의 제어문자.** 앱은 NUL/LF/CR만 거부하지만(`SVNClient.swift:2161`) 나머지는 svn이 거부한다. 탭 포함 이름은 `svn: E160005: Invalid control character '0x09' in path` 로 막힌다. 이중 방어가 아닌 것뿐이고 잘못된 동작으로 이어지지는 않는다.
- **빈 커밋 메시지는 정상이다.** `svn commit -m "" --force-log` 는 성공하고 `<msg></msg>` 로 저장된다.
- **최근 추가된 명령들의 경로 정규화 계층 통과 여부.** `cat`, `export`, `move`, `copy`, `relocate`, `propset`/`propget`/`propdel`/`proplist`, `lock --force`, `list`, `cleanup` 을 개별 확인했다. `export` 목적지(발견 5)와 URL 계열(발견 4)을 제외하면 모두 `resolveWorkingCopyCommandPath` → 원문 운반 → peg 이스케이프 계층을 정상적으로 통과한다. `cleanup` 은 대상 인자가 없다.

---

# 3부 — 경계 입력 검증이 없는 명령 목록

아래는 **경계 입력을 전혀 넣지 않는** 명령이다. 기존 통합 테스트가 쓰는 입력은 `document.xlsx`, `original.hwp`, `a.xlsx`, `source.bin`, `한글파일.txt`, `office:metadata` 처럼 전부 안전한 이름이고, 커밋 메시지는 `"원본"`, `"NFC file"`, `"mixed paths"` 처럼 검증에 쓰이지 않는 값이다. `SVNClient.svnPathEscapingPegSyntax` 의 단위 테스트(`Tests/SVNCoreTests/SVNCredentialsTests.swift:25-27`)는 함수만 검증하고 **어느 호출부가 그 함수를 거치는지는 검증하지 않는다** — 발견 4·5가 테스트를 통과한 이유다.

| 명령 | 테스트 위치 | 넣어야 하는 입력 |
|---|---|---|
| `commit` (메시지) | `SVNLogMessagePathnameTests`, `SVNUnicodeCommitIntegrationTests` | **한글 메시지 `"결산 자료 반영"` 을 넣고 `svn log --xml` 의 `<msg>` 바이트가 입력 NFC 바이트와 같은지 비교.** 문자열 비교(`==`)는 Swift가 정규화를 무시해 통과하므로 `Data(msg.utf8)` 비교가 필수. 발견 1이 이 한 줄로 잡힌다 |
| `commit` (대상) | `ProjectStoreTests`, `SVNCoreCommandsIntegrationTests` | `paths: []` — 전체가 커밋되지 않고 오류가 나야 한다(발견 2) |
| `lock` (코멘트) | `SVNLogMessagePathnameTests:29` | 한글 코멘트 `"편집 중"` 을 넣고 `svn info --xml` 의 `<comment>` 바이트 비교(발견 1) |
| `revisionDiff` | 테스트 없음 | `보고서%2010.txt`(퍼센트 이스케이프), `파일@2026.txt`, `매출 50%.xlsx`, `회의#3.txt`, 하위 디렉터리 경로. 발견 3이 첫 항목으로 잡힌다 |
| `checkout` | `SVNCredentialsTests`(URL 정규화만) | 마지막 폴더 이름에 `@` 가 든 저장소 URL(`.../제안서@2026`). 발견 4 |
| `verifyCredentials` | `SVNCredentialsTests` | 같음 — `@` 가 든 저장소 URL |
| `export` | `SVNCoreCommandsIntegrationTests:24` | 목적지 파일명 `견적@2026.xlsx`, `보고서%2010.txt`. 발견 5 |
| `fileContents` (`cat`) | `SVNCoreCommandsIntegrationTests:16` | `파일@2026.txt`, `매출 50%.xlsx`, 공백 포함 이름, NFD 이름 |
| `move` / `copy` (작업 복사본) | `SVNCoreCommandsIntegrationTests:43,69` | 원본·대상 양쪽에 `@`, `%`, 공백, 선행 `-`. 대상만 `@` 인 경우도 별도로 |
| `addIgnoreRule` / `removeIgnoreRule` | `GitIgnoreImporterTests`, `IgnoreRules` 계열 | 빈 패턴, 공백만 있는 패턴, `\r` 포함 패턴, 이미 있는 패턴 중복 추가, `-` 로 시작하는 패턴 |
| `setProperty` / `deleteProperty` | `SVNCoreCommandsIntegrationTests:88` | 빈 값(`Data()`), 값이 존재하는 경로 이름과 같은 경우, 대상 경로에 `@`·`%` |
| `scheduleDeletion` | `SVNRepositoryCleanupDeletionIntegrationTests` | `paths: []`, `@`·`%`·공백 포함 경로 |
| `repositoryEntries` / 저장소 브라우저 | `RepositoryBrowserTests` | 이름에 `%20`, `@`, `#`, `?` 가 든 항목으로 하위 탐색 및 부모 이동 |
| `relocate` | `SVNCoreCommandsIntegrationTests:229` | FROM/TO에 `@` 가 든 URL — **이스케이프하면 깨진다는 사실을 고정하는 회귀 테스트로** |
| `cleanup` | `ProjectStore+Cleanup` 계열 | 작업 복사본 하위 폴더를 프로젝트로 등록한 상태(대상 인자 없이 cwd로 동작하는 것 확인) |

공통으로 넣어야 하는 이름 세트: `파일@2026.txt`, `보고서%2010.txt`, `매출 50%.xlsx`, `-leading.txt`, `공간 있는 파일.txt`, NFD 한글 이름, 그리고 커밋 메시지에는 `test.txt`(이미 있음)와 **한글 문장**.

---

# 4부 — 확인하지 않은 것

- **NFD 커밋 메시지가 다른 클라이언트에서 어떻게 보이는지.** 저장소에 NFD 바이트가 저장되는 것까지는 재현했다. TortoiseSVN(Windows)이나 웹 저장소 뷰어에서 조합 자모가 어떻게 렌더링되는지는 이 환경(macOS)에서 확인할 수 없었다. 발견 1의 심각도는 "영구 기록되는 바이트가 입력과 다르다"는 확인된 사실에 근거했고, 화면 표시 결과는 추정으로 표시했다.
- **`svn log --search` 의 NFC/NFD 일치 여부.** CLI로 두 형태 모두 시도했으나 결과가 일관되지 않아(양쪽 모두 같은 개수 반환) 근거로 쓰지 않았다. 발견 1에서 검색 실패는 주장하지 않았다.
- **HTTP/HTTPS·`svn+ssh` 실제 서버.** 모든 재현은 `file://` 저장소다. 인증이 개입하는 경로(`--password-from-stdin`, `--trust-server-cert-failures`)와 서버측 훅의 메시지 검증은 확인하지 못했다. 인자 구성은 프로토콜과 무관하므로 발견 1~7의 판정에는 영향이 없다고 본다.
- **`ARG_MAX` 정확한 임계값.** 한글 40만 자는 실패, 12만 자는 성공을 확인했고 그 사이 값은 측정하지 않았다.
- **`Process.arguments` NFD 변환의 macOS 버전 의존성.** 이 환경(Darwin 25.6.0 / Swift 6.3.3)에서 argv 바이트를 직접 덤프해 확인했다. 다른 macOS 버전에서 다르게 동작하는지는 확인하지 않았다.
- **`normalizeRepositoryPaths`(`SVNClient.swift:501`)의 `move` 인자.** URL이 argv로 가지만 `SVNRepositoryPathNormalization.repositoryURL` 이 경로 구성요소를 퍼센트 인코딩해 ASCII로 만들기 때문에 NFD 변환의 영향을 받지 않는다고 판정했다. 이 판정은 코드 기준이며, 이름이 섞인 실제 저장소로 이 명령을 재현하지는 않았다(기존 통합 테스트 `SVNRepositoryPathNormalizationIntegrationTests` 가 통과하는 것만 확인).
- **`scheduleDeletion(paths: [])` 의 UI 도달 경로.** svn 쪽에서 `E205001` 로 막히는 것은 확인했으므로 위험은 없다고 판정했고, 호출부 가드는 개별 확인하지 않았다.
