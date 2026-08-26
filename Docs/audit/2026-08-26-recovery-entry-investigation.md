# 작업 복사본 복구 진입점 조사

날짜: 2026-08-26
범위: 읽기 전용. 앱 GUI는 띄우지 않았다. `swift test`는 실행하지 않았다.
방법: `Sources/`·`Tests/` 검색, 관련 화면 파일 열람, `git log -S` / `git show`.

추측과 확인한 사실을 섞지 않는다. 「판단」절만 해석이다.

---

## 1. `beginPathRecovery()`와 그 뒤 흐름이 하는 일

### 확인한 사실

`ProjectStore.beginPathRecovery()` (`Sources/SVNMac/ProjectStore+Recovery.swift:23-38`)는 선택된 프로젝트에 대해:

1. `client.recoveryPreview(at:credentials:)`를 호출한다.
2. 미리보기를 `pathRecoveryPreview`에 넣고 `pathRecoverySourceProjectID`를 기록한다.
3. `isShowingPathRecovery = true`로 시트를 연다.
4. 실패하면 `errorMessage`만 채운다. 시트를 열지 않는다.

시트는 `ChangesView`에만 붙어 있다 (`Sources/SVNMac/ChangesView.swift:49-52` → `WorkingCopyRecoveryView`).

`SVNClient.recoveryPreview` (`Sources/SVNCore/SVNClient.swift:661-667`)는 작업 복사본 스냅샷을 읽어 `SVNWorkingCopyRecovery.preview`에 넘긴다. 미리보기는 (`Sources/SVNCore/SVNWorkingCopyRecovery.swift:55-112`):

- 커밋 가능한 실제 변경(수정·추가·미등록·삭제·누락)만 매핑한다.
- NFC/NFD 별칭 충돌 건수를 `ignoredAliasCount`로 센다.
- 서버에 정규화 키가 같은 관리 경로가 둘 이상이면 그 충돌을 `blockingPaths`에 넣는다 (`Sources/SVNCore/SVNWorkingCopyRecovery.swift:62-67`).
- 속성 변경, switched, 충돌, 폴더 수정, 경로 탈출 등 복사로 재현할 수 없는 상태도 `blockingPaths`에 넣는다 (`Sources/SVNCore/SVNWorkingCopyRecovery.swift:77-97`, `278-284`).

사용자가 시트에서 빈 폴더를 고르고 `recoverNewWorkingFolder`를 누르면 `ProjectStore.recoverWorkingCopy(to:)` (`Sources/SVNMac/ProjectStore+Recovery.swift:41-108`)가 돈다. 가드:

- 대상이 이미 등록된 작업 폴더면 거부 (`:46-49`).
- 대상이 원본 안이거나 원본을 품으면 거부 (`:52-57`, `Sources/SVNCore/SVNWorkingCopyRecovery.swift:118-126`). 중첩 체크아웃을 막기 위한 주석이 코드에 있다.

통과하면 `SVNClient.recoverWorkingCopy` (`Sources/SVNCore/SVNClient.swift:669-727`)가:

1. 빈 대상 폴더를 준비한다.
2. 원본 BASE 리비전으로 새로 checkout한다 (`:688-698`). 주석: HEAD로 받으면 그 사이 서버 커밋이 새 BASE가 되어 out-of-date 검사 없이 다른 사람 변경이 사라질 수 있다.
3. 파일별 BASE를 고정한다 (`pinRecoveryBaseRevisions`).
4. 미리보기 매핑대로 원본의 실제 변경 파일만 복사·삭제한다 (`SVNWorkingCopyRecovery.apply`, `:179-201`).
5. 추가·삭제 예약을 svn 명령으로 다시 세운다 (`restoreRecoveryScheduling`, `:732-757`).
6. 대상 스냅샷에 경로 충돌이 남아 있으면 실패한다 (`:714-716`).
7. 실패 시 대상 폴더를 롤백한다 (`:722-725`).

성공 시 스토어는 원본 프로젝트를 지우지 않고 복구본을 목록에 추가한다. 선택이 아직 원본이면 복구본으로 전환하고 안내 문구를 띄운다 (`Sources/SVNMac/ProjectStore+Recovery.swift:86-103`, `ProjectStore.registerRecoveredCheckout` `:1902-1906`).

화면 문구 (`Sources/SVNMac/WorkingCopyRecoveryView.swift:14-26, 85-91`): 자동 유니코드 경로 복구, 서버에서 깨끗한 작업 복사본을 받고 실제 로컬 변경만 옮김, 성공해도 원본과 복구본이 사이드바에 둘 다 남음.

### 사용자 관점 (코드가 말하는 목적)

이 기능은 NFC/NFD 한글 경로 별칭으로 작업 복사본 메타데이터가 갈라진 폴더를 **제자리에서 고치지 않고**, 원본은 그대로 둔 채 **새 빈 폴더에 같은 저장소를 BASE로 다시 체크아웃한 뒤 실제 로컬 변경만 옮기는** 복제 복구다.

같은 충돌 화면에 있는 `repairCanonicalAliases()` (`Sources/SVNMac/ProjectStore+Recovery.swift:5-21`)는 다른 동작이다. 새 폴더를 만들지 않고, 로컬 추가 예약 별칭만 `svn revert --depth empty`로 되돌린다 (`Sources/SVNCore/SVNClient.swift:1049-1077`).

최초 진입은 `31f9cb06f9a9852571966ed00b50a602f7ad3372` (`손상된 한글 경로 작업 복사본 자동 복구`)가 `ChangesView` 충돌 행에 `경로 자동 복구…` 버튼을 붙이며 만들었다.

---

## 2. `ChangesViewPerformanceTests.swift:91` 금지 단정이 막으려는 것

### 같은 테스트 함수의 단정들

현재 `collisionActionsUseAggregateRepairabilityAndManualServerGuidance` (`Tests/SVNMacTests/ChangesViewPerformanceTests.swift:83-92`):

| 줄 | 단정 | 현재 `ChangesView.swift` |
|---|---|---|
| 86 | `.ui.cleanup.cleanUpEquivalentPath` 있음 | `:297` 제자리 정리 버튼 |
| 87 | `store.canRepairCanonicalAliases` 있음 | `:292` 집계 판정 |
| 88 | `await store.repairCanonicalAliases()` 있음 | `:294` |
| 89 | `.ui.changes.resolveDuplicateServerPathsManually` 있음 | `:303` 안내 문구 |
| 90 | `if collision.repairableRawPath != nil` 없음 | 행 단위 분기 없음 |
| 91 | `await store.beginPathRecovery()` 없음 | 호출 없음 |

충돌 행 실제 분기 (`Sources/SVNMac/ChangesView.swift:291-307`):

- `canRepairCanonicalAliases`가 참이면 제자리 정리 버튼.
- 아니면 버튼이 아니라 `서버 중복 경로 수동 정리 필요` 텍스트 + help (`:306` `.ui.changes.multipleCanonicallyEquivalentServerPathsExistSoAppCannotChoose`).

`canRepairCanonicalAliases` (`Sources/SVNMac/ProjectStore.swift:733-735`): 충돌이 하나 이상이고 **모든** 충돌의 `repairableRawPath != nil`. 하나라도 수리 불가면 원클릭 정리를 주지 않는다.

`hasUnrepairablePathCollisions`는 커밋 가능 여부에도 쓰인다 (`ProjectStore.swift:737-744`). 수리 불가 충돌이 있으면 커밋을 막는다.

### 이 줄이 들어온 커밋

`git log -S 'await store.beginPathRecovery()' -- Tests/SVNMacTests/ChangesViewPerformanceTests.swift` 결과 4개. 금지(`!contains`)로 뒤집힌 커밋은 하나다.

**해시:** `a121112f0a3c003daf54358ba4d79b4002ba08cb`  
**날짜:** Mon Jul 20 14:00:24 2026 +0900  
**제목:** `정규화 별칭 복구 안전성 보강`  
**본문:** 없음.

이 커밋의 `ChangesViewPerformanceTests` diff:

```
-    @Test func repairableUnicodeCollisionsUseOneClickInPlaceRepair() throws {
+    @Test func collisionActionsUseAggregateRepairabilityAndManualServerGuidance() throws {
         ...
-        #expect(changesView.contains("if collision.repairableRawPath != nil"))
+        #expect(changesView.contains("store.canRepairCanonicalAliases"))
         #expect(changesView.contains("await store.repairCanonicalAliases()"))
-        #expect(changesView.contains("await store.beginPathRecovery()"))
+        #expect(changesView.contains("서버 중복 경로 수동 정리 필요"))
+        #expect(!changesView.contains("if collision.repairableRawPath != nil"))
+        #expect(!changesView.contains("await store.beginPathRecovery()"))
```

같은 커밋의 `ChangesView` diff: 수리 불가 분기의 `경로 자동 복구…` 버튼(`beginPathRecovery()`)을 지우고, 수동 정리 안내 텍스트로 바꿨다. 행 단위 `collision.repairableRawPath != nil`을 집계 `store.canRepairCanonicalAliases`로 바꿨다.

같은 커밋이 설계 문서도 고쳤다 (`Docs/superpowers/specs/2026-07-20-canonical-alias-in-place-repair-design.md`):

- 이전: 서버 경로가 모호하면 「기존의 새 작업 폴더 복구 또는 수동 확인 안내를 유지」.
- 이후: 「자동 복구 동작 대신 서버 중복 경로를 수동으로 정리하라는 안내」. mixed 상태에서는 원클릭 정리도 표시하지 않음.

README 같은 커밋 (`README.md` 당시 문장): 「서버 경로가 모호한 상태에서는 새 작업 폴더로의 복구도 진행할 수 없습니다.」

현재 README도 그 결정을 유지한다 (`README.md:122`). 다만 기능 목록 `:15`는 여전히 「한글 경로가 이미 충돌한 작업 폴더를 원본 보존 방식의 새 작업 폴더로 자동 복구」를 적고 있다. UI와 불일치한다.

### 바로 앞 커밋 (금지의 전제)

`d7874043d5b8f971d7d0650409af75cc8208a0ab` (`동일 한글 경로 원클릭 정리 추가`, Mon Jul 20 13:22:22 2026 +0900):

- 수리 가능하면 제자리 정리.
- **아니면** 기존 `beginPathRecovery()` 버튼을 유지.
- 테스트는 `await store.beginPathRecovery()`가 **있을 것**을 요구했다.

`a121112`는 그 폴백을 38분 뒤에 제거하면서 테스트 단정도 반대로 고정했다.

### 금지 단정이 막는 것 (사실)

`ChangesView.swift` 소스 문자열에 `await store.beginPathRecovery()`가 다시 들어가면 이 테스트가 실패한다. 수리 불가 충돌 행에서 새 폴더 복구 시트를 여는 경로를 회귀로 취급한다.

이 테스트는 `ChangesView.swift`만 읽는다 (`:84`). 다른 파일의 호출은 이 단정과 충돌하지 않는다.

---

## 3. 지금 도달 경로는 0인가

### 확인한 사실: production `Sources/`에서 시트를 켜는 사용자 경로는 0

`isShowingPathRecovery = true`를 쓰는 곳 (`Sources/`):

1. `ProjectStore+Recovery.swift:34` — `beginPathRecovery()` 안.
2. `ProjectStore.swift:245-246` — `didSet`: 시트를 닫으려 해도 `isPathRecoveryRunning`이면 다시 `true`. 진행 중 닫기 방지. 시작점이 아니다.

`beginPathRecovery()` 호출 (`Sources/`): 정의만 있다. 화면·메뉴·툴바에서 호출하는 곳이 없다.

`pathRecoverySourceProjectID` 대입 (`Sources/`): `beginPathRecovery()`만 한다 (`ProjectStore+Recovery.swift:32`). `isPathRecoveryRunning` (`ProjectStore.swift:671-674`)은 이 ID가 있어야 `.recover` 작업을 본다. production에서 ID가 안 세워지므로 didSet 재오픈도 발동하지 않는다.

시트를 `false`로 내리는 곳: `WorkingCopyRecoveryView.swift:20` (닫기), `ProjectStore.prepareRefreshRequest` `:1265`, `resetSelectedProjectState` `:1951`. 켜는 경로가 아니다.

### 메뉴·툴바·단축키

- `SVNMacApp.swift:88-100`: 체크아웃 (`⌘O`), 도움말(문의). 복구 없음.
- `SVNMacCommands` (`AppAboutView.swift:80-98`): 정보, 업데이트 확인. 복구 없음.
- `ContentView` 툴바 (`:109-174`): 새로고침, 업데이트. 복구 없음.
- 프로젝트 머리글 (`ContentView.swift:275-284`, `:313-348`): 저장소 경로 정규화, 잠금, Finder, 폴더 설정. 복구 없음. 저장소 경로 정규화는 서버 경로 NFC 정리이며 `beginPathRecovery`와 다른 기능이다.

`keyboardShortcut` 중 경로 복구 시트 실행용은 `WorkingCopyRecoveryView.swift:93`의 기본 동작(이미 열린 시트 안)뿐이다.

### 오류 화면

`DetailedErrorView`는 복사·닫기만 있다 (`Sources/SVNMac/DetailedErrorView.swift:56-82`). 복구 버튼 없음.

`WorkingCopyRecoveryDialogs.swift`의 `CanceledCheckoutRecoveryView` / `WorkingCopyCleanupView`는 중단된 체크아웃·작업 복사본 cleanup이다. `isShowingPathRecovery`를 건드리지 않는다.

### 이름이 비슷한 다른 「recovery」

`ProjectRecoveryState` (`Sources/SVNMac/ProjectRecoveryState.swift`)는 충돌·업데이트 미리보기·out-of-date 커밋 재시도 등 다른 화면 상태 묶음이다. `isShowingPathRecovery`를 들고 있지 않다.

### 테스트에서만 도달

- `Tests/SVNMacTests/ProjectStoreTests.swift:3400` — `await store.beginPathRecovery()`.
- 같은 파일 `:675`, `:2377`, `:3422` — 플래그를 테스트가 직접 `true`로 설정.
- `ChangesViewPerformanceTests.swift:91` — 호출 **금지**.

### 확인하지 않은 것

- 앱 GUI를 띄워 숨은 메뉴/접근성 동작을 누르지는 않았다.
- SwiftUI가 `$store.isShowingPathRecovery` 바인딩을 코드 없이 `true`로 올릴 수 있는지는 런타임으로 확인하지 않았다. 초기값은 `false`이고 디스크에 저장하는 코드는 보지 못했다.
- `#Preview`에서 시트를 여는 코드는 `Sources/`에 없다.

코드 검색 기준으로 production 진입점은 0이다.

---

## 4. 진입점 후보

### 후보 A. `ChangesView` 충돌 행 폴백에 버튼을 되돌림

- **도달 상황:** 한글 경로 충돌이 있고 `canRepairCanonicalAliases == false`일 때. 서버에 정규화 동등 경로가 둘 이상이거나, 수리 가능 별칭과 모호한 서버 경로가 섞인 때 (`ProjectStore.swift:733-738`, `SVNWorkingCopySnapshot.swift:151-154, 256-271, 461-469`).
- **잘못 눌렀을 때:** `beginPathRecovery`는 미리보기만으로도 스냅샷 조회를 한다. 미리보기의 `blockingPaths`가 비어 있지 않으면 시트는 열려도 복구 버튼이 비활성이다 (`WorkingCopyRecoveryView.swift:94-98`). 서버 중복 경로는 preview가 바로 blocker로 넣는다 (`SVNWorkingCopyRecovery.swift:62-67`). 막히지 않고 실행되면 빈 폴더에 저장소 전체 checkout + 파일 복사다. 원본은 남지만 디스크를 한 벌 더 쓰고, 사이드바에 복구본이 추가되며 선택이 바뀔 수 있다 (`ProjectStore+Recovery.swift:86-103`).
- **건드릴 파일:** `Sources/SVNMac/ChangesView.swift`. 테스트 단정도 바꿔야 하면 `Tests/SVNMacTests/ChangesViewPerformanceTests.swift`.
- **금지 단정과 충돌:** 한다. `:91`이 바로 이 문자열을 금지한다. `:90`은 행 단위 `repairableRawPath` 분기도 금지한다.

이 자리는 `a121112`가 의도적으로 비운 자리다.

### 후보 B. 프로젝트 머리글 또는 앱 메뉴의 명시적 「새 작업 폴더로 복구」

- **도달 상황:** 충돌 유무와 관계없이, 작업 복사본이 손상됐다고 판단한 사용자가 머리글/메뉴에서 고르는 경우. 저장소 경로 정규화 버튼과 같은 층 (`ContentView.swift:313-327`).
- **잘못 눌렀을 때:** 후보 A와 같은 무거운 checkout. 충돌 행보다 노출이 넓어 오클릭 면적이 더 크다. 시트에 미리보기·빈 폴더 선택·차단 경로가 있어 한 번에 실행되지는 않는다 (`WorkingCopyRecoveryView.swift:28-98`). `beginPathRecovery` 실패 시 루트 오류 시트가 뜬다 (`ProjectStore+Recovery.swift:35-38`, `ContentView.swift:237-239`).
- **건드릴 파일:** `Sources/SVNMac/ContentView.swift` 또는 `Sources/SVNMac/SVNMacApp.swift` / `AppAboutView.swift`의 `SVNMacCommands`. 시트는 이미 `ChangesView`에 있으므로 시트를 옮기지 않으면 `ChangesView.swift`는 안 건드려도 된다. 시트를 머리글로 옮기면 `ChangesView.swift`와 `PresentationOwnershipRegressionTests` 쪽 시트 소유 단정도 본다.
- **금지 단정과 충돌:** `ChangesView.swift`에 `await store.beginPathRecovery()`를 넣지 않으면 `:91`과 충돌하지 않는다. 이 테스트는 그 파일만 읽는다.

### 후보 C. 제자리 정리 실패 뒤의 다음 수단

- **도달 상황:** `canRepairCanonicalAliases`가 참이라 제자리 정리를 눌렀는데 `repairCanonicalAliases()`가 `errorMessage`를 남긴 뒤 (`ProjectStore+Recovery.swift:17-19`). 지금은 오류 상세만 있고 다음 동작이 없다.
- **잘못 눌렀을 때:** 가벼운 revert가 실패한 상태에서 전체 checkout으로 넘어간다. 실패 원인이 서버 모호 경로면 preview가 다시 막을 수 있다. 원인이 잠금·권한·일시 오류면 불필요한 복제본이 생긴다.
- **건드릴 파일:** 오류 UI를 `ChangesView` 충돌 행에 붙이면 `ChangesView.swift` (+ 테스트 `:91`). `DetailedErrorView`에 붙이면 `Sources/SVNMac/DetailedErrorView.swift`와 presenter. 후자는 `:91`과 충돌하지 않는다.
- **금지 단정과 충돌:** 호출 문자열이 `ChangesView.swift`에 있으면 충돌. 다른 파일이면 충돌하지 않음.

---

## 5. 아무것도 붙이지 않는 선택

### 판단

충돌 행에 `beginPathRecovery()`를 다시 붙이지 않는 편이 맞다. `a121112`가 막은 바로 그 동작이다.

근거 (사실):

1. 수리 가능한 로컬 별칭은 이미 제자리 정리 버튼이 있다 (`ChangesView.swift:292-300`). 스토어 테스트가 이 경로에서 시트를 열지 않음을 고정한다 (`ProjectStoreTests.swift:2733-2764`).
2. 수리 불가의 대표 경우는 서버 중복 경로다 (`SVNWorkingCopySnapshot.swift:151-154`, 설계 문서 `Docs/superpowers/specs/2026-07-20-canonical-alias-in-place-repair-design.md:43`). 그 경우 recovery preview도 `blockingPaths`에 넣어 복구 버튼을 죽인다 (`SVNWorkingCopyRecovery.swift:62-67`, `WorkingCopyRecoveryView.swift:94-98`). 시트를 열어도 실행되지 않는다.
3. `a121112`는 UI·테스트·설계·README를 함께 바꿔 「모호한 서버 경로에서는 자동 복구 없음」을 고정했다. 충돌 행에 버튼을 되돌리면 그 커밋을 되돌리는 일이다.
4. 금지 단정 `:91`은 성능 테스트 이름이지만 실제로는 이 제품 결정을 소스 계약으로 잠근 것이다.

후보 B·C는 `:91`과 반드시 충돌하지 않는다. 그래도 지금 충돌 UX의 빈칸을 메우지는 못한다. 수리 불가는 시트를 열어도 막히는 쪽이고, 수리 가능은 더 가벼운 제자리 정리가 있다.

시트를 살릴 이유가 따로 있다면 그것은 「제자리 정리로 못 고치는, 그러면서 preview `blockingPaths`가 비어 있는」 손상 작업 복사본이 실제로 있는지를 먼저 재현한 뒤의 일이다. 이 조사는 그 입력 fixture를 만들지 않았다. 확인하지 못했다.

이전 감사 `Docs/audit/2026-08-25-audit-ui.md:122-130`은 「수리 불가면 `beginPathRecovery()`를 부르거나 죽은 시트를 제거」를 고치는 방법으로 적었다. 그 문장은 `a121112`의 결정과 반대다. 그 감사를 따라 충돌 행에 다시 붙이지 않는다.

`README.md:15`는 새 폴더 자동 복구를 제공 기능으로 적고, `:122`는 모호한 서버 경로에서 자동 복구를 하지 않는다고 적는다. 문서 불일치는 이 조사의 수정 범위가 아니다.

### 확인하지 않은 것

- 제자리 정리가 실패한 실제 작업 복사본에서 recovery preview의 `blockingPaths`가 비는 경우가 있는지는 재현하지 않았다.
- `Docs/audit/2026-08-26-sweep-b1-codex.md:42`는 `recoverWorkingCopy`가 HEAD로 checkout한다고 적었다. **현재 코드는 BASE다** (`SVNClient.swift:688-698`). 그 감사 문장은 현재 트리와 다르다. HEAD 가정으로 진입점 판단을 바꾸지 않는다.
- 복구 구현의 다른 결함(인증서 전달, 대상 폴더 수명, NFD 검사 누락 등)은 이번 범위가 아니다. 진입점을 붙이면 그 결함이 사용자에게 열린다는 선행 감사(`Docs/audit/2026-08-26-sweep-b1-claude.md:17`)는 참고만 한다.

---

## 결론

production에서 `beginPathRecovery()`에 닿는 화면·메뉴·단축키·오류 동작은 없다. 시트와 스토어 로직은 남아 있고 테스트만 직접 호출한다.

`Tests/SVNMacTests/ChangesViewPerformanceTests.swift:91`은 `a121112f0a3c003daf54358ba4d79b4002ba08cb` (`정규화 별칭 복구 안전성 보강`)가 넣었다. 수리 불가 충돌 행에서 새 작업 폴더 복구를 여는 회귀를 막는다.

충돌 행에 버튼을 되돌리지 않는다. 다른 자리의 전문가 진입점은 이 조사만으로 필요하다고 단정하지 않는다.
