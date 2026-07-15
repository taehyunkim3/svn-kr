# SVN Mac

여러 SVN 로컬 작업 폴더를 한곳에서 관리하기 위한 가벼운 macOS 네이티브 앱입니다. 복잡한 SVN 명령을 외우지 않아도 변경 확인부터 업데이트, 커밋 기록 조회, 선택 커밋까지 처리하는 것을 목표로 합니다. 배포 앱에는 SVN CLI와 필요한 라이브러리가 포함되므로 사용자가 Homebrew나 SVN을 별도로 설치할 필요가 없습니다.

## 현재 제공하는 기능

- 저장소 URL과 로컬 경로를 입력해 체크아웃
- 여러 SVN 로컬 작업 폴더 등록 및 전환
- 로컬 작업 폴더별 SVN 사용자명과 macOS Keychain 비밀번호 관리
- 변경 파일 상태 확인과 텍스트 diff 보기
- 변경 파일을 선택해 커밋 (`unversioned` 파일은 자동 `svn add`)
- 업데이트하지 않아도 서버의 최근 50개 커밋과 내 로컬 작업 폴더 리비전 위치 확인
- 작성자, 정확한 시간, 변경 경로, 사용자 정의 리비전 속성을 포함한 상세 커밋 기록
- 서버 커밋, 내 로컬 기준, 미커밋 변경의 관계를 보여주는 SVN 타임라인 그래프
- 설정에서 커밋 시각 표시 시간대 변경 (기본값 KST)
- 모든 작업 버튼의 역할을 설명하는 hover 도움말
- 로컬 작업 폴더 업데이트 및 새로고침
- 기존 SVN 인증 캐시와 macOS Keychain 사용 (앱에는 비밀번호를 저장하지 않음)

## 실행

소스에서 실행하려면 macOS 14 이상, Xcode 16 이상, SVN CLI가 필요합니다. `dist/SVN Mac.app`을 사용하는 일반 사용자는 Xcode, Homebrew, SVN이 필요하지 않습니다.

```bash
swift run SVNMac
```

테스트와 릴리스 앱 번들은 다음처럼 만들 수 있습니다.

```bash
swift test
./scripts/package-app.sh
open 'dist/SVN Mac.app'
```

생성된 앱은 `dist/SVN Mac.app`, 공유용 압축 파일은 `dist/SVN-Mac-버전-아키텍처.zip`에 있습니다. 패키징 스크립트는 빌드 Mac에 설치된 SVN과 비시스템 동적 라이브러리를 앱 내부에 포함하고 라이선스 파일도 함께 복사합니다. 현재 기본값은 로컬 실행용 ad-hoc 서명입니다.

Developer ID가 있다면 다음처럼 서명할 수 있습니다. 이후 `notarytool`로 공증하고 티켓을 첨부해야 일반 사용자가 별도 보안 예외 없이 실행할 수 있습니다.

```bash
CODE_SIGN_IDENTITY='Developer ID Application: 회사명 (TEAMID)' ./scripts/package-app.sh
```

현재 패키지는 빌드 Mac과 동일한 CPU 아키텍처용입니다. Apple Silicon에서 빌드하면 Apple Silicon용 SVN이 포함됩니다.

## 사용 방법

1. 왼쪽 아래 `+` 또는 `⌘O`로 저장소 URL과 체크아웃할 로컬 폴더를 입력합니다.
   이미 체크아웃된 폴더는 추가 창의 `기존 로컬 폴더 등록…`으로 등록할 수 있습니다.
2. `변경 사항`에서 파일을 눌러 diff를 확인하고 커밋할 파일만 체크합니다.
3. 메시지를 입력한 뒤 `선택 항목 커밋`을 누릅니다.
4. `커밋 기록`에서 다른 사용자를 포함한 최근 서버 이력을 확인합니다.

프로젝트 상단의 `인증 설정`에서 로컬 작업 폴더마다 서로 다른 사용자명과 비밀번호를 지정할 수 있습니다. 비밀번호는 앱 설정이나 Git에 기록하지 않고 macOS Keychain에 프로젝트별로 저장하며, SVN 명령에는 표준 입력으로만 전달합니다. 서버 인증서 승인이 아직 저장되지 않았다면 터미널에서 한 번 `svn update --username 계정명`으로 인증서를 승인한 뒤 앱을 사용하세요.

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
- `scripts/embed-svn.sh`: SVN CLI, 의존 라이브러리, 오픈소스 라이선스 포함
