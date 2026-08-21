# 윈도우 한글 파일명 정규화 설계

## 문제와 증상

macOS에서 새로 추가한 한글 파일이나 폴더의 이름이 SVN 저장소에 자모 분리 형태로 기록되면 윈도우에서는 `ㅎㅏㄴㄱㅡㄹ`처럼 낱개 자모로 보인다. 실제 SVN 1.14.5와 APFS, HFS+ 볼륨에서 확인한 결과, 이 문제는 화면 표시가 아니라 디스크와 저장소에 기록된 파일명 UTF-8 바이트의 차이에서 발생한다.

이번 범위는 새 SVN 경로를 커밋할 때 디스크 이름과 저장소 이름을 NFC로 맞추고, 이를 보존할 수 없는 볼륨의 작업 폴더에 경고하는 것이다. 이미 저장소에 자모 분리 형태로 기록된 경로는 자동으로 바꾸지 않는다.

## 원인 분석

검증된 원인 사슬은 다음과 같다.

1. APFS는 파일 생성 시 전달된 파일명 바이트를 그대로 보존한다.
2. NFD로 만든 한글 파일명은 디스크에도 NFD 바이트로 남는다.
3. `svn status`는 디스크에서 읽은 NFD 원문 경로를 보고한다.
4. 그 경로를 그대로 `svn add`하면 저장소에도 NFD 파일명이 기록된다.
5. 윈도우는 이 이름을 NFC로 정규화하지 않으므로 한글 음절 대신 `ㅎㅏㄴㄱㅡㄹ`처럼 분리된 자모를 렌더링한다.

따라서 저장소에 추가하기 전에 실제 디스크의 신규 파일명 바이트를 NFC로 바꿔야 한다.

## 설계 제약

### 디스크 이름 변경이 먼저여야 한다

디스크 파일명은 그대로 둔 채 `svn add`에 NFC 문자열만 넘기면 추가 예약 자체는 만들어지지만 커밋은 다음 오류로 거부된다.

```text
svn: E155010: '...' is scheduled for addition, but is missing
```

SVN이 예약한 NFC 경로와 디스크의 NFD 경로가 서로 다른 원문 바이트이기 때문이다. 문자열 치환만으로는 해결할 수 없으며, 반드시 디스크 rename이 선행되어야 한다.

APFS에서는 `rename(NFD 이름 -> NFC 이름)`만으로 실제 저장 바이트가 NFC로 바뀐다. 중간 임시 이름을 거칠 필요가 없다.

### NFD를 강제하는 볼륨은 앱에서 복구할 수 없다

HFS+는 파일명을 항상 NFD로 저장한다. NFC 이름으로 새 파일을 만들어도 디렉터리 열거 결과는 NFD이고, NFC로 rename해도 다시 NFD로 저장된다.

이 볼륨의 작업 사본에서 저장소가 NFC 경로를 갖고 있으면 `svn status`는 같은 이름처럼 보이는 unversioned와 missing 항목을 함께 보고한다.

```text
?       한글파일.txt
!       한글파일.txt
```

두 줄은 화면에서는 같아 보여도 파일명 원문 바이트가 다르다. 앱 수준의 rename으로 고칠 수 없으므로 자동 수정하지 않고, 해당 작업 폴더가 있는 디스크에 대해 경고만 표시한다.

### 이미 버전관리된 경로의 원문을 보존한다

이미 버전관리된 경로는 저장소에 기록된 원문 바이트를 유지해야 한다. 신규 파일의 조상인 버전관리된 NFD 디렉터리까지 NFC로 rename하면 커밋 뒤 작업 사본에 unversioned와 missing 항목이 함께 남는 회귀가 실제로 발생했다.

따라서 가장 깊은 버전관리 조상까지는 원문 경로를 그대로 사용하고, 그 아래의 신규 경로 구성 요소만 NFC로 바꾼다. 이 경계는 `realSVNCommitIntoVersionedNFDDirectoryLeavesWorkingCopyClean` 통합 테스트로 고정한다.

### 판정과 검증은 문자열이 아니라 바이트로 한다

> **회귀 방지 규칙:** Swift `String` 동등성은 NFC와 NFD를 같은 값으로 취급한다. 정규화 형태 판정, rename 결과 검증, 테스트 기대값은 반드시 `Data(문자열.utf8)` 바이트로 비교한다. `String`끼리 비교하면 NFC/NFD가 달라도 테스트가 통과해 회귀를 잡지 못한다.

## 구현된 것

### 업로드 정규화

`SVNClient.commit`은 변경 명령 직전에 작업 사본 스냅샷을 다시 읽고, 선택 경로 중 `unversioned`인 신규 경로만 `SVNPathNormalization.normalizeNewPaths`에 전달한다.

- 신규 경로는 얕은 경로부터 처리한다.
- `versionedPathsByCanonicalKey`에서 가장 깊은 버전관리 조상을 찾고 그 조상 구성 요소는 원문 그대로 보존한다.
- 새 경로 구성 요소는 NFC 목적지로 `rename(2)`를 호출한다. rename 뒤 디렉터리를 다시 읽고 NFC UTF-8 바이트가 실제로 남았을 때만 성공으로 인정한다.
- 선택한 신규 디렉터리의 하위 파일과 폴더도 재귀적으로 정규화한다. 심볼릭 링크 자체는 처리할 수 있지만 링크를 따라 하위로 내려가지는 않는다.
- 디스크 rename이 확인되면 작업 사본 스냅샷과 선택 경로를 다시 해석한 뒤 `svn add --parents`와 commit을 실행한다.
- NFC 목적지가 이미 별도 엔트리로 존재하거나 rename 뒤에도 NFC 바이트가 남지 않으면 문자열만 바꾸지 않는다. 실제 디스크에 남은 원문 경로로 기존 커밋 흐름을 계속한다.

이 흐름은 신규 경로의 저장소 표기만 NFC로 만들며, 이미 버전관리된 파일과 디렉터리의 표기는 변경하지 않는다.

### NFD 강제 볼륨 감지와 경고

`SVNVolumeNormalizationProbe`는 작업 폴더 안에 NFC 한글을 포함한 임시 파일을 POSIX `open`으로 생성하고, `readdir`로 읽은 실제 엔트리의 UTF-8 바이트를 NFC/NFD 기대값과 비교한다. 남아 있던 프로브 파일을 먼저 정리하고 현재 프로브 파일도 검사 후 삭제한다.

확정된 결과는 표준화한 작업 폴더 경로별로 캐시하지만, 생성이나 열거에 실패한 알 수 없는 결과는 캐시하지 않는다. `ProjectStore`는 저장된 프로젝트 복원, 체크아웃 완료, 작업 폴더 추가, 작업 폴더 위치 변경 때 메인 액터 밖에서 프로브를 실행한다. 등록된 동일 프로젝트 경로에 대해 결과가 `false`로 확정된 경우에만 사이드바의 파일명 경고 배지와 프로젝트 상단의 APFS 사용 권고를 표시한다.

## 아직 구현되지 않은 것

이미 저장소에 NFD로 올라간 기존 경로를 서버사이드 `svn move`로 NFC 이름으로 바꾸는 복구 기능은 이번 범위에 포함하지 않는다. 이 기능은 별도 작업으로 진행 중이며 상세 설계도 그 작업에서 다룬다.

## 회귀 방지 테스트

`Tests/SVNCoreTests/SVNPathNormalizationTests.swift`

- `pathNormalizationRenamesNFDFileToNFCBytes`
- `pathNormalizationRecursivelyRenamesNFDDirectoryAndChild`
- `pathNormalizationLeavesNFCPathUntouched`
- `pathNormalizationReportsExistingDistinctNFCTarget`
- `pathNormalizationPreservesVersionedNFDAncestor`
- `pathNormalizationReadsEachNewDirectoryAtMostTwice`

`Tests/SVNCoreTests/SVNUnicodeCommitIntegrationTests.swift`

- `realSVNCommitStoresNewNFDFileAsNFC`
- `realSVNCommitRecursivelyStoresNFDDirectoryAndChildAsNFC`
- `realSVNCommitPreservesExistingVersionedNFDPathWhileNormalizingNewPath`
- `realSVNCommitIntoVersionedNFDDirectoryLeavesWorkingCopyClean`

`Tests/SVNCoreTests/SVNCanonicalAliasIntegrationTests.swift`

- `realSVNCleansMissingAdditionAndRecursivelyCommitsNFDDirectoryAsNFC`

`Tests/SVNCoreTests/SVNVolumeNormalizationProbeTests.swift`

- `normalizationProbePreservesNFCAndRemovesTemporaryFile`
- `normalizationProbeCachesResultByWorkingCopyPath`
- `normalizationProbeDoesNotCacheUnknownResult`
- `normalizationProbeRemovesStaleProbeFilesBeforeRunning`
- `normalizationProbeDetectsHFSPlusWhenDiskImagesAreAvailable`

`Tests/SVNMacTests/ProjectStoreTests.swift`

- `restoredProjectsExposeOnlyConfirmedFilenameNormalizationWarnings`
