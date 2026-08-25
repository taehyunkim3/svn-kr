# 감사 A: 데이터 손실 위험 — 파괴적 동작의 안전성

- 일자: 2026-08-25
- 대상 브랜치: `audit-destructive` (HEAD `4f4ce81`)
- 범위: 사용자 파일을 지우거나 덮어쓰는 동작만. `svn` 명령 인자 구성(이스케이프, peg revision, `--force-log`, 인코딩)은 별도 감사 축이므로 제외.
- 방법: 코드 추적 + 임시 `file://` 저장소에서 `svn` CLI 재현. 소스 수정·커밋 없음.
- 기준 선례: `ConflictFileService.preserveWorkingFile`(`Sources/SVNMac/ConflictFileService.swift:181`) — 스테이징 복사 → 바이트 동일성 검증 → `moveItem` 원자 확정. 아래 발견은 이 수준과의 차이를 기준으로 판정했다.

발견 7건(높음 2, 중간 4, 낮음 1).

---

## 1. 텍스트·속성 동시 충돌이 "속성 충돌"로 분류돼, 백업 없이 작업 파일 내용이 서버 버전으로 덮어써진다

- 심각도: 높음
- 근거:
  - `Sources/SVNCore/SVNXMLParser.swift:294`–`303` (각 `<conflict>` 시작에서 `type` 재대입)
  - `Sources/SVNCore/SVNXMLParser.swift:323`–`338` (`details`를 `<conflict>` 닫힘마다 덮어씀 → 마지막 항목이 승리)
  - `Sources/SVNMac/ProjectStore+Conflicts.swift:31`–`77` (`details.type`으로 세 화면 분기)
  - `Sources/SVNMac/ProjectStore+Conflicts.swift:84`–`132` (`resolveActivePropertyConflict` — 작업 파일 백업 호출이 전혀 없음)
  - `Sources/SVNMac/ProjectStore+Conflicts.swift:240`–`244` (텍스트 경로만 `prepareWorkingFileForResolve`로 백업)
  - `Sources/SVNMac/PropertyConflictResolutionView.swift:76`–`80`, `151`–`158` (경고문이 속성 얘기만 한다)
  - `Sources/SVNMac/PropertyConflictResolution.swift:48`–`56` (검증이 `propertyState`만 본다 → 내용이 날아간 것을 못 잡는다)
- 재현: **실제 재현함** (텍스트 파일과 바이너리 xlsx 양쪽)

### 재현 절차와 실측

임시 `file://` 저장소에서 한 파일에 내용 충돌과 속성 충돌을 동시에 만들었다.

```
$ svn up --accept postpone
CC   예산.xlsx
Summary of conflicts:
  Text conflicts: 1
  Property conflicts: 1

$ svn info --xml 예산.xlsx | grep 'type="'
   type="text">
   type="property">
   type="text">
   type="property">
```

`svn info --xml`은 충돌을 여러 `<conflict>` 요소로 내보내고, `ConflictInfoDelegate`는 매 요소가 닫힐 때 `details`를 통째로 덮어쓴다. 따라서 앱이 보는 최종 `type`은 **항상 마지막 요소인 `property`** 다. `prepareConflictResolution`은 이걸 속성 충돌로 분류해 `PropertyConflictResolutionView`를 띄운다.

이 화면에서 "서버 속성 적용"을 누르면 `svn resolve --accept theirs-full`이 실행된다. 실측 결과:

```
$ cat 예산.xlsx        # 해결 전
PKMY_PRECIOUS_WORK
$ ls -1
예산.xlsx  예산.xlsx.prej  예산.xlsx.r1  예산.xlsx.r2

$ svn resolve --accept theirs-full 예산.xlsx
Merge conflicts in '예산.xlsx' marked as resolved.
Resolved conflicted state of '예산.xlsx'

$ cat 예산.xlsx        # 해결 후
PKSERVER_VERSION
$ ls -1
예산.xlsx
```

`theirs-full`은 속성 충돌만 해결하지 않는다. 같은 경로의 내용 충돌까지 해결하면서 작업 파일을 서버 버전으로 교체하고 `.r1`/`.r2`/`.prej` 보조 파일도 지운다. 앱은 이 경로에서 작업 파일 복구본을 만들지 않으므로 사용자의 편집분은 어디에도 남지 않는다.

- 트리거:
  1. A와 B가 같은 xlsx를 각자 편집한다.
  2. 같은 파일에 서로 다른 속성 변경이 함께 들어간다. 이 팀 워크플로에서 가장 흔한 경로는 두 사람이 같은 파일에 `svn:needs-lock`을 서로 다르게 설정한 뒤 커밋하는 것이다(앱에 `svn:needs-lock` 관리 기능이 이번 배치에 함께 들어왔다).
  3. B가 커밋하고, A가 업데이트한다 → 내용 충돌 + 속성 충돌.
  4. A가 충돌 파일을 열면 "속성 충돌" 화면이 뜬다.
  5. A가 "서버 속성 적용"을 누른다.
- 증상: 화면은 속성만 바꾼다고 말했는데(`"내 로컬 속성 값이 사라집니다."`) 작업 중이던 xlsx 내용이 서버 버전으로 바뀐다. 완료 알림은 `"속성 충돌을 해결했습니다. 커밋 전에 속성을 확인하세요."` 로, 내용이 교체됐다는 언급이 없다. 백업 폴더도 만들어지지 않아 앱 안에서 되돌릴 방법이 없다.
- 확률: 높음. 속성 충돌은 드물지만 이 팀은 `svn:needs-lock`을 공유 문서에 걸어 쓰고, 그 속성 관리 UI가 방금 추가됐다. 속성 충돌이 나는 상황은 거의 항상 같은 파일을 두 사람이 편집한 상황이라 내용 충돌이 동반된다.
- 고치는 방법: `ConflictInfoDelegate`가 충돌을 목록으로 모으고(첫 항목 우선 또는 `tree > text > property` 우선순위), 속성 충돌 해결 경로에도 `prepareWorkingFileForResolve`와 동일한 작업 파일 보존을 넣는다.

---

## 2. 트리 충돌 "서버 버전으로 파일 복구"가 하위 트리 전체를 백업 없이 지운다 (미버전 파일 포함)

- 심각도: 높음
- 근거:
  - `Sources/SVNMac/ProjectStore+Conflicts.swift:160`–`173` (`revert` → `update`, 백업 호출 없음)
  - `Sources/SVNCore/SVNClient.swift:1621`–`1628` (`revert --depth infinity`)
  - `Sources/SVNMac/TreeConflictResolutionView.swift:148`–`155` (경고문이 개수·경로 없이 한 줄)
- 재현: **실제 재현함**

### 재현 절차와 실측

서버가 디렉터리를 삭제했고, 로컬에는 그 디렉터리 안에 미커밋 편집과 한 번도 커밋되지 않은 새 파일이 있는 상태를 만들었다.

```
$ svn status
A  +  C 2026예산            (local dir edit, incoming dir delete upon update)
M  +    문서/계획.txt
?       문서/신규계약서.xlsx

$ svn revert --depth infinity 문서
Reverted '문서'
Reverted '문서/계획.txt'

$ ls -1 문서
ls: 문서: No such file or directory
```

`revert --depth infinity`가 충돌 디렉터리를 통째로 제거한다. 미커밋 편집(`문서/계획.txt`)뿐 아니라 **저장소에 존재조차 없는 `문서/신규계약서.xlsx`도 함께 사라진다.** 이 파일은 저장소 이력에도 없고 앱이 만든 복구본도 없으므로 영구 손실이다. `find`로 `.mine`/`.r*`/백업 흔적을 찾아도 없다.

- 트리거:
  1. 서버에서 누군가 폴더를 삭제(또는 이름변경)하고 커밋한다.
  2. 로컬에서는 같은 폴더 안 문서를 편집 중이거나 새 문서를 만들어 뒀다(아직 add/commit 안 함).
  3. 업데이트 → 트리 충돌.
  4. 충돌 해결 화면에서 "서버 버전으로 파일 복구" → 확인 대화상자에서 실행.
- 증상: 폴더가 Finder에서 그대로 사라진다. 확인 대화상자는 `"커밋하지 않은 로컬 변경이 사라집니다."` 한 줄만 보여줬고, 하위에 파일이 몇 개인지, 저장소에 없는 파일이 섞여 있는지는 말하지 않았다. 오류도 나지 않는다.
- 확률: 중간. 폴더 정리·이름변경은 사무직 팀에서 흔하고, 트리 충돌 해결 UI가 이번 배치에 새로 들어왔다. 트리 충돌 자체는 텍스트 충돌보다 드물지만, 발생하면 손실 단위가 파일 1개가 아니라 폴더 하나다.
- 고치는 방법: 실행 전에 대상 하위 트리의 수정·미버전 항목을 스캔해 개수와 경로를 확인창에 나열하고, 텍스트 충돌과 같은 수준으로 하위 트리를 백업 폴더에 복사한 뒤(바이트 검증 포함) `revert`를 실행한다.

---

## 3. 커밋 확인창이 열린 뒤 상태가 갱신되면, 확인창에 없던 파일이 서버에서 삭제된다

- 심각도: 중간
- 근거:
  - `Sources/SVNMac/CommitConfirmationView.swift:11`–`28` (요청 생성 시점의 `statuses`로 `serverDeletionEntries` 고정)
  - `Sources/SVNMac/CommitConfirmationView.swift:144`–`146` (화면은 고정된 스냅샷만 읽는다)
  - `Sources/SVNMac/ProjectStore+Deletion.swift:72`–`83` (`confirmCommit`은 스냅샷 검증 없이 `commitSelectedChanges` 호출)
  - `Sources/SVNMac/ProjectStore+Deletion.swift:121`–`131` (`missingPaths`를 **현재** `statuses`에서 다시 계산해 삭제 예약)
  - `Sources/SVNMac/ProjectStore+FileBrowser.swift:4`–`17` (`refreshForMainWindowActivation`이 모달 여부를 보지 않고 `statuses` 갱신)
- 재현: **코드 기준 추정**
- 트리거:
  1. 변경 목록에서 파일 여러 개를 선택하고 커밋을 누른다. Finder에서 지운 파일이 하나라도 있어 확인창이 뜬다(확인창 표시 조건은 `ProjectStore+Deletion.swift:57`).
  2. 확인창의 안내(`"삭제하는 파일이 있습니다. 정말 삭제하는게 맞는지 아래 목록에서 확인해주세요."`)를 따라 Finder로 전환해 확인한다.
  3. 그 김에 선택돼 있던 다른 파일 몇 개를 Finder에서 지우거나 다른 폴더로 옮긴다.
  4. 앱으로 돌아온다 → 창 활성화 리프레시가 `statuses`를 갱신하고 그 파일들이 `missing`이 된다. 확인창의 목록은 갱신되지 않는다.
  5. "커밋 확인"을 누른다.
- 증상: 확인창이 "서버에서 삭제될 항목 1개"라고 보여줬는데 실제로는 4개가 삭제된다. 사용자에게는 삭제 예약과 커밋이 한 번에 성공한 것으로 보인다.
- 확률: 중간. 확인창 문구가 사용자를 Finder로 보내고, 앱으로 돌아오는 행위 자체가 리프레시를 트리거한다는 점이 결합해서 확률을 올린다.
- 고치는 방법: `confirmCommit`에서 현재 `statuses` 기준 삭제 대상을 다시 계산해 확인된 집합과 비교하고, 늘어났으면 커밋을 중단하고 갱신된 목록으로 확인창을 다시 띄운다.

---

## 4. 리비전 복원·충돌 해결의 복구본이 숨김 파일로만 남고 앱이 위치를 알려주지 않는다

- 심각도: 중간
- 근거:
  - `Sources/SVNMac/ProjectStore+History.swift:203`–`209` (`RevisionRestoreResult`를 `_ =`로 버린다)
  - `Sources/SVNMac/ProjectStore+History.swift:213`–`217` (완료 알림에 복구본 언급 없음)
  - `Sources/SVNMac/RevisionFileService.swift:148`–`161` (복구본 이름이 `.<파일명>-before-r<N>.<확장자>` — 선행 점)
  - `Sources/SVNMac/ConflictFileService.swift:186`–`201` (`.working-file-recovery-<UUID>` — 선행 점, 확장자 없음)
  - `Sources/SVNMac/ProjectStore+Conflicts.swift:240`–`244` (복구본 URL을 `_ =`로 버린다), `:264`–`267` (해결 직후 `activeConflictSession = nil`)
  - `Sources/SVNMac/ProjectStore+Conflicts.swift:213`–`216` (`openConflictBackupFolder`는 세션이 살아 있을 때만 동작)
  - 저장소 전체 검색 결과 `Revision Restore Backups` / `Conflict Backups` 디렉터리를 여는 UI는 위 한 곳뿐이다.
- 재현: **코드 기준 추정** (경로·파일명 규칙은 코드에서 확정, 실제 Finder 표시는 확인 안 함)
- 트리거:
  1. 이력 화면에서 과거 리비전을 골라 "이 버전으로 되돌리기"를 실행한다. 또는 텍스트 충돌에서 "서버 버전 적용"을 실행한다.
  2. 되돌린 결과가 잘못됐다는 걸 깨닫고 직전 파일을 되찾으려 한다.
- 증상: 복구본은 실제로 `~/Library/Application Support/…/Revision Restore Backups/<프로젝트UUID>/<세션UUID>/.보고서-before-r17.xlsx` 형태로 존재하지만, 완료 알림은 `"%1$@ 파일을 r%2$@로 되돌렸습니다. 현재 로컬 수정 상태입니다. 서버에 반영하려면 커밋하세요."` 뿐이다. 경로도, 여는 버튼도 없다. 파일명이 점으로 시작하므로 Finder 기본 설정에서는 폴더를 열어도 보이지 않는다. 충돌 해결 쪽은 세션이 끝나면 "백업 폴더 열기" 버튼 자체가 사라진다. 터미널을 쓰지 않는 사용자에게는 복구본이 없는 것과 같다.
- 확률: 중간. 되돌리기를 쓰는 사람은 정의상 무언가를 잘못했다고 판단한 사람이고, 되돌린 결과가 또 틀리는 경우는 드물지 않다.
- 고치는 방법: 복구본 URL을 알림에 담고(경로 표시 + "복구본 폴더 열기" 버튼), 파일명에서 선행 점을 빼서 Finder에서 보이게 한다.

---

## 5. 잠금 일괄 해제가 `svn:needs-lock` 작업 파일을 즉시 읽기전용으로 만든다 — 확인창은 개수만 보여준다

- 심각도: 중간
- 근거:
  - `Sources/SVNMac/ProjectStore+Locking.swift:51`–`55` (`requestBulkUnlock` — 로컬 수정 여부 검사 없음)
  - `Sources/SVNMac/ProjectStore+Locking.swift:57`–`95` (`confirmBulkUnlock`)
  - `Sources/SVNMac/LockWorkflow.swift:122`–`125` (`ownedLocks` — 소유자 일치만 본다)
  - `Sources/SVNMac/RepositoryLocksView.swift:102`–`118` (확인창에 개수만, 경로 목록 없음)
- 재현: **실제 재현함** (읽기전용 전환 부분)

```
$ ls -l 예산.xlsx | awk '{print $1}'   # needs-lock, 잠금 없음
-r--r--r--@
$ svn lock -q 예산.xlsx; ls -l 예산.xlsx | awk '{print $1}'
-rw-r--r--@
$ svn unlock -q 예산.xlsx; ls -l 예산.xlsx | awk '{print $1}'
-r--r--r--@
```

- 트리거:
  1. 사용자가 xlsx/hwp 여러 개를 잠그고 편집 중이다(Excel·한글에서 열어 둔 상태).
  2. 잠금 화면에서 "잠금 N개 해제"를 누른다.
  3. 확인창은 `"현재 사용자가 소유한 잠금 %1$@개를 해제합니다. 다른 사용자가 이 파일들을 수정할 수 있게 됩니다."` — 어떤 파일인지 나열하지 않고, 파일이 읽기전용으로 바뀐다는 말도, 미커밋 변경이 있다는 경고도 없다.
- 증상: 열어 둔 문서가 읽기전용으로 바뀌어 Excel·한글에서 저장이 실패한다. 앱 안에서 다시 잠그면 쓰기 권한이 돌아오지만, 그 사이 응용프로그램이 저장에 실패한 방식(임시파일만 남기고 종료 등)에 따라 편집 중이던 내용이 날아갈 수 있다. 로컬에 미커밋 변경이 남은 상태로 잠금이 풀리면 다른 사람이 같은 파일을 잠그고 먼저 커밋해 충돌 상황을 만든다.
- 확률: 중간. 이 팀의 기본 워크플로가 "잠그고 편집"이므로 잠금 일괄 해제는 정리 목적으로 자주 쓰일 동작이다. 다만 편집 중 문서가 열려 있어야 손실로 이어진다.
- 고치는 방법: 확인창에 해제 대상 경로를 나열하고, 로컬 수정(`modified`) 상태인 항목을 별도로 표시해 기본 선택에서 빼고, 읽기전용 전환 사실을 문구에 넣는다.

---

## 6. Finder 삭제 항목이 일반 체크박스가 되어 전체 선택에 포함되고, 행에 있던 "로컬 파일 복원" 안내가 죽었다

- 심각도: 중간
- 근거:
  - `Sources/SVNMac/ChangesView.swift:114` (`isSelectableForCommit || canScheduleRepositoryDeletion` → 체크박스)
  - `Sources/SVNMac/ChangesView.swift:125`–`140` (`else if entry.canScheduleRepositoryDeletion` — 위 조건이 이미 잡으므로 **도달 불가능한 죽은 분기**. "로컬 파일 복원 / 저장소에서 삭제" 선택 메뉴가 행에서 사라졌다)
  - `Sources/SVNMac/TemporaryFileClassification.swift:79`–`84` (`automaticallySelectedEntries`가 `missing`을 포함)
  - `Sources/SVNMac/ProjectStore.swift:652`–`654` ("전체 선택"이 위 함수를 그대로 쓴다)
  - 커밋 `bc9b6bf` "feat: Finder 삭제를 전체 선택에 포함"에서 `ChangesView.swift:114`의 조건 한 줄만 바뀌면서 125행 분기가 죽었다
- 재현: **실제 재현함** (상태 수량 부분)

```
$ mv 2026예산 2026예산_최종     # Finder에서 폴더 이름변경
$ svn status
!       2026예산
!       2026예산/1분기
!       2026예산/1분기/보고1.hwp
… (총 missing 8개)
?       2026예산_최종
```

- 트리거:
  1. Finder에서 버전관리 중인 폴더를 이름변경하거나 휴지통으로 옮긴다(파일 6개 폴더 → `missing` 8개).
  2. 앱에서 "전체 선택"을 누른다 → 8개가 모두 삭제 대상으로 선택된다.
  3. 커밋 메시지를 쓰고 커밋한다.
- 증상: 삭제 확인창이 8개를 나열하므로 최종 방어선은 살아 있다. 문제는 그 앞 단계다. 삭제 예정 항목이 수정 항목과 똑같은 체크박스로 보이고, 행에서 "로컬 파일 복원"을 선택할 수단이 없어졌다. 복원 경로는 (a) 행을 우클릭한 컨텍스트 메뉴(`ChangesView.swift:268`–`276`)와 (b) 삭제 확인창 안의 "선택한 서버 파일 복원" 두 곳뿐이다. 우클릭을 쓰지 않는 사용자는 커밋 확인창까지 가야 복원 수단을 만난다.
- 확률: 높음(폴더 이름변경·이동 자체). 손실까지 이어질 확률은 낮음 — 확인창이 개수와 경로를 보여준다. 삭제된 내용은 저장소 이력에 남고 이력 화면에서 개별 파일로 저장해 되살릴 수 있다.
- 고치는 방법: 125행의 죽은 분기를 제거하고, 삭제 예정 행의 체크박스 옆에 상태 배지와 "로컬 파일 복원" 인라인 버튼을 함께 둔다.

---

## 7. 커밋 확인창의 기본 버튼(Return)이 파괴적 동작이다

- 심각도: 낮음
- 근거: `Sources/SVNMac/CommitConfirmationView.swift:109`–`115` (`"커밋 확인"`에 `.keyboardShortcut(.defaultAction)`)
- 재현: **코드 기준 추정**
- 트리거: 서버 삭제가 포함된 커밋 확인창이 떠 있는 상태에서 Return을 누른다. 커밋 메시지 입력에서 Return으로 제출한 흐름(`CommitControlsView.swift:69`–`76`)이라면 Return을 두 번 눌러 확인창을 지나칠 수 있다.
- 증상: 목록을 읽지 않고 서버 삭제가 실행된다.
- 확률: 낮음~중간. 시트가 새로 열릴 때 포커스가 어디로 가는지는 확인하지 않았다.
- 고치는 방법: 삭제 항목이 있을 때는 `.defaultAction`을 "아니오" 쪽에 두거나 어느 버튼에도 두지 않는다. 같은 시트의 나머지 파괴적 대화상자들은 `.destructive` 역할만 쓰고 `.defaultAction`을 지정하지 않는다(`TreeConflictResolutionView.swift:28`, `ConflictResolutionView.swift:31`, `WorkingCopyRecoveryDialogs.swift:120`).

---

## 기준을 충족한 것 (참고)

기준 선례와 같은 수준이거나 별도 조치가 필요 없다고 판단한 것들이다.

- `RevisionFileService.restoreWorkingFile`(`:113`–`182`) — 복구본 스테이징 → `filesHaveEqualContents` 검증 → `moveItem`, 새 내용도 스테이징 후 재검증. 기준과 동일 수준. 발견 4는 "복구본을 못 찾는다"는 별개 문제다.
- `emptyWorkingCopy`(`ProjectDependencies.swift:260`–`281`) — 심볼릭 링크 거부, `.svn/wc.db` 정규 파일 존재 확인, 그리고 `canEmptySafely`가 **체크아웃 시작 전 폴더가 비어 있었는지**로 제한된다(`ProjectStore.swift:783`, `836`, `857`). 기존 폴더를 대상으로 선택했으면 버튼 자체가 뜨지 않는다(`WorkingCopyRecoveryDialogs.swift:80`–`92`). 확인 문구도 경로와 비가역성을 명시한다.
- 경로 탈출·심볼릭 링크 (감사 항목 4): 파괴 대상 경로를 만드는 곳을 모두 추적했고 작업 복사본 밖을 가리킬 수 있는 경로는 찾지 못했다. `ConflictFileService.sourceURL`(`:234`–`257`, `attributesOfItem`은 링크를 따라가지 않아 `.typeSymbolicLink`를 거부), `RevisionFileService.regularWorkingFile`(`:184`–`203`, 절대경로·상위탈출 거부 + `isSymbolicLink` 거부), `TemporaryFilePolicy.containedFileURL`(`:198`–`213`, `..`/`.` 성분 거부 + 링크 해석 후 재검사), `performVersionedFileAction`(`RepositoryMaintenance.swift:250`–`255`)이 모두 정규 파일 + 루트 하위를 확인한다.
- 임시파일 정리의 부분 실패 처리(`ProjectStore+Update.swift:160`–`245`) — 경로별 실패를 수집해 목록으로 보여주고, 커밋이 실패하면 예약한 삭제를 전부 `revert`로 되돌린다. 재시도 시 이중 적용도 없다.
- 삭제 확인창의 다중 복원(`ProjectStore+FileActions.swift:72`–`132`) — 부분 실패를 `"%1$@개를 복원했고 %2$@개는 실패했습니다."` + 경로별 사유로 보고하고, `revert`가 멱등이라 남은 항목 재시도가 안전하다. 실패한 항목은 선택 상태로 남아 계속 목록에 보인다.
- `commit`의 방어선(`ProjectStore.swift:1217`–`1233`) — 선택된 경로 중 아직 `missing`인 것이 남아 있으면 커밋을 거부한다. 발견 3은 이 검사가 아니라 확인창 스냅샷이 갱신되지 않는다는 문제다.
- 작업 복사본이 사라진 경우(`ensureWorkingCopyDirectoryExists`, `ProjectStore.swift:1725`–`1739`) — 네트워크 볼륨이 언마운트되어 작업 폴더 자체가 없어지면 프로젝트를 사용 불가로 표시하고 자동 리프레시를 막는다. "볼륨 해제 → 전 파일 `missing` → 전체 선택 커밋"이라는 대량 오작동 경로는 이 지점에서 차단된다. 실제로 남은 대량 경로는 Finder에서의 폴더 이동·이름변경(발견 6)이다.
- 저장소 이전 relocate(`ProjectStore+RepositoryMaintenance.swift:148`–`207`) — 파일을 건드리지 않고, 스킴 화이트리스트와 확인창(현재 URL / 새 URL 병기)이 있으며 실패 시 현재 URL을 다시 읽어 요청을 복원한다.
- 이력 보존 이름변경·복사(`:219`–`290`) — `svn move`/`svn copy`는 작업 파일 내용을 파괴하지 않고, 대상 존재 여부를 파일시스템과 SVN 항목 양쪽으로 검사한다.
- `svn:needs-lock` 설정(`:314`–`380`) — 파일 내용이 아니라 속성만 다루고, 실패 시 실제 상태를 다시 읽어 화면을 맞춘다.

### 부수적으로 눈에 띈 것 (데이터 손실 아님)

- `BulkUnlockFailure.message`가 `String(describing: error)`(`LockWorkflow.swift:140`–`143`)이라 부분 실패 대화상자(`RepositoryLocksView.swift:148`–`158`)에 Swift 오류 덤프가 그대로 노출된다. 다른 실패 경로들은 `localizedError`를 쓴다.
- `TemporaryFilePolicy.repositoryCleanupValidationFailure`에서 `nameOnlyCleanupCandidates`(`.Trashes`, `.fseventsd`, `.TemporaryItems`, `.Spotlight-V100`, `.apdisk`, `Icon\r`)는 `:164`–`166`에서 조기 반환하므로 `:168`의 정규 파일 검사를 건너뛴다. 이 이름의 **디렉터리**가 저장소에 커밋돼 있으면 `svn delete --force`가 하위 내용까지 지운다. 그 안에 업무 문서가 들어 있을 가능성은 매우 낮아 손실 시나리오로는 세지 않았다.
- 백업 디렉터리(`Conflict Backups`, `Revision Restore Backups`)를 정리하는 코드는 없다. 무한히 누적된다.

---

## 확인하지 않은 것

- **GUI 실행 확인 전무.** 앱을 띄우지 않았다. SwiftUI `.alert`에서 `role: .destructive` 버튼이 Return 키를 받는지, 시트가 열릴 때 초기 포커스가 어디인지는 확인하지 못했다. 발견 7은 명시적으로 `.keyboardShortcut(.defaultAction)`이 붙은 한 곳만 근거로 삼았고, 나머지 대화상자의 Return 동작은 판단하지 않았다.
- **발견 3 미재현.** 확인창이 열린 동안 창 활성화 리프레시가 실제로 `statuses`를 갱신하는지 GUI로 확인하지 못했다. 코드상 `refreshForMainWindowActivation`의 가드는 `isWorking`뿐이고 모달 표시 여부를 보지 않는다는 점까지만 확인했다.
- **발견 4 Finder 표시 미확인.** 복구본 파일명이 점으로 시작한다는 것과 그 폴더를 여는 UI가 없다는 것은 코드에서 확인했지만, 실제 Finder에서 숨김 처리되는 모습은 확인하지 않았다.
- **발견 5의 손실 단계 미재현.** `svn unlock`이 `svn:needs-lock` 파일을 읽기전용으로 만드는 것은 재현했다. 그 상태에서 Excel·한글이 편집 중 버퍼를 어떻게 처리하는지는 확인하지 않았다.
- **`swift test` 미실행.** 읽기 전용 감사라 테스트를 추가하지 않았고, 기존 493개 스위트도 돌리지 않았다. 발견 1과 관련해 `svn info --xml`에 충돌 요소가 여러 개 오는 경우를 다루는 파서 테스트는 존재하지 않는다(`Tests/SVNCoreTests/SVNXMLParserTests.swift`에 해당 케이스 없음).
- **속성 충돌의 `mine-full` 방향 미검증.** "내 속성 유지"(`mine-full`)가 동시 내용 충돌에서 작업 파일을 어떻게 다루는지는 재현하지 않았다. `theirs-full` 방향만 확인했다.
- **`nameOnlyCleanupCandidates` 디렉터리 케이스 미재현.** 위 부수 항목의 `svn delete --force` 재귀 삭제는 코드 기준 추정이다.
