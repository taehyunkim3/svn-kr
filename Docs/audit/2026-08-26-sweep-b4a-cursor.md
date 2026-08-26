# B4a 전수 감사

배정 9파일, 1769줄. 소스 수정 없음. 기존 테스트 54개 통과 (`GitIgnore` / `SVNFileSystem` / `SVNApplicationSupport` / `SVNVolumeNormalization` / `SVNXMLParser` / 관련 필터).

재현 환경: svn 1.14, 임시 `file://` `/tmp/svnmac-b4a-repro`, APFS. 파서는 그 XML을 `SVNXMLParser.workingCopySnapshot` / `statuses`에 직접 넣었다.

## 읽은 파일
- `Sources/SVNCore/GitIgnoreImporter.swift` — 127줄 — gitignore 규칙을 svn:ignore / svn:global-ignores 제안으로 변환
- `Sources/SVNCore/GitIgnoreParser.swift` — 108줄 — `.gitignore` 한 파일을 규칙 목록으로 파싱
- `Sources/SVNCore/Models.swift` — 550줄 — 상태·충돌·로그·오류 등 SVNCore 공개 모델
- `Sources/SVNCore/SVNAdditionalModels.swift` — 70줄 — 인자 오류, 인증서 실패, 속성, 저장소 목록 항목
- `Sources/SVNCore/SVNApplicationSupport.swift` — 37줄 — Application Support `SVN KR` 경로와 `SVN Mac` 이전
- `Sources/SVNCore/SVNFileSystem.swift` — 49줄 — 경로 포함 여부, 파일 덮어쓰기, 내용 비교
- `Sources/SVNCore/SVNHistoryTimeline.swift` — 54줄 — 기록 목록에 로컬 기준 리비전 위치 계산
- `Sources/SVNCore/SVNVolumeNormalizationProbe.swift` — 82줄 — 볼륨이 NFC 파일명 바이트를 보존하는지 실제 파일로 확인
- `Sources/SVNCore/SVNXMLParser.swift` — 692줄 — svn XML 응답을 모델로 파싱

경계 확인용으로 `SVNWorkingCopySnapshot.swift`, `SVNClient.swift`(해당 호출), `ProjectStore+Ignore.swift`, `ChangesView.swift`, `TemporaryFileClassification.swift`, `WorkingCopyFileService.swift`, `ConflictFileService.swift`도 읽었다. 발견은 배정 파일 기준으로만 적는다.

## 발견
### 충돌 부산물(.mine / .rN / .prej)이 변경 목록에 미버전으로 남고 커밋 대상이 된다
- 심각도: 중간
- 근거: `Sources/SVNCore/SVNXMLParser.swift:20-48` (`statuses()`만 `.mine`·`.r[0-9]+`를 숨김, `.prej`는 여기도 안 숨김), `Sources/SVNCore/SVNXMLParser.swift:61-62` (새로고침은 `workingCopySnapshot` → `workingCopyEntries`, 숨김 없음), `Sources/SVNCore/Models.swift:350-355` (미버전은 `isSelectableForCommit`), `Sources/SVNMac/ProjectStore.swift:1212` (`statuses = snapshot.statuses`), `Sources/SVNMac/CommitControlsView.swift:18-19` (전체 선택이 `automaticallySelectedEntries`)
- 재현: 실제 재현함
- 트리거: 작업 폴더에서 업데이트 충돌이 난 뒤 변경 탭을 연다. 내용 충돌이면 `sample.txt.mine` / `.r1` / `.r2`가, 속성 충돌이면 `sample.txt.prej`가 미버전 행으로 보인다. 「전체 선택」을 누르거나 그 행만 체크한 뒤 커밋한다. 충돌 원본 파일은 `item==conflicted` 또는 `propertyState==conflicted`라 선택이 막히지만, 부산물은 막히지 않는다.
- 증상: 변경 목록에 충돌 임시파일이 새 파일처럼 보인다. 속성 충돌 XML 원문 `<entry path="sample.txt.prej"><wc-status item="unversioned"/>`. 파서 결과 `statuses()`는 내용 충돌 부산물만 거르고 (`["sample.txt:conflicted"]`), 스냅샷은 `["sample.txt:conflicted", "sample.txt.mine:unversioned", "sample.txt.r1:unversioned", "sample.txt.r2:unversioned"]`. `.prej`는 두 경로 모두 남는다. 커밋하면 저장소에 충돌 덤프가 추가된다. 파일 탐색기도 `workingCopyEntries`를 쓰므로 같은 파일이 미버전으로 보인다.
- 확률: 중간. 잠금을 쓰는 팀도 속성 충돌(`svn:needs-lock` 등)과 잠금 없이 연 xlsx/hwp 내용 충돌은 난다. 충돌을 해결하기 전에 다른 파일을 커밋하려고 전체 선택을 누르기 쉽다.
- 고치는 방법: 스냅샷 가시 목록과 `statuses()`가 같은 규칙으로 `.mine` / `.rN` / `.working` / `.prej`를 거르고, 선택·탐색기 매칭도 그 목록을 쓴다.

### incomplete 항목이 커밋 선택 대상이다
- 심각도: 낮음
- 근거: `Sources/SVNCore/Models.swift:350-355` (`isSelectableForCommit`이 `.incomplete`를 제외하지 않음), `Sources/SVNMac/ChangesView.swift:115-118` (이 플래그로 체크박스를 그림), `Sources/SVNMac/StatusBadge.swift:23-28` (되돌리기는 막았고 업데이트 안내는 있음)
- 재현: 실제 재현함 (`SVNStatusEntry(path: "partial", item: .incomplete, revision: "2").isSelectableForCommit == true`). 그 경로로 `svn commit`이 성공하는지는 이 세션에서 실행하지 않음
- 트리거: 큰 저장소 체크아웃·업데이트가 끊긴 뒤 변경 목록에서 전체 선택하고 커밋한다.
- 증상: 「업데이트 미완료」 배지와 「업데이트로 이어받으세요」 안내 옆에 커밋 체크박스가 있다. 전체 선택에 포함된다. 사용자는 안내와 반대로 커밋을 시도한다.
- 확률: 낮음. incomplete 자체는 드물다. 한 번 생기면 전체 선택은 자연스럽다.
- 고치는 방법: `isSelectableForCommit`에서 `.incomplete`·`.obstructed`를 빼고, 전체 선택도 그 정의를 따른다.

### `isVersioned`가 예약 추가를 저장소 미관리로 취급한다
- 심각도: 낮음
- 근거: `Sources/SVNCore/Models.swift:384-389` (`revision >= 0` 필수), `Tests/SVNCoreTests/SVNXMLParserTests.swift:111-122` (added/`-1`을 `isVersioned == false`로 고정), `Sources/SVNMac/ProjectStore+Ignore.swift:109-144` (gitignore 비교가 `entries.filter(\.isVersioned)`만 사용), `Sources/SVNMac/ProjectStore+RepositoryMaintenance.swift:230-232` (이름·복사만 `added`/`replaced`를 따로 보정)
- 재현: 실제 재현함 (모델: `SVNWorkingCopyEntry(path: "new.xlsx", status: "added", revision: "-1").isVersioned == false`)
- 트리거: 커밋이 add 뒤에 실패해 xlsx/hwp가 `added`로 남은 상태에서 「gitignore 비교」를 연다. 또는 파일 탐색기에서 그 문서를 연다.
- 증상: `*.xlsx` 가져오기 미리보기에 「이미 추적 중」 경고가 없다. 무시 규칙을 적용해도 예약 추가는 커밋된다. 탐색기는 `svnEntry?.isVersioned == false`라 잠금 확인을 건너뛴다. 이름 변경 UI는 같은 모델을 `added`로 보정하므로 화면마다 버전이 다르다.
- 확률: 낮음. 평소 커밋은 add와 한 번에 끝나지만, 커밋 실패 뒤 gitignore를 가져오는 순서는 가능하다.
- 고치는 방법: `isVersioned`를 「svn이 스케줄한 항목」으로 맞추거나, gitignore `trackedPaths`와 탐색기 잠금이 `added`/`replaced`를 포함하게 호출부를 통일한다.

## 블록 경계
- 변경 목록 새로고침은 `SVNClient.workingCopySnapshot` → `SVNWorkingCopySnapshot.visibleStatuses`다. `SVNXMLParser.statuses()`의 충돌 부산물 필터는 `client.status` / 무시 목록에만 쓰인다. 같은 XML을 두 경로가 다르게 해석한다.
- `SVNWorkingCopySnapshot.visibleStatuses`는 canonical 키가 다른 미버전(`.mine`, `.prej`)을 남긴다. NFC 별칭 미버전만 접는다.
- `ProjectStore.containsSelectedConflict`는 `item == .conflicted`만 본다. 속성 충돌 파일은 이미 `isSelectableForCommit == false`라 막히지만, `.prej` 단독 커밋은 통과한다.
- `SVNFileSystem.isAtOrBelow`는 URL `pathComponents` 비교다. 충돌 백업·리비전 복원이 작업 복사본 밖 판정에 쓴다. APFS에서 `URL(fileURLWithPath:)`가 NFD로 맞춰 이 환경에선 NFC/NFD 혼용이 true였다. `SVNWorkingCopySnapshot` / `TreeConflictRestoreScan` / `SVNRepositoryPathNormalization`에 문자열용 구현이 또 있다. 정규화 규칙이 갈라지면 백업 위치 검사와 트리 충돌 영향 범위가 달라진다.
- `SVNWorkingCopyEntry.repositoryPath`는 파서가 채우지 않는다. `WorkingCopyFileService`의 저장소 경로 매칭은 항상 WC `path`로 떨어진다.
- `ConflictInfoDelegate`는 `<prop-file>`을 읽지 않는다. 속성 충돌 UI는 디스크에서 `.prej`를 찾는다(`PropertyConflictResolution.swift`). 표준 위치면 동작하고, XML 경로와 디스크가 다르면 속성 이름이 빈다.
- `GitIgnoreImporter.matches`는 `*.확장자`와 정확 이름만 본다. `ProjectStore+Ignore`가 넘기는 `trackedPaths`는 `isVersioned` 필터 뒤에 온다.
- `SVNClientArgumentError.errorDescription`은 영어다. `ProjectStore.localizedError`는 `SVNError`만 한국어로 바꾸고 나머지는 `localizedDescription`이다. 빈 대상·NUL 메시지가 UI에 새면 영어 원문이 그대로 뜬다.
- `SVNVolumeNormalizationProbe`는 작업 폴더에 `.svn-mac-normalization-probe-…-한글`을 만들었다가 지운다. `ProjectStore.probeFilenameNormalization`이 프로젝트 등록 시 호출한다. 짧은 구간 동안 `svn status`와 겹치면 미버전으로 보일 수 있다.
- `SVNApplicationSupport.migrateRoot`는 `SVN KR`이 없을 때만 `SVN Mac`을 옮긴다. 둘 다 있으면 레거시를 그대로 둔다. 인증·설정이 나뉜 채 남을 수 있다.

## 검증 공백
- `SVNXMLParserTests.parsesConflictArtifactsAndHidesTemporaryStatusEntries`는 `statuses()`만 본다. 같은 XML을 `workingCopySnapshot`에 넣으면 `.mine`/`.rN`이 남는다. `sample.txt.prej` 케이스는 두 API 모두 없다.
- `isSelectableForCommit` 테스트는 missing / 속성 충돌 / switched만 있다. incomplete·obstructed·unversioned 부산물이 전체 선택에 들어가는지 없다.
- `GitIgnoreImporterTests`는 `*.log`, 부정, `**`, 관리 밖 디렉터리만 본다. `added` 추적 경로, NFD 파일명(Swift `==`라 통과할 가능성 큼), `*~` / `[abc]` / 디렉터리 전용(`isDirectoryOnly`) 변환은 없다.
- `GitIgnoreParser`는 BOM, UTF-16, 마지막 줄 CR만 있는 입력, 빈 `sourceDirectory`를 안 본다.
- `SVNFileSystemTests`는 성공한 덮어쓰기와 용량 비교만 있다. `truncate` 이후 `write` 실패, 대상 없음, 디렉터리/심볼릭 링크 입력은 없다.
- `workingCopyRevision`은 버전 항목이 없으면 `malformedResponse`다. 빈 저장소 체크아웃·incomplete만 있는 WC 실측이 없다.
- `remoteChanges`는 `repos-status item="none" props="modified"`를 `item=modified`, `propertyState=none`으로 만든다. 업데이트 미리보기는 이 배열을 커밋 겹침·빈 여부만 쓰므로 화면 라벨 테스트가 없다.
- `LogDelegate`는 `foundCDATA`가 없다. 실제 `svn log --xml` CDATA 여부는 이 세션에서 확인하지 않았다.
- `SVNHistoryTimeline` 테스트는 최신순 로그를 전제한다. 호출부가 순서를 뒤집으면 삽입 위치가 틀어지는데 그 계약 테스트는 파서 쪽에 없다.
- `IgnoreRulesDelegate`는 속성 값의 공백-only 줄, 속성 이름 오타(ignore 외 속성)를 안 본다.
- `repositoryEntries`는 `kind`가 file/dir가 아니면 목록 전체를 `abortParsing`한다. 미래 kind 회귀가 없다.

## 확인하지 않은 것
- incomplete 작업 복사본에서 실제 `svn commit` 성공/실패 원문
- `overwriteFile`이 truncate 이후 복사 도중 프로세스가 죽은 경우의 디스크 상태. 예외로 source open이 먼저 실패하면 대상은 그대로였다(100바이트 유지). `SVNClient.materializeCanonicalFileReplacements`의 catch 복구는 예외 경로만 커버한다
- HFS+에서 `SVNFileSystem.isAtOrBelow` NFC/NFD. 프로브는 HFS+ 이미지에서 NFC 비보존만 확인했다
- `svn list --xml`에 file/dir 이외 kind가 나오는 SVN 버전
- 레거시 `SVN Mac`과 `SVN KR`이 동시에 있는 실사용자 머신
- 프로브 임시파일이 커밋된 사례
- 이미 고친 항목: incomplete 상태 매핑, 다중 `<conflict>` 보존, switched 파싱, `--force-log` / 빈 커밋 거부
