# B4a 블록(코어 모델·파서·파일시스템) 전수 감사

## 읽은 파일
- `Sources/SVNCore/GitIgnoreImporter.swift` — 127줄 — `.gitignore` 규칙을 SVN 무시 속성 제안으로 변환하고 미지원·충돌·이미적용을 분류한다.
- `Sources/SVNCore/GitIgnoreParser.swift` — 108줄 — `.gitignore` 텍스트를 부정/앵커/디렉터리전용 플래그가 붙은 규칙 목록으로 파싱한다.
- `Sources/SVNCore/Models.swift` — 550줄 — 상태·충돌·로그·리비전·오류 등 코어 도메인 모델 전체.
- `Sources/SVNCore/SVNAdditionalModels.swift` — 70줄 — 인자 오류, 인증서 실패 종류, 속성, 저장소 항목 모델.
- `Sources/SVNCore/SVNApplicationSupport.swift` — 37줄 — Application Support 루트 경로와 `SVN Mac` → `SVN KR` 폴더 이관.
- `Sources/SVNCore/SVNFileSystem.swift` — 49줄 — 경로 포함 검사, 청크 단위 덮어쓰기, 내용 동일성 비교.
- `Sources/SVNCore/SVNHistoryTimeline.swift` — 54줄 — 서버 커밋 목록에서 로컬 기준 리비전의 표시 위치 계산.
- `Sources/SVNCore/SVNVolumeNormalizationProbe.swift` — 82줄 — 실제 파일을 만들어 볼륨이 NFC 파일명을 보존하는지 확인하고 경로별로 캐시.
- `Sources/SVNCore/SVNXMLParser.swift` — 692줄 — `svn` XML 출력 전체(status/info/log/list/propget/lock/conflict) 파싱 델리게이트.

보조로 읽은 파일(발견 판정용, 보고 대상 아님): `SVNClient.swift`(관련 구간), `ProjectStore+Ignore.swift`, `ProjectStore+Conflicts.swift`, `ConflictFileService.swift`, `TemporaryFileClassification.swift`, `IgnoreRulesView.swift`, `HistoryView.swift`, 그리고 대응 테스트 6종.

재현 환경: `svn 1.14.5`, `file:///tmp/b4a/repo` 임시 저장소, 한글 NFD 경로 포함.

## 발견

### 속성 충돌 산출물 `.prej` 가 변경 목록에 남고 "전체 선택"에 포함된다
- 심각도: 중간
- 근거: `Sources/SVNCore/SVNXMLParser.swift:35`–`48` (`isConflictArtifact` 가 `.mine` 과 `.r<숫자>` 만 걸러낸다), `Sources/SVNCore/Models.swift:350`–`355` (`isSelectableForCommit` 는 미버전 항목을 커밋 대상으로 허용)
- 재현: 실제 재현함
- 트리거: 같은 파일을 두 사람이 고치고 속성까지 바꾼 뒤 업데이트 → 내용+속성 충돌 발생 → 변경 목록에서 "전체 선택" → 커밋.
- 증상: `svn status` 가 내보내는 네 개 산출물 중 `문서.txt.mine`, `문서.txt.r1`, `문서.txt.r2` 는 목록에서 사라지지만 `문서.txt.prej` 만 미버전 파일로 남는다. 커밋 경로는 선택된 미버전 경로를 `svn add --parents` 로 먼저 추가하므로(`SVNClient.swift:1838`, `1854`) 산출물이 저장소에 올라간다. 임시 저장소에서 실제로 커밋됐다: `Adding 문서.txt.prej` / `Committed revision 6.` 충돌 파일이 아직 충돌 상태여도 명시적 대상 커밋은 막히지 않는다.
- 확률: 중간. 이 팀은 xlsx·hwp 를 잠금으로 돌리지만 잠금이 걸리지 않은 파일과 폴더 속성에서는 속성 충돌이 나고, "전체 선택"은 기본 동작이다.
- 고치는 방법: `isConflictArtifact` 에 `.prej` 접미사를 추가한다(내용 산출물과 같은 정규화 비교 사용).

### `svn propget --xml` 의 `target/@path` 가 절대경로라서 무시 규칙 디렉터리가 전부 절대경로가 된다
- 심각도: 중간
- 근거: `Sources/SVNCore/SVNXMLParser.swift:453`, `466`–`477` (`target/@path` 를 프로젝트 상대 디렉터리로 그대로 사용)
- 재현: 실제 재현함
- 트리거: 무시 규칙 화면을 열거나(`loadIgnoreRules`) `.gitignore` 비교를 실행한다.
- 증상: 앱이 쓰는 인자 그대로 실행한 결과가 항상 절대경로다.
  ```
  $ svn propget svn:ignore --recursive --show-inherited-props --xml .
  <target path="/private/tmp/b4a/wc6"> ... <target path="/private/tmp/b4a/wc6/subproj">
  ```
  (같은 명령의 비 XML 출력은 `. - *.tmp` / `subproj - sub-only` 로 상대경로다. `--recursive` 유무와 무관하게 XML 만 절대경로다.)
  결과 세 가지:
  1. 규칙 목록이 디렉터리 칸에 `/Users/이름/Documents/...` 전체 경로를 그린다(`IgnoreRulesView.swift:109`).
  2. `GitIgnoreImporter` 의 이미적용 판정이 절대경로 대 `"."`/`"lib"` 비교라 절대 일치하지 않는다(`GitIgnoreImporter.swift:86`–`92`). 이미 있는 규칙이 "적용 대상"으로 자동 선택되고 "규칙 N개를 적용했습니다" 알림이 뜬다(실제 쓰기는 `addIgnoreRule` 의 패턴 중복 검사에서 멈춘다).
  3. 작업 복사본 루트가 아니라 그 하위 폴더를 프로젝트로 등록한 경우, 규칙 삭제가 `svnProjectPathPrefix + "/" + 절대경로` 를 대상으로 삼아 깨진다. 실제 오류: `svn: E155010: The node '/private/tmp/b4a/wc6/subproj/private/tmp/b4a/wc6' was not found.` 프로젝트가 작업 복사본 루트면 절대경로가 유효해서 우연히 동작한다.
- 확률: 높음(1·2번은 무시 규칙 화면을 여는 모든 사용자). 3번은 중간(하위 폴더 등록 사용자만).
- 고치는 방법: 파서에서 `target/@path` 를 명령 실행 기준 경로에 대해 상대화한다(루트면 `"."`). 기준 경로를 파서 인자로 받아야 한다.

### `.gitignore` 의 한글 패턴이 NFC 그대로 기록돼 svn 이 아무것도 무시하지 않는다
- 심각도: 중간
- 근거: `Sources/SVNCore/GitIgnoreImporter.swift:73`, `76`–`80` (`.gitignore` 원문 바이트를 그대로 패턴으로 제안)
- 재현: 실제 재현함
- 트리거: `.gitignore` 에 한글 폴더·파일 패턴(`임시/`)이 있는 프로젝트에서 "Git 무시 규칙 가져오기" 실행.
- 증상: svn 의 무시 판정은 바이트 비교다. NFC 패턴은 디스크의 NFD 이름과 매칭되지 않는다.
  ```
  # 디스크 이름 NFD(e18480...), 패턴 NFC(ec9e84...)
  $ svn status
   M      .
  ?       임시        ← 무시되지 않음
  # 같은 패턴을 NFD로 넣으면
  $ svn status
   M      .           ← 무시됨
  ```
  앱은 "규칙 N개를 적용했습니다" 로 성공을 알리고, 폴더는 계속 미변경 목록에 남는다. 사용자가 오른쪽 클릭 메뉴로 직접 추가하는 경로(`ProjectStore+Ignore.swift:39`)는 `svn status` 가 준 NFD 경로를 쓰므로 정상 동작한다. 같은 일을 하는 두 경로가 갈라져 있다.
- 확률: 중간. 한글 폴더명이 흔하고, `.gitignore` 는 보통 편집기에서 NFC 로 저장된다.
- 고치는 방법: 제안 패턴을 실제 디스크 표기(작업 복사본 항목 이름)에 맞춰 정규화하거나, 대응하는 항목이 없으면 경고로 표시한다.

### `isVersioned` 가 방금 추가한 폴더를 미버전으로 판정해 무시 규칙 가져오기를 막는다
- 심각도: 낮음
- 근거: `Sources/SVNCore/Models.swift:384`–`389` (`revision >= 0` 요구), 소비자 `ProjectStore+Ignore.swift:109`, `144`
- 재현: 실제 재현함(입력 XML 확인 + svn 동작 확인)
- 트리거: `새폴더` 를 만들어 추가만 하고 커밋하지 않은 상태에서 `.gitignore` 의 `새폴더/tmp` 를 가져온다.
- 증상: 추가 예정 항목의 verbose status 는 `item="added" revision="-1"` 이라 `isVersioned == false` 다. `managedDirectories` 에 들어가지 못해 규칙이 "SVN이 관리하는 속성 대상 디렉터리를 찾을 수 없습니다: 새폴더" 충돌로 분류되고 선택할 수 없다. 실제로는 `svn propset svn:ignore -F ... 새폴더` 가 정상 동작한다(`property 'svn:ignore' set on '새폴더'`). `trackedPaths` 에서도 빠지므로 "이미 추적 중" 경고도 뜨지 않는다.
- 확률: 낮음~중간. 폴더를 추가한 직후 무시 규칙을 정리하는 순서에서만 걸린다.
- 고치는 방법: 소비자마다 뜻이 달라지는 이름이므로 `isVersioned`(저장소 기반)와 별개로 `added`/`replaced` 를 포함하는 판정을 모델에 추가하고, 무시 규칙 쪽이 후자를 쓴다. `ProjectStore+RepositoryMaintenance.swift:231`, `325` 는 이미 `|| status == "added" || status == "replaced"` 를 손으로 붙여 같은 문제를 국소적으로 때웠다 — 규칙이 두 벌이다.

### 트리 충돌의 action/reason/kind 는 파싱·모델·테스트만 있고 화면에 없다
- 심각도: 낮음
- 근거: `Sources/SVNCore/Models.swift:126`–`128`, `176`–`178`, `Sources/SVNCore/SVNXMLParser.swift:306`–`310`
- 재현: 실제 재현함(파서 입력 XML 확인), 화면 부재는 코드 기준
- 트리거: 트리 충돌 해결 화면을 연다.
- 증상: 실제 `svn info --xml` 은 `<tree-conflict kind="file" reason="edit" action="delete" operation="update">` 를 준다. 파서가 세 값을 모두 담지만 `Sources/` 전체에서 소비자가 없다(테스트 6곳만 참조). 사용자는 "서버가 지웠는데 내가 고쳤다" 같은 판단 근거를 화면에서 볼 수 없다. `conflictTypes`(`Models.swift:184`)도 생산 코드에서 호출부가 없다.
- 확률: 낮음(트리 충돌 자체가 드물다). 다만 걸리면 정보가 가장 필요한 순간이다.
- 고치는 방법: 트리 충돌 화면이 세 값을 문장으로 표시하거나, 표시하지 않기로 정했으면 모델에서 지운다.

### `SVNConflictDetails` 의 `conflicts` 기본값이 목록 유실을 컴파일 단계에서 숨긴다
- 심각도: 낮음
- 근거: `Sources/SVNCore/Models.swift:201`, `216`–`229` (`conflicts` 기본값 `[]` + 비어 있으면 평면 필드로 단일 레코드 합성)
- 재현: 코드 기준 추정
- 트리거: 작업 복사본 루트의 하위 폴더를 프로젝트로 등록한 상태에서 충돌 해결 화면 진입.
- 증상: `SVNClient.conflictDetailsRelativeToRegisteredProject`(`SVNClient.swift:1430`–`1441`)가 경로 접두사를 떼며 이 이니셜라이저를 호출할 때 `conflicts:` 와 트리 메타데이터 세 필드를 넘기지 않는다. 인자에 기본값이 있어 컴파일은 통과하고, 충돌 목록은 대표 유형 하나로 조용히 줄어든다. 내용/속성 오분류는 `ConflictFileService.classify` 가 `svn status` 교차 판정으로 막아 두었고(`ConflictFileService.swift:45`–`63` 주석이 이 경로를 명시한다), 트리 메타데이터는 위 발견대로 소비자가 없어 지금은 눈에 보이는 피해가 없다. 남은 위험은 다음에 목록이나 트리 값을 쓰는 화면이 생길 때 같은 자리에서 다시 유실된다는 점이다.
- 확률: 낮음(현재 관측 가능한 증상 없음).
- 고치는 방법: 평면 필드 전용 이니셜라이저와 목록 이니셜라이저를 분리해 목록 없는 재구성이 컴파일되지 않게 한다.

### `.gitignore` 의 디렉터리 전용 표시(`build/`)를 변환에서 버린다
- 심각도: 낮음
- 근거: `Sources/SVNCore/GitIgnoreParser.swift:59`–`60` (`isDirectoryOnly` 파싱), `Sources/SVNCore/GitIgnoreImporter.swift` 전체(참조 없음)
- 재현: 코드 기준 추정
- 트리거: `.gitignore` 에 `build/` 가 있고 같은 이름의 파일 `build` 도 있는 프로젝트에서 가져오기 실행.
- 증상: `build/` 와 `build` 가 동일한 `svn:ignore` 패턴 `build` 로 변환된다. git 은 폴더만 무시하지만 svn 은 같은 이름 파일도 무시한다. 파일이 목록에서 사라져 커밋에서 빠진다. `isDirectoryOnly` 는 파서와 테스트에만 존재한다.
- 확률: 낮음. 같은 이름의 파일과 폴더가 함께 있어야 한다.
- 고치는 방법: 디렉터리 전용 규칙은 그 뜻을 SVN 무시 속성으로 표현할 수 없으므로 경고 문구를 붙이거나 `unsupported` 로 분류한다.

### 로그 리비전 속성의 `encoding="base64"` 를 무시해 base64 원문을 보여준다
- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNXMLParser.swift:604`–`605`, `631`–`639` (`LogDelegate` 는 `name` 만 읽는다). 비교: `PropertyListDelegate` 는 `SVNXMLParser.swift:156`, `173`–`174` 에서 base64 를 처리한다.
- 재현: 실제 재현함(XML 산출물 확인)
- 트리거: 제어문자가 든 사용자 정의 리비전 속성이 있는 커밋을 기록 화면에서 본다.
- 증상: 실제 출력은 `<property encoding="base64" name="myteam:bin">YQFi</property>` 다. 화면에는 `YQFi` 가 값으로 뜬다. 커밋 메시지(`<msg>`)는 svn 이 제어문자를 `?\001` 로 escape 해 넘기므로 base64 가 되지 않는다 — 메시지 표시는 영향 없다.
- 확률: 낮음. 이 팀이 사용자 정의 리비전 속성을 쓸 근거는 없다.
- 고치는 방법: `LogDelegate` 도 `encoding` 속성을 보고 base64 를 디코드한다. 두 델리게이트가 같은 일을 다르게 하고 있다.

### 같은 폴더에서 정규화 프로브가 동시에 돌면 서로의 탐사 파일을 지운다
- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNVolumeNormalizationProbe.swift:21` (락 밖에서 `probeUncached` 호출), `37`–`48` (접두사가 같은 파일을 모두 `unlinkat`)
- 재현: 코드 기준 추정
- 트리거: 같은 폴더를 가리키는 프로젝트를 둘 등록해 두고 앱을 다시 열어 두 프로브가 겹치게 만든다.
- 증상: 뒤에 시작한 프로브의 정리 루프가 앞선 프로브의 탐사 파일을 지운다. 앞선 프로브는 `readdir` 재순회에서 NFC·NFD 어느 이름도 찾지 못해 `nil` 을 반환한다. `nil` 은 캐시하지 않으므로 오류는 안 나지만, 그 프로젝트의 "이 볼륨은 한글 파일명을 NFD로 바꿉니다" 경고가 조용히 사라진다.
- 확률: 낮음. 같은 경로를 두 번 등록해야 한다.
- 고치는 방법: 경로별 직렬화(경로 단위 락) 또는 자기 프로세스·자기 호출이 만든 이름만 지우도록 접두사를 좁힌다.

### 탐사 파일이 작업 복사본 안에 만들어져 상태 목록에 잠깐 노출된다
- 심각도: 낮음
- 근거: `Sources/SVNCore/SVNVolumeNormalizationProbe.swift:54`–`60` (프로젝트 폴더 안에 `.svn-mac-normalization-probe-<UUID>-한글` 생성 후 `defer` 로 삭제)
- 재현: 코드 기준 추정
- 트리거: 프로젝트를 추가·선택하는 순간(`ProjectStore.probeFilenameNormalization`)에 상태 새로고침이 겹친다.
- 증상: 그 순간의 `svn status` 에 `? .svn-mac-normalization-probe-...` 가 미버전 항목으로 잡힌다. 앱이 강제 종료되면 파일이 남고(다음 프로브가 정리한다), 남아 있는 동안 목록에 보인다. 창은 수 밀리초다.
- 확률: 낮음.
- 고치는 방법: 탐사 파일을 작업 복사본 대신 같은 볼륨의 임시 디렉터리에서 만든다(볼륨 판정 목적은 동일하게 달성된다).

## 블록 경계

내 파일이 다른 파일과 맞닿는 지점에서 어긋날 수 있는 것들이다. 발견 항목은 위에 내 파일 기준으로 적었고, 여기에는 계약 자체의 문제를 적는다.

1. **`SVNXMLParser.ignoreRules` → `SVNClient.removeIgnoreRule`**: 파서가 내놓는 `SVNIgnoreRule.directory` 는 실제로 절대경로인데, `removeIgnoreRule` 은 그것을 `projectRelativePath` 로 받는다(`SVNClient.swift:984`–`1014` → `resolveWorkingCopyCommandPath:1285`–`1287`). 프로젝트가 작업 복사본 루트일 때만 우연히 성립하는 계약이다. 위 두 번째 발견의 3번 증상이 여기서 난다.

2. **`SVNXMLParser.statuses` → `TemporaryFilePolicy` → 커밋 인자 조립**: 파서가 산출물을 걸러 준다는 가정 위에 커밋 후보 계산이 서 있다(`TemporaryFileClassification.swift:71`–`84`). 파서가 한 종류(`.prej`)를 놓치면 그 아래 계층 어디에도 두 번째 방어선이 없다. `.prej` 는 `isRepositoryCleanupCandidate` 목록에도 없어 정리 제안으로도 잡히지 않는다.

3. **`GitIgnoreParser.parse` 는 `String` 만 받는다 → 인코딩 책임이 전부 호출부에 있다**: `ProjectStore+Ignore.swift:126` 이 `String(contentsOf:encoding:.utf8)` 로 읽는다. Windows 편집기가 CP949 로 저장한 `.gitignore` 는 여기서 던지고, 사용자에게는 Cocoa 원문("파일이 올바른 형식이 아니기 때문에 열 수 없습니다." 계열)만 뜬다. 어느 파일이 문제인지, 어떻게 하라는 안내가 없다. UTF-8 BOM 은 Foundation 이 제거하므로 문제 없음을 확인했다.

4. **`GitIgnoreImporter` 제안 목록 → `applySelectedGitIgnoreRules` 부분 실패**: 제안을 `for` 루프로 하나씩 `addIgnoreRule` 한다(`ProjectStore+Ignore.swift:186`–`195`). 중간에 하나가 던지면 앞의 것들은 이미 속성에 써졌는데 오류만 뜨고 무엇이 적용됐는지 알려주지 않는다. 루프 안에는 `selectedProjectID` 재확인도 없다(루프 뒤에만 있다). 되돌리는 수단도 없다. 모델 쪽에 부분 성공을 표현할 타입이 없다는 점이 원인이다 — `SVNDeletionResult`(`Models.swift:358`)처럼 성공/실패를 나눠 담는 결과 타입이 무시 규칙 적용에는 없다.

5. **`SVNStatusEntry.nodeKind` 는 경로에 따라 채워지거나 비어 있다**: `SVNClient.workingCopySnapshot` 만 `lstat` 으로 채우고(`SVNClient.swift:783`–`794`), `status(at:)`(`SVNClient.swift:681`)와 `ignoredStatus`(`:936`)는 `nil` 로 둔다. `nodeKind == .file` 을 요구하는 판정(`TemporaryFileClassification.swift:59`, `ChangesView.swift:457`)은 후자 경로의 항목에 대해 항상 거짓이 된다. 모델이 옵셔널이라 어느 쪽인지 타입으로 구분되지 않는다.

6. **`SVNFileSystem.isAtOrBelow` 는 심볼릭 링크를 풀지 않는다**: 백업 위치가 작업 복사본 밖인지 확인하는 안전 검사에 쓰이고(`ConflictFileService.swift:139`, `311`, `377`, `RevisionFileService.swift:129`, `190`), 거짓 음성이면 백업 없이 진행하거나 작업 복사본 안에 백업을 만든다. 현재 호출부는 모두 양쪽을 `resolvedURL` 로 풀고 넘기므로 성립한다 — 계약이 문서화되지 않은 채 호출부 규율에만 의존한다. 한글 NFC/NFD 차이는 문제되지 않음을 확인했다(Swift `String` 비교와 `Set` 해시가 정규 동등성 기준이라 NFC 키로 NFD 값을 찾는다). 대소문자만 다른 경로는 거짓 음성이 되지만 실제 호출부 조합에서 트리거를 찾지 못했다.

7. **`SVNHistoryTimeline` 은 `logs` 가 리비전 내림차순이라고 가정한다**(`SVNHistoryTimeline.swift:45`–`48`). 현재 두 호출 경로(`SVNClient.log`, `SVNClient` 의 경로별 로그)는 모두 내림차순이라 성립한다. 오름차순 목록을 넘기면 삽입 위치가 조용히 틀린다.

## 검증 공백

- **`.prej` 를 넣은 status 픽스처가 없다.** `SVNXMLParserTests.swift:258`(`parsesConflictArtifactsAndHidesTemporaryStatusEntries`)와 `:281`(`hidesCanonicallyEquivalentConflictArtifacts`)는 `.mine`, `.r41`, `.r42`, `.review` 만 넣는다. `<entry path="sample.txt.prej"><wc-status item="unversioned"/></entry>` 한 줄을 픽스처에 더했으면 첫 번째 발견이 잡혔다.
- **무시 규칙 픽스처가 실제 svn 출력 형태와 다르다.** `SVNXMLParserTests.swift:194`, `:212` 는 `<target path=".">`, `<target path="Documents">` 를 쓴다. 실제 svn 1.14.5 는 `<target path="/private/tmp/b4a/wc6">` 처럼 절대경로를 낸다. 임시 저장소를 만들어 `client.ignoreRules(at:)` 결과의 `directory` 를 검사하는 통합 테스트가 있었으면 두 번째 발견이 잡혔다. 현재 `addIgnoreRule`/`removeIgnoreRule` 통합 테스트(`SVNCanonicalAliasIntegrationTests.swift:94`, `187`)는 항상 `directory: "."` 를 직접 넘기므로 파서가 준 값을 되먹이는 경로를 밟지 않는다.
- **`GitIgnoreImporter` 테스트에 한글 패턴이 없다.** `GitIgnoreImporterTests.swift` 전체가 ASCII(`*.log`, `build/`, `nested/cache/`)다. NFD 로 존재하는 디렉터리와 NFC 로 적힌 `.gitignore` 를 함께 넣고 제안 패턴의 바이트를 검사하면 세 번째 발견이 잡혔다.
- **`isDirectoryOnly` 를 소비하는 테스트가 없다.** `GitIgnoreParserTests.swift:19`, `24` 가 플래그가 세워지는지만 본다. 임포터 출력이 `build/` 와 `build` 를 구분하는지 확인하는 단정이 없어 무시 상태로 남았다.
- **`managedDirectories` 에 추가 예정 폴더가 들어가는 입력이 없다.** `GitIgnoreImporterTests` 는 `managedDirectories` 를 직접 만들어 넘긴다. `ProjectStore` 가 `isVersioned` 로 그 집합을 만드는 구간(네 번째 발견)은 어느 테스트도 `item="added" revision="-1"` 항목으로 밟지 않는다.
- **`LogDelegate` 에 base64 리비전 속성 입력이 없다.** `parsesStandardRevisionPropertiesAndDateWithoutFractionalSeconds`(`:459`)는 평문 속성만 쓴다. `PropertyListDelegate` 쪽 base64 처리도 잘못된 base64 로 `abortParsing` 을 태우는 테스트가 없다(그 경로는 목록 전체를 `malformedResponse` 로 버린다).
- **`SVNHistoryTimeline` 의 비수치 리비전 입력이 없다.** `placesWorkingCopyRevisionInHistoryTimeline`(`:477`)은 숫자 문자열만 쓴다. 비수치 값이 오면 `insertionIndex == nil` 이 되어 `isBeforeLoadedHistory` 가 참이 되는데(`SVNHistoryTimeline.swift:49`–`52`), 이게 의도인지 확인하는 단정이 없다.
- **`SVNFileSystem` 에 실패 경로 테스트가 없다.** `SVNFileSystemTests.swift` 는 정상 덮어쓰기·비교·경계만 본다. `overwriteFile` 은 대상을 먼저 `truncate(atOffset: 0)` 하므로 중간에 쓰기가 실패하면 대상이 잘린 채 남는다(`SVNFileSystem.swift:20`–`24`). 원본과 대상이 같은 URL 인 호출도 막지 않는다. 현재 호출부는 둘 다 위반하지 않지만 계약을 고정한 테스트가 없다.
- **프로브 동시 실행 테스트가 없다.** `SVNVolumeNormalizationProbeTests.swift` 는 캐시·정리·HFS+ 판정을 단일 스레드로만 본다. 같은 경로에 두 프로브를 동시에 돌리는 입력이 아홉 번째 발견을 잡는다.
- **`SVNApplicationSupport` 이관 실패 이후를 보는 테스트가 없다.** `existingCurrentApplicationSupportDirectoryWinsOverLegacy` 는 legacy 가 남아 있음만 단정한다. legacy 안의 데이터가 이후 어떤 경로로도 읽히지 않는다는 사실(사용자 관점에서는 과거 백업 유실)을 다루는 단정이 없다.

기존 테스트 실행: `swift test --filter "ConflictArtifact|GitIgnore|normalizationProbe|shared|migrat"` → 20개 통과(실패 0). 새 테스트는 추가하지 않았다.

## 확인하지 않은 것

- `RepositoryListDelegate`(`SVNXMLParser.swift:243`–`257`)는 `<size>` 가 정수가 아니거나 `<commit>` 이 없으면 `abortParsing` 으로 목록 전체를 `malformedResponse` 로 버린다. 실제 svn 이 그런 출력을 내는 조건을 찾지 못해 발견으로 올리지 않았다.
- `StatusLocksDelegate` 는 서버 측 `repos-status/lock` 만 읽고 로컬 `wc-status/lock`(내가 이 작업 복사본에서 쥔 잠금)은 읽지 않는다. `2026-08-25-dead-end-audit-claude.md:518` 이 이미 보고한 항목이라 다시 세지 않았다.
- `workingCopyRevision(from:)` 이 버전관리 항목 없는 응답에서 `malformedResponse` 를 던지는 문제는 `2026-08-25-dead-end-audit-claude.md:226` 에 이미 있다.
- 앱을 실제로 빌드해 화면에서 확인하지 않았다. 무시 규칙 목록의 절대경로 표시, `.prej` 항목의 체크박스 상태, 트리 충돌 화면의 문구는 코드 경로 추적으로 판단했다. svn 쪽 동작(산출물 이름, propget XML 경로, 무시 패턴 바이트 매칭, 추가 예정 폴더 propset, `.prej` 커밋 성공)은 임시 저장소에서 실제로 실행해 확인했다.
- CP949 로 저장된 `.gitignore` 의 읽기 실패는 Foundation 수준에서 확인했지만(`The file couldn't be opened because it isn't in the correct format.`), 앱이 그 오류를 한국어로 어떻게 보여주는지는 확인하지 않았다.
- `svn:global-ignores` 를 하위 디렉터리에 설정하는 임포터 동작(`GitIgnoreImporterTests` 가 기대하는 `directory: "lib", kind: .global`)이 팀 의도에 맞는지는 판단하지 않았다. svn 의미상으로는 성립한다.
