# svn 명령 인자 구성 경계 조건 감사

날짜: 2026-08-25  
범위: `Sources/SVNCore/SVNClient.swift`의 모든 `svn` 인자 구성 지점과 `Sources/SVNMac` 입력 경로. 소스 수정 없음. 이미 고친 `--force-log` pathname 검사는 발견에서 제외.

## 감사 기준과 재현 환경

- 설치된 SVN: 1.14.5
- 파일 시스템: APFS
- 근거 명령: `svn help -v`와 `svn help <명령> -v`의 실제 출력. 확인한 명령은 `checkout`, `info`, `cat`, `export`, `move`, `copy`, `relocate`, `propset`, `propget`, `propdel`, `proplist`, `list`, `status`, `cleanup`, `revert`, `delete`, `lock`, `unlock`, `resolve`, `log`, `diff`, `update`, `add`, `commit`.
- 실제 재현: `/tmp/svn-argv-audit.o061bi` 아래 임시 `file://` 저장소. 앱 호출 대신 앱과 같은 argv를 SVN CLI에 전달했다. NUL·인자 길이는 Swift `Foundation.Process`에 설치된 SVN을 직접 연결해 확인했다.
- 도움말상 핵심 계약:
  - 대상 생략이 허용되는 명령은 현재 디렉터리 `.`를 기본 대상으로 삼는다. `commit`도 `PATH...`가 없으면 현재 작업복사본을 커밋한다.
  - `checkout URL[@REV]`, `info TARGET[@REV]`, `cat TARGET[@REV]`, `copy SRC[@REV]` 등은 `@`를 peg revision 구문으로 해석한다.
  - `commit` 메시지는 빈 문자열도 허용한다. 메시지·잠금 설명·URL 간 move 메시지는 `--message`와 `--file`을 모두 지원한다.
  - `--targets`는 파일 내용을 추가 대상 인자로 읽는다.

## 인자 구성 지점 전수표

- 직접 argv, 작업 디렉터리 자체가 대상: `validateWorkingCopy`, `workingCopyRepositoryURL`, `status`, `cleanup`, `workingCopyEntries`, `ignoreRules`, `log`, `workingCopyRevision`, `workingCopyRepositoryPath`, `incomingCommits`, `workingCopyIsOutOfDate`, `remoteChanges`, `update`, 루트 `diff`. 근거: `Sources/SVNCore/SVNClient.swift:113-120,625-638,880-897,1396-1412,1468-1516,1562-1618`.
- 직접 argv, URL이 대상: `checkout`, 저장소 경로 정규화용 `list`, 서버 URL 간 `move`, `verifyCredentials`, `relocate`. 근거: `Sources/SVNCore/SVNClient.swift:56-110,346-385,454-509,565-579,235-247`.
- 단일 경로 공통 계층: `cat`, `propset`, `propget`, `propdel`, `proplist`, 정리용 `delete`, `lock`, `unlock`, `info`, `resolve`, 파일 `diff`, `revert`, 파일 `log`. `resolveWorkingCopyCommandPath` 후 원문 UTF-8 파일 운반, 마지막 `--`, `svnPathEscapingPegSyntax`를 사용한다. 근거: `Sources/SVNCore/SVNClient.swift:123-146,250-318,1036-1052,1079-1112,1151-1168,1191-1304,1328-1339,1382-1393,1609-1646,2002-2025,2112-2147`.
- 2개 경로 공통 계층: working-copy `move`/`copy`, URL에서 working-copy로 `copy`, `export`. 두 경로를 원문 UTF-8 파일로 운반하고 마지막 `--` 뒤에 둔다. source peg escape가 기본이다. `export` 목적지는 로컬 출력 경로라 peg escape를 끈다. 근거: `Sources/SVNCore/SVNClient.swift:148-232,320-344,2027-2067,2349-2369`.
- 다중 경로 공통 계층: `add`, `delete`, `revert`, `lock`, `unlock`, `commit`. 경로를 `--targets` 파일에 원문 UTF-8로 쓰고 각 경로의 `@`를 escape한다. NUL/LF/CR 경로는 거부한다. 근거: `Sources/SVNCore/SVNClient.swift:676-700,841-868,982-1018,1115-1188,1649-1802,2069-2165`.
- 의도한 peg revision: 과거 revision `diff`는 `^/경로@PEGREV`를 직접 만들고 자동 escape를 끈다. 근거: `Sources/SVNCore/SVNClient.swift:1415-1438`.
- 옵션 값: revision, property name, 메시지, username은 argv로 전달한다. property 값은 임시 파일, password는 stdin을 쓴다. 근거: `Sources/SVNCore/SVNClient.swift:123-175,221-299,2328-2347,2477-2482`.

## NUL이 든 커밋 메시지가 앱 프로세스를 종료한다

- 심각도: 중간
- 근거: `Sources/SVNMac/CommitControlsView.swift:13-16,63-66`, `Sources/SVNCore/SVNClient.swift:1783-1792,2308-2317,2389-2392`
- 재현: 실제 재현함
- 트리거 입력: 커밋 메시지 `"정산\u{0000}완료"`. 같은 경계는 저장소 경로 정규화 메시지에도 있다. 2,000,000자 메시지는 별도 길이 경계를 재현했다.
- 증상: `Foundation.Process.arguments`에 NUL 문자열을 넣어 SVN을 실행하면 `NSInvalidArgumentException: *** -[NSString fileSystemRepresentation]: Unable to form file system representation for string`으로 프로세스가 종료된다. 2,000,000자 문자열은 `NSPOSIXErrorDomain Code=7 "Argument list too long"`으로 실행이 거부된다.
- 확률: NUL 입력은 매우 드물다. 복사한 외부 문자열에 포함될 때만 현실적이다. 초대형 메시지도 일반 사무 커밋에서는 드물다.
- 고치는 방법: 사용자 메시지를 임시 UTF-8 파일로 운반하고 `--file`을 쓰며, NUL은 실행 전에 명시적으로 거부한다.

## move/copy가 NFD 목적지 이름을 그대로 새 저장소 경로로 만든다

- 심각도: 중간
- 근거: `Sources/SVNMac/RepositoryDialogs.swift:766-790`, `Sources/SVNMac/ProjectStore+RepositoryMaintenance.swift:36-62,219-270`, `Sources/SVNCore/SVNClient.swift:177-232,320-344,1697-1764`, `Tests/SVNCoreTests/SVNCoreCommandsIntegrationTests.swift:43-86`, `Tests/SVNMacTests/RepositoryMaintenanceTests.swift:45-86`
- 재현: 실제 재현함
- 트리거 입력: 이름 변경/이력 복사 화면의 새 이름에 NFD `"\u{1100}\u{1175}-copy.txt"`를 입력한다. 기존 NFD 이름이 입력칸 기본값이고 사용자가 뒤에 `-복사`만 붙이는 경우도 같은 바이트를 만든다.
- 증상: `svn copy` 성공 후 저장소 `svn list`에 `e1 84 80 e1 85 b5` NFD 바이트가 그대로 저장됐다. 기대 NFC `기`는 `ea b8 b0`이다. 새 파일 commit만 통과하는 `SVNPathNormalization.normalizeNewPaths`를 move/copy 목적지는 거치지 않는다.
- 확률: 한글 기존 경로가 NFD인 팀에서 이름 끝만 수정해 복사·이동하면 발생 가능하다. 새 기능의 일반 사용 흐름과 맞닿아 있다.
- 고치는 방법: move/copy 목적지 이름도 신규 add와 같은 NFC 계획·디스크 바이트 검증을 거친 뒤 SVN 명령에 넘긴다.

## `@`가 든 저장소 폴더를 탐색해도 checkout과 자격 증명 확인이 실패한다

- 심각도: 중간
- 근거: `Sources/SVNMac/RepositoryBrowserState.swift:127-131,158-160,216-220`, `Sources/SVNCore/SVNClient.swift:64-75,100-110,565-579,2149-2151`, `Sources/SVNMac/ProjectStore.swift:1305-1339`
- 재현: 실제 재현함
- 트리거 입력: 저장소 폴더 `trunk@team`, URL `file:///tmp/.../repo/trunk@team`. 저장소 탐색기가 이 폴더를 선택해 만든 URL도 literal `@`를 유지한다.
- 증상: 현재 checkout argv는 `svn checkout -- URL .`, 자격 증명 확인은 `svn info ... -- URL`이며 URL에 trailing `@`를 붙이지 않는다. 둘 다 `svn: E205000: Syntax error parsing peg revision 'team'`으로 실패했다. 같은 URL 뒤에 `@`를 붙이면 성공했다.
- 확률: `@` 폴더명은 한글 일반 문서명보다 드물다. 팀·메일·버전 표기에 쓰이면 checkout과 계정 저장 확인이 막힌다.
- 고치는 방법: checkout과 `verifyCredentials` URL도 `svnPathEscapingPegSyntax`를 거치는 단일 SVN 경로 계층으로 보낸다.

## raw NFD 저장소 URL을 checkout 전에 NFC로 바꿔 다른 경로를 조회한다

- 심각도: 중간
- 근거: `Sources/SVNMac/RepositoryDialogs.swift:231-238,366-387`, `Sources/SVNMac/ProjectStore.swift:765-807`, `Sources/SVNCore/SVNClient.swift:64-69,100-105`, `Tests/SVNCoreTests/SVNCredentialsTests.swift:68-94`
- 재현: 실제 재현함
- 트리거 입력: 저장소에 NFD 이름 `"\u{1100}\u{1175}"`만 있을 때 Add Repository URL 입력칸에 raw NFD `file:///tmp/.../repo/기`를 붙여 넣는다.
- 증상: raw NFD URL을 CLI에 그대로 주면 checkout 성공했다. 코드의 `precomposedStringWithCanonicalMapping`과 같은 NFC URL `.../%EA%B8%B0`는 `svn: E170000: URL '.../%EA%B8%B0' doesn't exist`로 실패했다. 기존 테스트는 이 바이트 변경을 기대하므로 회귀를 잡지 못하고 반대로 고정한다. 이미 `%E1%84%80%E1%85%B5`로 인코딩된 NFD URL은 ASCII라 변환되지 않고 성공한다.
- 확률: 브라우저가 만든 percent-encoded URL은 안전하다. 사용자가 raw 한글 URL을 직접 붙여 넣고 저장소에 legacy NFD 경로만 있을 때 발생한다.
- 고치는 방법: URL 전체를 Unicode precompose하지 말고 URL path component의 기존 percent-encoded/raw UTF-8 의미를 보존한다.

## 빈 대상 배열은 commit 범위를 작업복사본 전체로 넓힌다

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNClient.swift:1649-1656,1783-1792,2072-2109,2153-2159`, `Sources/SVNMac/ProjectStore.swift:664-668,1217-1244`, `Tests/SVNCoreTests/SVNCredentialsTests.swift:1008-1044,1590-1635`
- 재현: 실제 재현함
- 트리거 입력: `SVNClient.commit(at: paths: [], message: "빈 선택")`. 생성되는 targets 파일은 `"\n"`이다. 0바이트 targets 파일도 같은 결과였다.
- 증상: 수정된 `a.txt`가 있는 작업복사본에서 `svn commit --targets <빈 파일>`이 `a.txt`를 커밋하고 `Committed revision 3.`을 반환했다. 현재 `ProjectStore`는 빈 선택을 막으므로 정상 UI에서는 도달하지 않는다. 코어 API나 이후 호출부가 빈 배열을 넘기면 선택 커밋이 전체 커밋으로 바뀐다.
- 확률: 현재 UI 가드 때문에 낮다. 비동기 호출부 추가나 코어 직접 호출 회귀가 있어야 한다.
- 고치는 방법: 다중 대상 공통 계층 또는 `commit` 진입점에서 빈 배열을 실행 전에 거부한다.

## 경계 입력 검증이 없는 명령 목록

현재 테스트는 `svnTargetsFileContents`의 `@` 변환과 LF 거부, 20,000개 commit 대상, 일부 NFD commit 경로를 검증한다. 대부분 새 명령 통합 테스트는 ASCII 안전 입력만 쓴다.

- `checkout`, 원격 `info`: literal `trunk@team`, raw NFD URL, `%25`가 든 URL, 이미 `%40`로 인코딩된 URL을 실제 저장소로 검증해야 한다. 현재 checkout NFD 테스트는 fake SVN으로 NFC 변환만 기대한다.
- `cat`, `export`: `보고서@최종.hwp`, `-초안.hwp`, 저장소 원문 NFD 경로, 목적지 `-내보내기@1.hwp`, 빈/잘못된 revision을 넣어야 한다. 현재 테스트는 `document.xlsx`, `archive/document.hwp`, revision `2`만 쓴다.
- working-copy `move`, `copy`: source `보고서@최종.hwp`와 `-초안.hwp`, NFD source, NFD destination, NFC destination을 실제 commit 후 `svn list` 원문 바이트로 비교해야 한다. 현재 통합 테스트는 `original.hwp`, `moved.hwp`, `copied.hwp`만 쓴다.
- URL에서 working-copy로 `copy`: source URL의 `%40`, `%25`, percent-encoded NFD와 목적지의 `@`, leading `-`, NFD를 넣어야 한다. 현재는 ASCII `source.bin`만 쓴다.
- `relocate`: raw/encoded 공백, `%25`, literal `@`, percent-encoded NFD old/new URL을 자동화해야 한다. 이번 CLI 재현에서는 literal `@`와 raw 공백 URL이 성공했지만 저장소 테스트에는 없다.
- `propset`, `propget`, `propdel`, `proplist`: `@`, leading `-`, NFD 대상 경로와 빈 property 값을 넣어야 한다. binary property 값의 NUL/LF/CR은 기존 통합 테스트가 이미 검증한다. 앱의 property name은 현재 `svn:needs-lock`, `svn:ignore`, `svn:global-ignores`로 고정돼 있다.
- `list`: URL의 literal `@`, `%25`, percent-encoded NFD, invalid revision을 넣어야 한다. 현재 실제 테스트는 한글·공백 entry와 숫자 revision만 검증한다.
- 저장소 URL 간 `move`(NFD 경로 정규화): 경로 component `@`, `%`, 메시지의 NUL·ARG_MAX 근접 길이를 넣어야 한다. 기존 NFD 3단계 통합 테스트는 경로 정규화만 검증한다.
- `add`, `delete`, `revert`, `commit`: `@`와 leading `-` 대상의 실제 명령 성공, 빈 대상 배열, NUL/LF/CR 거부를 명령별로 검증해야 한다. 현재 `@`는 targets 파일 문자열 단위 테스트뿐이고, 빈 commit 대상은 없다.
- `lock`, `unlock --force`: `@`, leading `-`, NFD 대상, 빈 대상 배열을 넣어야 한다. lock comment에는 빈 문자열, NUL, ARG_MAX 근접 길이를 넣어야 한다. 현재는 `a.xlsx`, `b.hwp`와 pathname형 comment만 검증한다.
- `resolve`, 파일 `log`, 파일 `diff`, revision `diff`: `@`, leading `-`, NFD 대상과 `^/경로@이름@PEGREV`를 넣어야 한다. revision 값에는 숫자 외 `HEAD`, `{DATE}`, 역방향 change를 넣어야 한다.
- `status`, `cleanup`, `update`, 루트 `log`/`diff`: 사용자 경로를 argv로 받지 않고 작업 디렉터리 자체를 대상으로 하므로 `@`/leading `-` 대상 경계는 해당하지 않는다. 작업복사본 로컬 경로 NFD는 별도 filesystem URL 경계다.

이 버그를 잡았어야 한 최소 회귀 입력은 다음과 같다.

- checkout/원격 info: 저장소 디렉터리 `trunk@team`
- move/copy: NFD `"\u{1100}\u{1175}-복사.hwp"` 목적지와 commit 뒤 raw `svn list` 바이트
- checkout URL: raw NFD `"file:///.../기"`와 percent-encoded NFD `"file:///.../%E1%84%80%E1%85%B5"`를 서로 다른 케이스로 유지
- commit 공통 계층: `paths: []`, message `"a\u{0000}b"`, 1 MiB를 넘는 message
- 각 path 명령: `"-초안@1.hwp"`, `"보고서\n최종.hwp"`

## 확인하지 않은 것

- SwiftUI `TextField`에 clipboard를 통해 U+0000이 실제로 유지되는지는 UI에서 확인하지 않았다. `Foundation.Process`의 동일 문자열 argv crash만 실제 재현했다.
- HFS+에서 move/copy가 목적지 파일명을 다시 NFD로 바꾸는 동작은 확인하지 못했다. 현재 APFS에서는 명령에 준 NFD 바이트가 저장소에 그대로 커밋되는 것만 확인했다.
- HTTP/HTTPS/SVN/SSH 서버별 URL canonicalization은 서버가 없어 재현하지 못했다. URL 발견은 `file://` 저장소와 SVN 1.14.5 기준이다.
- macOS의 개별 파일명 한계보다 긴 단일 path는 만들 수 없어 실제 재현하지 않았다. 다중 대상 20,000개는 기존 테스트가 `--targets` 사용을 검증한다.
- LF/CR/NUL 파일명은 공통 운반 계층이 `unsupportedTargetPath`로 선제 거부한다. SVN까지 전달하는 재현은 하지 않았다.
- `relocate`의 literal `@`와 raw 공백 URL은 실제 성공했다. relocate는 도움말상 peg target이 아닌 URL prefix라 발견에서 제외했다.
- 빈 property 값, U+0001 메시지, 줄바꿈 메시지는 CLI에서 실제 성공했다. property 값은 `--file`을 쓰므로 NUL/LF/CR binary 값도 기존 통합 테스트가 통과한다.
- property name `-x`는 옵션으로 오해되지만 `--` 뒤에 둬도 `E195011: '-x' is not a valid Subversion property name`이다. 현재 UI가 임의 property name을 받지 않으므로 발견에서 제외했다.
