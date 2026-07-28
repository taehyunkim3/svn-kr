# 로컬 누락 처리 및 Git 무시 규칙 가져오기 구현 계획

> **For agentic workers:** 이 문서는 구현 전 승인과 작업 추적을 위한 계획서다. 각 작업은 체크박스(`- [ ]`) 단위로 진행하고, 사용자가 만든 기존 변경과 스테이징을 보존한다.

**목표:** SVN이 추적하지만 로컬에서 사라진 항목을 `로컬 누락 · 처리 필요`로 명확히 표시하고, 사용자가 `로컬 파일 복원` 또는 `저장소에서도 삭제`를 선택한 뒤에만 다음 단계로 진행하게 한다. 삭제를 선택한 항목은 `삭제 예정`으로 전환한 뒤 기존 커밋 흐름으로 저장소에 반영한다. 기존 SVN 무시 규칙 관리에는 `.gitignore` 비교·미리보기·선택 가져오기를 추가하되, SVN과 Git의 규칙 차이로 잘못된 범위가 숨겨지지 않게 한다.

**아키텍처:** 일반 `missing`은 커밋 선택 대상에서 제외하고 별도의 처리 결정이 필요한 상태로 관리한다. `저장소에서도 삭제`를 선택하면 `SVNClient`의 원문 경로 보존 명령 계층을 통해 SVN 삭제를 예약하고, 새 상태가 `deleted`인지 검증한 뒤 커밋 선택에 포함한다. `SVNClient.commit`은 더 이상 `missing`을 암묵적으로 `svn delete`로 전환하지 않고 이미 `deleted`인 항목만 커밋한다. 무시 규칙 가져오기는 `.gitignore` 원문을 별도 파서가 중간 표현으로 변환한 뒤, 안전하게 대응되는 규칙만 `svn:ignore` 또는 `svn:global-ignores` 변경 제안으로 만든다. 사용자가 미리보기에서 선택한 제안만 SVN 속성에 반영한다.

**기술 스택:** Swift 6.2, SwiftUI, Foundation, Swift Testing, SVN 1.14 CLI

## 구현 결과

- `2f73594 feat: 로컬 누락 처리와 명시적 저장소 삭제 지원`
- `d0180ad feat: SVN 전역 무시 규칙 관리 확장`
- `04a55da feat: Git 무시 규칙 선택 가져오기 추가`
- `d9a18c5 test: 삭제와 무시 규칙 통합 검증 보강`
- `96afa68 fix: 누락 디렉터리 재귀 복원 보강`
- 실제 SVN fixture에서 누락 파일의 삭제 예정 전환, revert 복원, 삭제 커밋 후 새 작업 복사본 반영을 검증했다.
- 실제 SVN fixture에서 `svn:global-ignores` 속성 커밋 후 다른 작업 복사본의 무시 동작을 검증했다.
- 권한 허용 macOS 환경에서 `swift test --disable-sandbox` 전체 195개 테스트가 통과했다.
- 모듈 캐시를 `/tmp`로 분리한 `swift build --disable-sandbox --product SVNMac`이 통과했다.

## 1. 제품 원칙

### 1.1 상태별 올바른 동작

| SVN 상태 | 의미 | 제공할 주요 동작 |
|---|---|---|
| `missing` | SVN 추적 항목이 로컬에서 사라졌지만 SVN 삭제 의사는 기록되지 않음 | 로컬 파일 복원, 저장소에서도 삭제 |
| `deleted` | 다음 커밋에서 저장소에서 삭제하도록 SVN에 기록됨 | 커밋, 삭제 취소 및 복원 |
| `unversioned` | SVN이 아직 추적하지 않음 | 추가, SVN 무시 규칙 추가 |
| `ignored` | SVN 무시 규칙에 해당 | 무시된 파일 보기에서 확인 |
| `missing`, `revision == -1` | 사라진 추가 예약 | 기존 안전 정리 정책 유지 |

- `svn:ignore`와 `svn:global-ignores`는 미추적 항목에만 적용한다.
- 이미 추적 중인 `missing`, `modified`, `deleted` 항목을 무시 규칙으로 숨기지 않는다.
- `missing`을 단순히 화면에서 숨기는 로컬 필터는 이번 범위에 포함하지 않는다.
- 저장소 삭제와 로컬 복원을 서로 다른 명시적 동작으로 제공한다.
- 삭제 예약은 실제 커밋 전까지 되돌릴 수 있어야 한다.
- 일반 `missing`은 커밋 체크박스와 `모두 선택` 대상에서 제외한다.
- 커밋 계층은 `missing`을 암묵적으로 `deleted`로 전환하지 않는다.
- 사용자가 `저장소에서도 삭제`를 선택해 `deleted`로 검증된 항목만 커밋할 수 있다.

### 1.2 용어

- `로컬 누락`: SVN이 추적하지만 작업 복사본에 파일 또는 디렉터리가 없고 아직 처리 방향을 선택하지 않은 상태
- `처리 필요`: `로컬 누락` 항목에서 복원 또는 저장소 삭제를 선택해야 한다는 사용자용 상태 안내
- `저장소에서도 삭제`: 사용자에게 노출하는 동작 이름. 내부적으로 SVN 삭제 예약을 수행
- `삭제 예정`: SVN 삭제 예약이 끝나 다음 커밋에서 저장소에서도 삭제될 사용자용 상태 이름
- `SVN 삭제 예약`: `svn delete`로 작업 복사본 상태를 `deleted`로 바꾸는 내부 기술 용어
- `SVN 무시 규칙`: `svn:ignore` 또는 `svn:global-ignores` 속성에 저장되는 팀 공유 가능 규칙
- `Git 규칙 가져오기`: `.gitignore`를 읽어 SVN 속성 변경 제안을 만드는 단방향 보조 기능

### 1.3 범위 밖

- Git과 SVN 무시 규칙의 실시간 양방향 동기화
- 변환이 불명확한 `.gitignore` 규칙의 자동 적용
- 추적된 변경 항목을 로컬 설정으로 숨기는 기능
- 실제 파일 또는 디렉터리의 자동 삭제
- 사용자의 확인 없는 SVN 속성 변경 또는 커밋

## 2. 사용자 흐름

### 2.1 로컬 누락 항목

1. 변경 목록에서 일반 `missing` 항목을 `로컬 누락 · 처리 필요`로 표시한다.
2. 일반 커밋 체크박스 대신 발견하기 쉬운 `처리 선택…` 동작을 제공한다.
3. `처리 선택…`에서 다음 동작을 표시한다.
   - `로컬 파일 복원…`
   - `저장소에서도 삭제…`
4. `저장소에서도 삭제…`을 누르면 확인창을 연다.
5. 확인창은 경로, 항목 종류, 디렉터리 하위 영향 여부와 `커밋해야 저장소에서 삭제된다`는 점을 보여준다.
6. 사용자가 승인하면 SVN 삭제를 예약한다.
7. 로컬 상태를 다시 읽어 해당 항목이 `deleted`로 바뀌었는지 검증한다.
8. 화면 배지를 `삭제 예정`으로 바꾸고 해당 항목을 커밋 선택 집합에 자동 포함한다.
9. 사용자는 기존 커밋 화면에서 삭제를 저장소에 반영한다.

미처리 `로컬 누락`은 다음 규칙을 적용한다.

- 커밋 체크박스를 표시하지 않는다.
- `모두 선택`에 포함하지 않는다.
- 커밋 요청에 경로가 유입되면 Core 계층에서도 거부한다.
- 여러 누락 항목은 한 번의 확인으로 `선택 항목을 저장소에서도 삭제` 처리할 수 있다.

확인 문구:

> 이 항목을 저장소에서도 삭제하도록 표시합니다. 지금은 삭제 예정 상태로만 바뀌며, 커밋하면 SVN 저장소에서 삭제됩니다. 커밋 전에는 취소하고 복원할 수 있습니다.

디렉터리 추가 문구:

> 이 디렉터리 아래의 SVN 추적 항목도 함께 삭제 대상으로 예약될 수 있습니다.

### 2.2 삭제 취소 및 복원

1. `삭제 예정` 상태의 항목에서 `삭제 취소 및 복원…`을 선택한다.
2. 내부적으로 기존 revert 흐름을 사용한다.
3. 실행 전 저장소 삭제 표시가 취소되고 저장소 기준 파일이 로컬에 복원된다는 점을 안내한다.
4. revert 후 상태를 다시 읽어 `deleted`가 남지 않았는지 검증한다.

### 2.3 Git 무시 규칙 가져오기

1. 사용자가 `무시 규칙 관리`를 연다.
2. `Git 규칙과 비교` 버튼을 누른다.
3. 앱이 작업 복사본 루트의 `.gitignore`를 읽는다.
4. 각 규칙을 SVN 속성 변경 제안으로 변환한다.
5. 미리보기에서 다음 정보를 제공한다.
   - Git 원문 규칙
   - SVN 속성 종류
   - SVN 속성을 설정할 디렉터리
   - 적용할 패턴
   - 현재 적용 여부
   - 변환 가능 여부와 불가 사유
6. 사용자가 선택한 제안만 적용한다.
7. 변경된 디렉터리 속성이 변경 목록에 표시된다.
8. 팀 공유를 위해 속성 변경을 커밋해야 한다는 안내를 표시한다.

## 3. 삭제 예약 명령 계약

### 3.1 단일 경로

- 로컬에 없는 추적 경로는 `svn delete --force`로 삭제 예약한다.
- 경로는 작업 복사본 상대 경로로 전달한다.
- `--` 또는 기존 단일 작업 복사본 경로 전달 계층을 사용해 옵션처럼 보이는 파일명을 보호한다.
- Foundation 문자열 재구성으로 SVN 경로의 원문 표기를 바꾸지 않는다.

### 3.2 여러 경로

- 여러 경로는 기존 원문 UTF-8 targets 파일 전송 계층을 사용한다.
- 서로의 하위 경로인 대상이 함께 선택되면 가장 짧은 상위 경로만 유지한다.
- 같은 canonical key에 서로 다른 관리 경로가 대응하면 실행을 차단한다.
- 파일과 디렉터리 종류 충돌이 있으면 자동 병합하지 않는다.

### 3.3 실행 전 조건

- 선택 프로젝트가 존재해야 한다.
- 항목 상태가 일반 `missing`이어야 한다.
- `revision == -1`인 사라진 추가 예약은 삭제 예약 기능에서 제외한다.
- 경로 충돌 상태가 없어야 한다.
- 이미 `deleted`인 항목은 다시 실행하지 않는다.
- 저장소 외부 경로 또는 작업 복사본 루트 이탈 경로를 거부한다.

### 3.4 실행 후 검증

- 삭제 명령 성공만으로 완료 처리하지 않는다.
- 새 `SVNWorkingCopySnapshot`을 읽어 대상이 `deleted`가 됐는지 확인한다.
- 대상이 여전히 `missing`이면 실패로 처리하고 상세 오류를 제공한다.
- 일부 대상만 전환됐으면 성공·실패 경로를 구분해 표시하고 자동 커밋하지 않는다.

### 3.5 커밋 경계

- `SVNClient.commit`은 선택 경로가 `missing`이면 명령 실행 전에 거부한다.
- 기존의 `commit` 내부 `missing` 탐지 및 `svn delete --force` 자동 실행을 제거한다.
- `deleted`는 이미 SVN 삭제 예약이 끝난 상태이므로 별도 삭제 명령 없이 커밋 대상에 포함한다.
- UI 검증을 우회해도 Core 계층에서 미처리 누락의 원격 삭제를 차단한다.
- 커밋 실패 시 이번 커밋이 만들지 않은 기존 `deleted` 상태를 자동 revert하지 않는다.

## 4. 무시 규칙 모델

### 4.1 속성 종류

```swift
enum SVNIgnorePropertyKind: String, Codable, Sendable {
    case local
    case global
}
```

- `local`: 특정 디렉터리의 바로 아래 항목에 적용하는 `svn:ignore`
- `global`: 설정 디렉터리 아래에 상속되는 `svn:global-ignores`

기존 `SVNIgnoreRule`은 다음 정보를 표현할 수 있게 확장한다.

```swift
struct SVNIgnoreRule: Identifiable, Hashable, Sendable {
    let directory: String
    let pattern: String
    let propertyKind: SVNIgnorePropertyKind
    let inheritedFrom: String?
}
```

- 직접 설정된 규칙과 상속된 규칙을 구분한다.
- 상속된 규칙은 실제 속성 소유 디렉터리에서만 제거할 수 있다.
- 중복 규칙은 `(directory, propertyKind, pattern)`을 기준으로 판정한다.

### 4.2 Git 규칙 중간 표현

```swift
struct GitIgnoreRule: Identifiable, Hashable, Sendable {
    let sourceLine: Int
    let rawPattern: String
    let pattern: String
    let isNegated: Bool
    let isDirectoryOnly: Bool
    let isRootAnchored: Bool
}
```

```swift
enum IgnoreImportDisposition: Hashable, Sendable {
    case alreadyApplied
    case proposal(SVNIgnoreRule)
    case unsupported(reason: String)
    case conflict(reason: String)
}
```

- `.gitignore` 원문과 줄 번호를 보존한다.
- 주석과 빈 줄은 미리보기 대상에서 제외한다.
- 이스케이프된 `#`, `!`, 공백을 원문 규칙에 맞게 처리한다.
- 규칙 순서가 의미를 갖는 경우 자동 변환하지 않는다.

## 5. `.gitignore` 변환 정책

### 5.1 자동 제안 가능

- 정확한 파일명
- 정확한 디렉터리명
- `*.확장자` 형태의 단순 glob
- 루트 기준의 정확한 파일 또는 디렉터리 경로
- 특정 디렉터리 아래의 정확한 한 단계 패턴

### 5.2 사용자 선택이 필요한 규칙

- 어디에서나 같은 이름을 무시하는 단순 디렉터리 규칙
  - 작업 복사본 루트의 `svn:global-ignores` 제안 가능
  - 적용 범위가 넓다는 경고 표시
- 한 개 이상의 디렉터리 구간을 포함하는 규칙
  - 마지막 구성 요소의 상위 디렉터리에 `svn:ignore`를 설정하는 제안
  - 해당 상위 디렉터리가 작업 복사본에 존재하고 SVN 관리 중일 때만 허용

### 5.3 자동 변환 불가

- `!`로 시작하는 예외 규칙
- `**`를 포함하는 재귀 패턴
- 여러 디렉터리 깊이에 걸친 복합 glob
- 앞선 규칙을 다시 포함시키는 순서 의존 규칙
- 작업 복사본 외부를 가리키는 경로
- canonical-equivalent 관리 경로가 둘 이상인 규칙
- SVN 속성을 설정할 관리 디렉터리를 하나로 결정할 수 없는 규칙

자동 변환 불가 규칙은 삭제하거나 무시하지 않고 미리보기에 사유와 함께 남긴다.

### 5.4 이미 추적된 항목

- 가져오기 전에 해당 규칙과 일치하는 추적 항목이 있으면 안내한다.
- SVN 무시 규칙은 이미 추적 중인 항목의 변경·누락·삭제 상태를 숨기지 않는다고 명시한다.
- 추적 중인 항목을 저장소에서 제거하려면 별도의 `저장소에서도 삭제…` 흐름을 사용하도록 안내한다.
- 삭제 예약과 무시 규칙 적용을 하나의 자동 작업으로 묶지 않는다.

## 6. 화면 설계

### 6.1 변경 목록 행과 컨텍스트 메뉴

`ChangesView.statusRow`의 상태별 메뉴 구성을 별도 계산 속성 또는 작은 뷰로 분리한다.

- `missing`
  - 상태 배지: `로컬 누락 · 처리 필요`
  - 커밋 체크박스 대신 `처리 선택…` 표시
  - 파일 열기는 비활성화
  - Finder에서 상위 디렉터리 보기
  - 전체 경로 복사
  - 로컬 파일 복원
  - 저장소에서도 삭제
- `deleted`
  - 상태 배지: `삭제 예정`
  - 커밋 체크박스 표시
  - 커밋 기록
  - 전체 경로 복사
  - 삭제 취소 및 복원
- `unversioned`
  - 기존 `이 파일 무시`
  - 기존 `같은 확장자 모두 무시`

상태 의미를 문자열 비교로 판정하지 않고 `SVNStatusEntry` 계산 속성을 사용한다.

### 6.2 삭제 확인창

- 기존 레이아웃 상수 정책에 맞춰 크기를 `AppLayout.swift`에서 관리한다.
- 항목 경로를 monospaced 텍스트로 표시한다.
- 단일/다중 선택 개수를 표시한다.
- 디렉터리 포함 여부를 표시한다.
- 지금은 `삭제 예정`으로만 바뀌고 커밋해야 저장소에서 삭제된다는 점을 표시한다.
- 커밋 전에는 `삭제 취소 및 복원`이 가능하다는 점을 표시한다.
- 기본 버튼은 취소로 둔다.
- 실행 버튼 문구는 `저장소에서도 삭제로 표시`로 하고 destructive role을 사용한다.
- 작업 중에는 중복 실행과 창 닫기를 방지한다.

### 6.3 선택과 커밋 요약

- `모두 선택`은 미처리 `missing`을 제외한다.
- `삭제 예정`은 일반 커밋 대상에 포함한다.
- 커밋 영역에 `삭제 예정 N개`를 별도 요약한다.
- 오래된 UI 상태 또는 테스트용 직접 호출로 `missing`이 커밋 요청에 포함되면 실행을 중단하고 `먼저 로컬 누락 항목의 처리 방법을 선택하세요.`를 표시한다.
- 삭제 전환 성공 직후 해당 항목을 자동 선택해 사용자가 다시 체크할 필요가 없게 한다.

### 6.4 무시 규칙 관리

기존 `IgnoreRulesView`를 다음 두 영역으로 구성한다.

1. `SVN 무시 규칙`
   - 직접 설정 및 상속 규칙 표시
   - 규칙 종류, 패턴, 적용 디렉터리 표시
   - 직접 설정 규칙 제거
2. `Git 규칙 가져오기`
   - `.gitignore` 존재 여부
   - 마지막 비교 시각
   - 비교 실행 버튼
   - 변환 미리보기

미리보기 행 상태:

- `이미 적용`
- `추가 가능`
- `확인 필요`
- `변환 불가`
- `충돌`

선택 적용 버튼은 `추가 가능` 또는 사용자가 범위를 확인한 `확인 필요` 항목에만 활성화한다.

### 6.5 안내 문구

- SVN 속성 변경은 커밋 전까지 로컬 작업 복사본에만 적용된다.
- 속성 변경을 커밋하면 팀에 공유된다.
- `.gitignore` 파일 자체는 변경하지 않는다.
- 가져오기는 단방향이며 이후 `.gitignore` 변경을 자동 추적하지 않는다.
- SVN 규칙 제거가 `.gitignore`를 수정하지 않는다는 점을 명시한다.

## 7. 코드 변경 계획

### Task 1: 삭제 예약 도메인 계약

**Files:**
- Modify: `Sources/SVNCore/Models.swift`
- Modify: `Sources/SVNMac/ProjectDependencies.swift`
- Test: `Tests/SVNCoreTests/SVNWorkingCopySnapshotTests.swift`
- Test: `Tests/SVNMacTests/ProjectStoreTests.swift`

**Interfaces:**
- Produces: `SVNStatusEntry.canScheduleRepositoryDeletion`
- Produces: 삭제 예약 대상과 실행 결과 모델
- Produces: `SVNClientServing.scheduleDeletion(...)`

- [x] 일반 `missing`과 `revision == -1` 누락을 구분하는 실패 테스트를 추가한다.
- [x] `deleted`, `conflicted`, `ignored`, `unversioned`가 삭제 예약 대상이 아닌지 검증한다.
- [x] 일반 `missing`은 `isSelectableForCommit == false`, `deleted`는 `true`인지 검증한다.
- [x] `모두 선택`과 수동 커밋 선택 집합에서 미처리 `missing`이 제외되는지 검증한다.
- [x] 다중 대상 결과가 성공·실패 경로를 구분하는 모델을 정의한다.
- [x] 실제 `SVNClient`와 Demo/Fake 클라이언트가 같은 프로토콜을 구현하게 한다.

### Task 2: Unicode-safe SVN 삭제 명령

**Files:**
- Modify: `Sources/SVNCore/SVNClient.swift`
- Test: `Tests/SVNCoreTests/SVNCredentialsTests.swift`
- Test: `Tests/SVNCoreTests/SVNCanonicalAliasIntegrationTests.swift`

**Interfaces:**
- Produces: `SVNClient.scheduleDeletion(at:paths:credentials:)`

- [x] 로컬에 없는 단일 파일에 `delete --force`를 실행하는 명령 테스트를 추가한다.
- [x] 누락 디렉터리와 하위 경로 중복을 최상위 경로로 축약하는 테스트를 추가한다.
- [x] 여러 경로가 원문 targets 파일로 전달되는지 검증한다.
- [x] NFC/NFD 경로의 원문 UTF-8 표기가 보존되는지 검증한다.
- [x] 옵션처럼 보이는 파일명과 공백·개행·비 ASCII 경로를 검증한다.
- [x] 경로 충돌 또는 작업 복사본 이탈을 명령 실행 전에 거부한다.
- [x] 실제 SVN fixture에서 `missing`이 `deleted`로 바뀌는지 검증한다.
- [x] `SVNClient.commit`이 `missing`을 받으면 `delete`와 `commit`을 모두 실행하지 않고 거부하는 테스트를 추가한다.
- [x] 이미 `deleted`인 경로는 추가 `delete` 없이 `commit`만 실행하는지 검증한다.
- [x] 기존 `commit` 내부의 `missing` 자동 삭제 및 관련 롤백 분기를 제거한다.

### Task 3: ProjectStore 삭제 흐름

**Files:**
- Add: `Sources/SVNMac/ProjectStore+Deletion.swift`
- Modify: `Sources/SVNMac/ProjectStore.swift`
- Modify: `Sources/SVNMac/DemoMode.swift`
- Test: `Tests/SVNMacTests/ProjectStoreTests.swift`

**Interfaces:**
- Produces: 삭제 확인 대상 상태
- Produces: `requestDeletion(_:)`
- Produces: `confirmDeletion(_:)`
- Produces: `cancelDeletion()`

- [x] 삭제 요청이 즉시 명령을 실행하지 않고 확인 상태만 만드는지 검증한다.
- [x] 확인 후 클라이언트를 호출하고 상태를 새로고침하는지 검증한다.
- [x] 새 스냅샷에서 `deleted`가 확인된 대상만 선택 집합에 포함한다.
- [x] 선택 프로젝트 전환 또는 작업 세대 변경 시 오래된 결과를 폐기한다.
- [x] 부분 실패와 전체 실패의 상세 오류를 보존한다.
- [x] 미처리 누락을 포함한 커밋 요청을 `ProjectStore`에서도 차단하고 처리 안내를 표시한다.
- [x] 여러 누락 항목을 한 번에 확인하고 삭제 예정으로 전환한다.
- [x] DemoMode에 파일·디렉터리 삭제 예약 예시를 추가한다.

### Task 4: 삭제 확인 UI와 컨텍스트 메뉴

**Files:**
- Modify: `Sources/SVNMac/ChangesView.swift`
- Add: `Sources/SVNMac/DeletionConfirmationView.swift`
- Modify: `Sources/SVNMac/AppLayout.swift`
- Test: `Tests/SVNMacTests/ChangesViewPerformanceTests.swift`
- Test: `Tests/SVNMacTests/DetailedErrorPresentationTests.swift`
- Test: `Tests/SVNMacTests/AppLayoutTests.swift`

- [x] 일반 `missing` 행에 `로컬 누락 · 처리 필요`와 `처리 선택…`이 표시되는 테스트를 추가한다.
- [x] 일반 `missing`에는 커밋 체크박스가 표시되지 않는지 검증한다.
- [x] `저장소에서도 삭제…`과 `로컬 파일 복원…` 동작이 함께 제공되는지 검증한다.
- [x] 사라진 추가 예약에는 삭제 메뉴가 표시되지 않는지 검증한다.
- [x] 삭제 확인창의 한국어·영어 문구와 destructive role을 검증한다.
- [x] 다중 선택 및 디렉터리 경고를 표시한다.
- [x] 성공 후 `삭제 예정` 배지와 커밋 선택이 갱신되는지 검증한다.
- [x] 커밋 영역에 `삭제 예정 N개` 요약이 표시되는지 검증한다.
- [x] 기존 revert 확인 흐름과 동작이 충돌하지 않는지 검증한다.

### Task 5: SVN ignore 속성 종류 확장

**Files:**
- Modify: `Sources/SVNCore/Models.swift`
- Modify: `Sources/SVNCore/SVNXMLParser.swift`
- Modify: `Sources/SVNCore/SVNClient.swift`
- Modify: `Sources/SVNMac/ProjectDependencies.swift`
- Modify: `Sources/SVNMac/ProjectStore+Ignore.swift`
- Test: `Tests/SVNCoreTests/SVNXMLParserTests.swift`
- Test: `Tests/SVNCoreTests/SVNCredentialsTests.swift`
- Test: `Tests/SVNMacTests/ProjectStoreTests.swift`

- [x] `svn:ignore`와 `svn:global-ignores`를 구분해 파싱하는 실패 테스트를 추가한다.
- [x] 직접 규칙과 상속 규칙을 구분한다.
- [x] 기존 속성 값을 덮어쓰지 않고 규칙을 추가·제거한다.
- [x] 빈 규칙 목록에서만 해당 속성을 삭제한다.
- [x] 상속 규칙의 실제 속성 소유 위치를 표시하고 현재 작업 복사본에서 직접 제거할 수 없으면 비활성화한다.
- [x] 속성 변경 후 ignore 목록과 변경 상태를 함께 새로고침한다.

### Task 6: `.gitignore` 파서와 변환기

**Files:**
- Add: `Sources/SVNCore/GitIgnoreParser.swift`
- Add: `Sources/SVNCore/GitIgnoreImporter.swift`
- Test: `Tests/SVNCoreTests/GitIgnoreParserTests.swift`
- Test: `Tests/SVNCoreTests/GitIgnoreImporterTests.swift`

**Interfaces:**
- Produces: `[GitIgnoreRule]`
- Produces: `[IgnoreImportDisposition]`

- [x] 빈 줄, 주석, 이스케이프, 디렉터리 전용, 루트 고정, 예외 규칙을 파싱한다.
- [x] 정확한 이름과 단순 확장자 glob을 변환한다.
- [x] 루트 기준 경로를 해당 상위 관리 디렉터리의 local ignore로 변환한다.
- [x] 범용 단순 이름을 global ignore 제안으로 분류한다.
- [x] `!`, `**`, 순서 의존 규칙을 변환 불가로 남긴다.
- [x] 존재하지 않거나 관리되지 않은 속성 대상 디렉터리를 거부한다.
- [x] 기존 SVN 규칙과의 중복·충돌을 판정한다.
- [x] 추적 항목과 일치하는 규칙에 경고를 추가한다.

### Task 7: Git 규칙 비교 및 선택 적용 UI

**Files:**
- Modify: `Sources/SVNMac/IgnoreRulesView.swift`
- Modify: `Sources/SVNMac/ProjectStore+Ignore.swift`
- Modify: `Sources/SVNMac/ProjectStore.swift`
- Modify: `Sources/SVNMac/AppLayout.swift`
- Test: `Tests/SVNMacTests/ProjectStoreTests.swift`
- Test: `Tests/SVNMacTests/DetailedErrorPresentationTests.swift`
- Test: `Tests/SVNMacTests/AppLayoutTests.swift`

- [x] `.gitignore`가 없을 때 명확한 빈 상태를 표시한다.
- [x] 비교 결과의 적용 위치, 패턴, 종류, 상태를 표시한다.
- [x] 변환 불가와 충돌 항목을 선택할 수 없게 한다.
- [x] 적용 범위가 넓은 global ignore에 추가 확인을 요구한다.
- [x] 선택 적용 시 SVN 속성만 변경하고 `.gitignore`는 수정하지 않는다.
- [x] 적용 후 변경 디렉터리 속성을 커밋해야 한다는 안내를 표시한다.
- [x] 규칙 제거가 `.gitignore`에 역반영되지 않는다는 설명을 유지한다.

### Task 8: 통합 검증과 문서화

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Verify: Tasks 1-7의 모든 변경 파일

- [x] 실제 SVN fixture에서 누락 파일·누락 디렉터리 삭제 예약과 revert를 검증한다.
- [x] 미처리 누락을 직접 커밋하려 해도 저장소가 변경되지 않는지 검증한다.
- [x] `로컬 누락 → 삭제 예정 → 커밋 완료` 상태 전이를 검증한다.
- [x] 삭제 예약 항목을 커밋하고 새 작업 복사본 업데이트 결과를 검증한다.
- [x] ignore 속성 변경을 커밋하고 다른 작업 복사본에서 상속되는지 검증한다.
- [x] `.gitignore` 가져오기 지원·미지원 패턴 전체 회귀 테스트를 실행한다.
- [x] `swift test` 전체를 실행한다.
- [x] `swift build --product SVNMac`을 실행한다.
- [x] `git diff --check`와 `git status --short`로 범위를 확인한다.
- [ ] 앱 패키징과 코드 서명 검증은 기능 승인 후 별도 배포 단계에서 수행한다.

## 8. 커밋 분리

1. `feat: 로컬 누락 처리와 명시적 저장소 삭제 지원`
   - Core 명령, 커밋 경계, 모델, ProjectStore, 처리 선택 UI, 확인창, 테스트
2. `feat: SVN 전역 무시 규칙 관리 확장`
   - local/global 속성 모델, 파서, 관리 화면, 테스트
3. `feat: Git 무시 규칙 선택 가져오기 추가`
   - `.gitignore` 파서, 변환기, 미리보기, 선택 적용, 테스트
4. `docs: 로컬 누락 처리와 무시 규칙 가져오기 안내`
   - README, CHANGELOG, 사용 안내

각 커밋은 관련 파일만 명시적으로 스테이징한다. 기능 구현 중 사용자가 만든 기존 변경과 다른 기능의 스테이징은 포함하지 않는다.

## 9. 완료 기준

- 일반 `로컬 누락` 항목은 `처리 필요`로 표시되고 커밋 체크박스와 `모두 선택`에서 제외된다.
- 사용자가 `로컬 파일 복원` 또는 `저장소에서도 삭제`를 명시적으로 선택할 수 있다.
- `저장소에서도 삭제` 처리 후 상태가 `삭제 예정`으로 갱신되고 기존 커밋 화면에 자동 선택된다.
- `삭제 예정`을 커밋하면 저장소의 새 리비전에서 삭제된다.
- `삭제 취소 및 복원`을 실행하면 저장소 기준 파일이 복원된다.
- UI를 우회해도 `missing`을 직접 커밋할 수 없고 `SVNClient.commit`이 암묵적으로 삭제 예약하지 않는다.
- 사라진 추가 예약과 경로 충돌 항목에는 삭제 예약을 제공하지 않는다.
- SVN 명령에서 한글 NFC/NFD 원문 경로가 보존된다.
- `svn:ignore`와 `svn:global-ignores`를 구분해 조회·추가·제거할 수 있다.
- `.gitignore`를 수정하지 않고 안전한 규칙만 SVN 속성 변경 제안으로 가져올 수 있다.
- 지원하지 않는 규칙은 이유를 표시하며 자동 적용하지 않는다.
- 이미 추적된 항목은 ignore로 숨길 수 없다는 안내가 유지된다.
- 삭제 및 속성 변경은 사용자의 명시적 SVN 커밋 전까지 저장소에 반영되지 않는다.
- 전체 Swift 테스트와 실제 SVN 통합 테스트가 통과한다.
