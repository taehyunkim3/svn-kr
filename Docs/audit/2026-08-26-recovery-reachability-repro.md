# 작업 복사본 복구 도달 가능성 재현

날짜: 2026-08-26
환경: macOS 26.6.2, svn/svnadmin 1.14.5
결론: `canRepairCanonicalAliases == false`이고 `recoveryPreview().blockingPaths == []`인 실제 작업 복사본을 재현했다.

## 확인한 사실

### 상류 데이터 흐름

`SVNClient`는 작업 복사본에서 `svn status --verbose --no-ignore --xml`을 실행한다
(`Sources/SVNCore/SVNClient.swift:873-878`). XML 파서는 각 `wc-status`의 원문 경로,
`item`, 리비전, `tree-conflicted`, 속성 상태, switched 상태를 `SVNWorkingCopyEntry`로 만든다
(`Sources/SVNCore/SVNXMLParser.swift:514-531`).

스냅샷은 리비전이 0 이상이고 unversioned/ignored/external이 아닌 항목을 관리 경로로 분류한 뒤,
NFC 키별 원문 경로 목록을 만든다 (`Sources/SVNCore/SVNWorkingCopySnapshot.swift:137-149`).
production에서 충돌을 새로 만드는 곳은 ambiguous 관리 경로와 orphaned 추가 예약 루트 두 곳이고,
마지막에 같은 NFC 키를 병합한다 (`Sources/SVNCore/SVNWorkingCopySnapshot.swift:151-173,461-469`).

`ProjectStore`는 이 스냅샷의 `collisions`를 그대로 `pathCollisions`에 넣는다
(`Sources/SVNMac/ProjectStore.swift:1319-1332`). 따라서 아래 재현에서 테스트가 계산한
`!collisions.isEmpty && collisions.allSatisfy { $0.repairableRawPath != nil }`은
`ProjectStore.canRepairCanonicalAliases`의 식과 같다 (`Sources/SVNMac/ProjectStore.swift:733-735`).

### `repairableRawPath == nil` 전수 표

| 수리 불가 원인 | 그 원인이 `blockingPaths`에 들어가는가 | 근거 `파일:줄` |
|---|---|---|
| 같은 NFC 키에 관리 원문 경로가 2개 이상 | 예 | nil 충돌 생성: `Sources/SVNCore/SVNWorkingCopySnapshot.swift:137-154`; 관리 경로 수가 2개 이상이면 차단: `Sources/SVNCore/SVNWorkingCopyRecovery.swift:62-67` |
| orphaned 추가 예약 루트와 같은 NFC 키의 관리 경로가 2개 이상 | 예 | 비어 있지 않은 관리 경로를 찾고 `count != 1`이면 nil: `Sources/SVNCore/SVNWorkingCopySnapshot.swift:260-272`; 같은 `count > 1` 판정으로 차단: `Sources/SVNCore/SVNWorkingCopyRecovery.swift:62-67` |
| orphaned 추가 예약 루트 아래 tree conflict가 있고, 해당 항목이 non-normal이거나 속성 변경/switched 상태 | 예 | subtree tree conflict면 nil: `Sources/SVNCore/SVNWorkingCopySnapshot.swift:265-272`; 표시 상태에 남은 tree conflict를 `.conflicted`로 변환: `Sources/SVNCore/SVNWorkingCopySnapshot.swift:289-343`; `.conflicted`는 복사 불가라 차단: `Sources/SVNCore/SVNWorkingCopyRecovery.swift:69-84,278-284` |
| orphaned 추가 예약 루트 아래 tree conflict가 `item="normal"`, 속성 없음, switched 아님 | **아니오** | subtree tree conflict면 nil: `Sources/SVNCore/SVNWorkingCopySnapshot.swift:265-272`; normal/속성 없음/switched 아님 항목은 표시 상태에서 제거: `Sources/SVNCore/SVNWorkingCopySnapshot.swift:289-292`; 복구는 표시 상태만 순회: `Sources/SVNCore/SVNWorkingCopyRecovery.swift:69-106` |
| 같은 NFC 키의 충돌 원인이 2개 이상 병합됨 | 예 | ambiguous와 orphaned 충돌을 합침: `Sources/SVNCore/SVNWorkingCopySnapshot.swift:151-173`; orphaned 루트는 같은 NFC 루트를 하나만 남김: `Sources/SVNCore/SVNWorkingCopySnapshot.swift:274-280`; 병합 값이 2개면 nil: `Sources/SVNCore/SVNWorkingCopySnapshot.swift:461-469`; 따라서 이 경우 포함된 ambiguous 관리 경로가 `count > 1` 차단에 걸림: `Sources/SVNCore/SVNWorkingCopyRecovery.swift:62-67` |

`versionedPaths.count == 0`은 orphaned 후보의 앞선 guard가 제거하므로 수리 불가 경우가 아니다
(`Sources/SVNCore/SVNWorkingCopySnapshot.swift:260-264`). 병합 값이 하나일 때의 nil은 앞선 원인을
그대로 전달할 뿐 새 원인이 아니다 (`Sources/SVNCore/SVNWorkingCopySnapshot.swift:461-469`).

### 실제 svn 재현

테스트: `Tests/SVNCoreTests/SVNWorkingCopyRecoveryReachabilityTests.swift`

1. `/tmp`의 `svnadmin create` 저장소에 NFC `관리 폴더/충돌 폴더/기존.txt`를 만들고 trunk를 branch로 복사했다.
2. case-sensitive APFS 작업 복사본에서 `기존.txt`를 수정했다. branch에서 상위 `충돌 폴더`를 삭제한 뒤 trunk 작업 복사본에 merge했다.
3. 실제 `svn status --xml` 결과는 NFC `관리 폴더/충돌 폴더`에 `item="normal"`, `tree-conflicted="true"`, `props="none"`, `switched=false`였다.
4. 같은 작업 복사본에 NFD `관리 폴더` 추가 예약을 만들었다. 기존 통합 테스트와 같이 `.svn`을 일반 볼륨 작업 복사본으로 옮기고 NFC 실제 파일만 다시 만들었다.
5. merge가 루트에 만든 `svn:mergeinfo` 속성 변경은 `svn revert --depth empty`로 되돌렸다. 되돌리기 전에는 `blockingPaths == ["."]`였고, 되돌린 뒤에도 하위 tree conflict와 로컬 파일 수정은 남았다.

그 상태에서 production `SVNClient`로 확인한 값:

```text
canRepairCanonicalAliases=false
collision canonicalPath="관리 폴더", repairableRawPath=nil
recoveryPreview.blockingPaths=[]
recoveryPreview.mappings contains ("관리 폴더/충돌 폴더/기존.txt", modified)
```

테스트는 원문 경로 비교에 `Data(path.utf8)`을 사용한다. Swift `String` 비교는 NFC/NFD를 같게
취급하므로 이 재현에서 관리 항목과 별칭 항목을 구분하지 못한다.

fixture, 저장소, 디스크 이미지, mount는 모두 `/tmp` 아래에 만든다. `defer` 정리는 detach와
fixture 삭제 실패를 무시해 정리 실패가 테스트 실패를 덮지 않게 한다.

## 판단

「제자리 정리 불가 + 새 폴더 복구 preview 차단 없음」 조합은 존재한다. 수리 불가 원인은
normal tree conflict가 포함된 별칭 subtree다. `visibleStatuses`가 이 tree conflict를 제거해
복구 차단 판정까지 전달하지 않는다.

따라서 사용자가 고칠 수단 없는 화면에 갇히는 입력이 있다. 이 결과는 복구 진입점 검토 근거다.
이번 범위에서는 UI 진입점과 production 소스를 수정하지 않았다. `recoverWorkingCopy` 전체 실행은
하지 않았고, 작업에서 정한 실행 가능 조건인 `recoveryPreview().blockingPaths.isEmpty`까지 확인했다.
