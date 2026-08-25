# SVN 명령 인자 구성 경계 조건 전수 감사 (2026-08-25)

- 감사자: argv-agy
- 대상 파일: `Sources/SVNCore/SVNClient.swift` 및 연관 모듈
- 감사 방식: 소스 코드 읽기 전용 전수 감사 및 임시 `file://` 저장소(`svn 1.14.5`) 실제 재현 검증

---

## 1. `export` 명령 대상 경로에 `@` 포함 시 peg revision 문법 오류로 내보내기 실패

- 심각도: 높음
- 근거: `Sources/SVNCore/SVNClient.swift:169` (`escapeSecondPegSyntax: false`)
- 재현: 실제 재현함
- 트리거 입력: 내보낼 대상 로컬 경로(`destinationPath`)에 `@`가 포함된 문자열 (예: `icon@2x.png`, `report@2026.pdf`, `/Users/user/Downloads/asset@v1`)
- 증상: 내보내기가 실패하며 SVN 오류 발생:
  ```
  svn: E200009: '/Users/.../icon@2x.png': a peg revision is not allowed here
  ```
- 확률: 높음. macOS/iOS 디자인·개발 워크플로에서 레티나 에셋(`@2x`, `@3x`)이나 버전 태그(`@v1`)가 포함된 파일명을 내보내는 일은 일상적임.
- 고치는 방법: `SVNClient.export`의 `checkedRunWithTwoSVNPathArguments` 호출에서 `escapeSecondPegSyntax: false`를 `true`로 변경(또는 기본값 사용)하여 대상 경로도 peg revision 이스케이프(`path@`) 처리.

---

## 2. `move` 명령 대상 경로에 `@` 포함 시 파일명 끝에 `@`가 붙어 생성되는 파일명 오염

- 심각도: 높음
- 근거: `Sources/SVNCore/SVNClient.swift:337-343` (`runWorkingCopyCopyOrMove`가 기본값 `escapeSecondPegSyntax: true`인 `checkedRunWithTwoSVNPathArguments` 호출)
- 재현: 실제 재현함
- 트리거 입력: 작업 복사본 내 파일/폴더 이동·이름 변경 시 대상 상대 경로(`destinationRelativePath`)에 `@`가 포함된 문자열 (예: `image@2x.png`, `doc@v2.txt`)
- 증상: 파일 이름이 의도한 `image@2x.png`가 아닌 `image@2x.png@`로 변경되어 디스크와 SVN에 끝에 `@`가 붙은 오염된 파일명이 등록됨:
  ```
  A  +  image@2x.png@
        > moved from image.png
  D     image.png
        > moved to image@2x.png@
  ```
- 확률: 높음. `svn copy`와 달리 `svn move`(WC -> WC)의 대상 인자(`DST`)는 peg revision 문법을 파싱하지 않고 파일명을 그대로 생성하므로, `@`가 포함된 이름으로 rename 시 100% 파일명이 오염됨.
- 고치는 방법: `runWorkingCopyCopyOrMove`에서 `command == "move"`인 경우 `escapeSecondPegSyntax: false`를 명시.

---

## 3. `repositoryEntries` (저장소 브라우저 목록) 및 `copy` (URL 복사)에서 과거 리비전 지정 시 삭제/이동된 경로 조회 실패

- 심각도: 높음
- 근거:
  - `Sources/SVNCore/SVNClient.swift:376-383` (`repositoryEntries`)
  - `Sources/SVNCore/SVNClient.swift:224-232` (`copy` from URL)
- 재현: 실제 재현함
- 트리거 입력: 과거 리비전에는 존재했으나 이후 리비전이나 HEAD에서 삭제·이동·이름변경되어 현재 HEAD에는 없는 경로에 대해 `repositoryEntries(at:revision:)` 또는 `copy(repositoryURL:revision:to:at:)` 호출
- 증상: SVN URL 인자의 peg revision이 생략되면 기본값이 HEAD로 취급되어, HEAD에서 파일을 먼저 찾다가 실패함:
  - `repositoryEntries`:
    ```
    svn: warning: W160013: File not found: revision <HEAD>, path '/deleted_dir'
    svn: E200009: Could not list all targets because some targets don't exist
    ```
  - `copy`:
    ```
    svn: E160013: File not found: revision <HEAD>, path '/deleted_file.txt'
    ```
- 확률: 높음. 저장소 브라우저에서 과거 리비전 히스토리를 탐색하거나 과거 리비전의 삭제된 파일을 복구할 때 반드시 발생.
- 고치는 방법: `revision` 인자가 존재하고 비어있지 않으면, URL 뒤에 peg revision `@\(revision)`을 붙여(`URL@REV`) SVN이 HEAD가 아닌 해당 리비전 기준으로 경로를 조회하도록 수정.

---

## 4. `checkout` 및 `verifyCredentials` 저장소 URL에 `@` 포함 시 peg revision 문법 오류로 실패

- 심각도: 중간
- 근거:
  - `Sources/SVNCore/SVNClient.swift:69, 105` (`["checkout", "--", repositoryURL, "."]`)
  - `Sources/SVNCore/SVNClient.swift:573` (`["info", "--show-item", "revision", "--", repositoryURL]`)
- 재현: 실제 재현함
- 트리거 입력: 저장소 URL에 `@`가 포함된 문자열 (예: `http://user@server.com/svn/repo`, `svn://host/repos/app@beta`, `file:///Volumes/Data/repo@2026`)
- 증상: 체크아웃 및 자격 증명 검증이 peg revision 파싱 문법 오류로 즉시 실패하거나, `@1` 같은 숫자 태그가 포함된 경우 최신 HEAD가 아닌 과거 r1 리비전이 의도치 않게 체크아웃됨:
  ```
  svn: E205000: Syntax error parsing peg revision 'beta'
  ```
- 확률: 중간. 저장소 경로, 브랜치명, 또는 로컬 저장소 상위 폴더명에 `@`가 들어가거나 URL에 사용자명이 포함된 환경에서 발생.
- 고치는 방법: `checkout`과 `verifyCredentials`에서 `repositoryURL`에 `Self.svnPathEscapingPegSyntax(repositoryURL)`를 적용해 trailing `@` 추가.

---

## 5. `relocate`가 작업 복사본의 하위 폴더에서 실행되면 `E155019`로 실패

- 심각도: 중간
- 근거: `Sources/SVNCore/SVNClient.swift:243-247` (`checkedRun(["relocate", oldURL, newURL, "--", "."], at: path, ...)`)
- 재현: 실제 재현함
- 트리거 입력: 작업 복사본의 최상위 루트가 아닌 하위 디렉터리를 프로젝트로 등록한 상태에서 `relocate` 실행
- 증상: 저장소 주소 변경(relocate) 시 작업 복사본 루트가 아니라는 오류로 실패:
  ```
  svn: E155019: Cannot relocate '/path/to/wc/sub/dir' as it is not the root of a working copy; try relocating '/path/to/wc' instead
  ```
- 확률: 중간. 대형 SVN 저장소의 특정 하위 폴더만 프로젝트로 열어서 작업하는 사용자에게 발생.
- 고치는 방법: `findWorkingCopyRootURL`을 통해 작업 복사본 루트 경로를 조회한 뒤 `relocate` 명령의 실행 디렉터리(`at:`)를 작업 복사본 루트로 전달.

---

## 6. `relocate`의 `--` 구분자 위치 오류로 `-`로 시작하는 URL이 CLI 옵션으로 오인식됨

- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNClient.swift:244` (`["relocate", oldURL, newURL, "--", "."]`)
- 재현: 실제 재현함
- 트리거 입력: 사용자가 이전 URL(`fromRepositoryURL`)에 오타로 `-`를 붙여 입력한 경우 (예: `--https://svn.example.com/...`)
- 증상: `--` 구분자가 `oldURL`, `newURL` 뒤에 있어, `-`로 시작하는 URL이 SVN CLI 옵션으로 파싱되어 알 수 없는 옵션 에러가 나거나 도움말이 출력되고 종료 코드 0으로 끝남.
- 확률: 낮음. 사용자 입력 오타 상황에서만 발생.
- 고치는 방법: `"--"` 구분자를 `"relocate"` 바로 뒤에 배치 (`["relocate", "--", oldURL, newURL, "."]`).

---

## 7. `setProperty`, `propertyValue`, `deleteProperty`에서 `-`로 시작하는 속성명이 CLI 옵션으로 오인식됨

- 심각도: 낮음
- 근거:
  - `Sources/SVNCore/SVNClient.swift:264` (`["propset", name, "--file", valueURL.path]`)
  - `Sources/SVNCore/SVNClient.swift:283` (`["propget", name, "--no-newline"]`)
  - `Sources/SVNCore/SVNClient.swift:299` (`["propdel", name]`)
- 재현: 실제 재현함
- 트리거 입력: `-`로 시작하는 커스텀 속성 이름 (예: `-custom-prop`, `--my-prop`, `-F`)
- 증상: 속성명이 SVN CLI 옵션으로 잘못 파싱되어 옵션 충돌 에러가 발생하거나 속성이 설정/삭제되지 않고 무시됨:
  - `propset -F ...` -> `svn: E000002: Can't open file '--file': No such file or directory`
  - `propdel -q ...` -> `-q`를 quiet 옵션으로 파싱해 속성 삭제 없이 성공 종료
- 확률: 낮음. 대부분의 SVN 속성은 `svn:` 접두사나 일반 영문으로 시작함.
- 고치는 방법: 속성명 `name`이 `-`로 시작하지 않는지 검증하거나, `SVNClient` 내부에서 속성명 전달 위치를 옵션 파싱 영역 밖으로 격리.

---

## 경계 입력 검증이 없는 명령 목록

| 명령 | 현재 테스트 상태 | 버그 검출을 위해 추가해야 하는 경계 입력 |
|---|---|---|
| `export` | `document.xlsx`, `archive` 등 단순 영문/한글 경로만 검증 | 대상 경로(`destinationPath`)에 `@2x`, `@v1`이 포함된 경우 (`"image@2x.png"`, `"/tmp/export@dir"`), 경로에 공백·제어문자가 포함된 경우 |
| `move` | `original.hwp` -> `moved.hwp` 단순 경로만 검증 | 대상 경로(`destinationRelativePath`)에 `@`가 포함된 경우 (`"image@2x.png"`). 실제 디스크와 SVN에 생성된 파일명이 끝에 `@` 없이 정확한지 검증 |
| `copy` (URL) | HEAD에 여전히 존재하는 파일(`source.bin`)의 과거 리비전 복사만 검증 | 과거 리비전에는 존재했으나 HEAD에서 삭제·이동된 파일/폴더의 URL 복사 (`revision: "1"` 지정 시 HEAD 조회 실패 방지 검증), URL 및 대상 경로에 `@` 포함 |
| `repositoryEntries` (list) | HEAD에 존재하는 폴더의 과거 리비전 메타데이터 조회만 검증 | 과거 리비전에는 존재했으나 HEAD에서 삭제·이동된 디렉터리/파일의 URL 조회, 저장소 URL에 `@`가 포함된 경우 |
| `checkout` / `verifyCredentials` | `@`가 없는 표준 URL 경로만 검증 | URL에 `@`가 포함된 경우 (`"file:///tmp/repo@test"`, `"http://user@server/repo"`), 숫자 태그가 포함된 URL (`"file:///tmp/repo@1"`) |
| `relocate` | 작업 복사본 루트에서의 기본 relocate만 검증 | 작업 복사본의 하위 폴더(subdirectory)를 등록한 프로젝트에서의 `relocate` 실행, URL에 `@` 포함된 경우, URL이 `-`로 시작하는 오타 |
| `setProperty` / `propertyValue` / `deleteProperty` | `office:metadata`, `svn:needs-lock` 등 정상 속성명만 검증 | `-`로 시작하는 속성명 (`"-custom"`), 빈 데이터(`Data()`) 속성값 설정, 개행이 불일치하는 파일에 `svn:eol-style` 설정 시 동작 |
| `lock` / `unlock` | `alice editing`, `bob takeover` 등 단순 코멘트만 검증 | 코멘트가 빈 문자열(`""`), 코멘트가 `-`로 시작하는 경우 (`"-m message"`), 파일 경로에 `@` 포함 (`"image@2x.png"`), 대량 다중 경로 잠금/해제 |

---

## 확인하지 않은 것

1. **원격 HTTPS 서버(Apache mod_dav_svn) 전용 오류**: 본 감사는 로컬 `file://` 저장소 환경에서 `svn 1.14.5` CLI 바이너리를 통해 직접 재현하고 검증했습니다. HTTP(S) 계층 특유의 웹서버 설정(예: mod_dav_svn의 특정 URL 디코딩 특성)은 로컬 SVN CLI 인자 해석 규칙과 동일함을 svn 공식 문서로 확인했으나 실제 원격 Apache 데몬을 띄워 대조하지는 않았습니다.
2. **APFS 이외의 이종 파일시스템(NFS/SMB 마운트)**: macOS APFS 로컬 볼륨에서 테스트를 진행했습니다. 네트워크 드라이브(NFS, SMB) 상에서 SVN working copy를 마운트하여 운용할 때의 파일시스템 레벨 잠금/경로 동작 차이는 감사 범위에서 제외했습니다.
