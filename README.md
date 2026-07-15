# SVN Mac

여러 SVN 작업 복사본을 한곳에서 관리하기 위한 가벼운 macOS 네이티브 앱입니다. 복잡한 SVN 명령을 외우지 않아도 변경 확인부터 업데이트, 커밋 기록 조회, 선택 커밋까지 처리하는 것을 목표로 합니다.

## 현재 제공하는 기능

- 저장소 URL과 로컬 경로를 입력해 체크아웃
- 여러 SVN 작업 복사본 등록 및 전환
- 작업 복사본별 SVN 사용자명과 macOS Keychain 비밀번호 관리
- 변경 파일 상태 확인과 텍스트 diff 보기
- 변경 파일을 선택해 커밋 (`unversioned` 파일은 자동 `svn add`)
- 최근 50개 커밋의 리비전, 작성자, 시간, 메시지 확인
- 작업 복사본 업데이트 및 새로고침
- 기존 SVN 인증 캐시와 macOS Keychain 사용 (앱에는 비밀번호를 저장하지 않음)

## 실행

macOS 14 이상, Xcode 16 이상, SVN CLI가 필요합니다.

```bash
swift run SVNMac
```

테스트와 릴리스 앱 번들은 다음처럼 만들 수 있습니다.

```bash
swift test
./scripts/package-app.sh
open 'dist/SVN Mac.app'
```

생성된 앱은 `dist/SVN Mac.app`에 있습니다. 현재 패키징은 로컬 실행용 ad-hoc 서명입니다. 다른 사용자에게 배포하려면 Apple Developer ID 서명과 공증을 추가해야 합니다.

## 사용 방법

1. 왼쪽 아래 `+` 또는 `⌘O`로 저장소 URL과 체크아웃할 로컬 폴더를 입력합니다.
   이미 체크아웃된 폴더는 추가 창의 `기존 작업 복사본 등록…`으로 등록할 수 있습니다.
2. `변경 사항`에서 파일을 눌러 diff를 확인하고 커밋할 파일만 체크합니다.
3. 메시지를 입력한 뒤 `선택 항목 커밋`을 누릅니다.
4. `커밋 기록`에서 다른 사용자를 포함한 최근 서버 이력을 확인합니다.

프로젝트 상단의 `인증 설정`에서 작업 복사본마다 서로 다른 사용자명과 비밀번호를 지정할 수 있습니다. 비밀번호는 앱 설정이나 Git에 기록하지 않고 macOS Keychain에 프로젝트별로 저장하며, SVN 명령에는 표준 입력으로만 전달합니다. 서버 인증서 승인이 아직 저장되지 않았다면 터미널에서 한 번 `svn update --username 계정명`으로 인증서를 승인한 뒤 앱을 사용하세요.

## 다음 단계

- Git `master` 및 `origin/master` 일치 여부 안전 점검
- `.gitignore`와 `svn:global-ignores` 동기화 미리보기
- 체크아웃 화면과 저장소 URL 관리
- 충돌 해결 보조 및 파일별 커밋 기록
- Developer ID 서명, 공증, 자동 업데이트가 포함된 배포 파이프라인

## 구조

- `Sources/SVNMac`: SwiftUI 화면과 프로젝트 목록 상태
- `Sources/SVNCore`: `svn` 프로세스 실행, XML 상태/로그 파싱
- `Tests/SVNCoreTests`: SVN XML 응답 파서 테스트
- `scripts/package-app.sh`: 로컬용 `.app` 번들 생성
