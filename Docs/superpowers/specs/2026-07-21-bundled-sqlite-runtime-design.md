# 내장 SQLite 런타임 설계

## 목표

배포 앱의 내장 SVN이 대상 Mac의 시스템 SQLite 버전에 의존하지 않도록 SVN의 컴파일 버전과 일치하는 SQLite 3.51.0을 앱에 포함한다. 앱 버전은 0.5.6, 빌드 번호는 17로 올린다.

## 선택한 방식

`scripts/embed-svn.sh`가 SVN의 `--version --verbose` 출력에서 컴파일 SQLite 버전을 확인하고, 같은 버전의 SQLite amalgamation 소스를 준비해 `MACOSX_DEPLOYMENT_TARGET=14.0`으로 동적 라이브러리를 빌드한다. 빌드한 라이브러리는 `Contents/Frameworks/libsqlite3.dylib`에 넣고, SQLite를 참조하는 내장 바이너리의 `/usr/lib/libsqlite3.dylib` 링크를 `@loader_path` 상대 경로로 바꾼다.

시스템 라이브러리를 일반적으로 내장하지 않는 기존 원칙은 유지하며 SQLite만 명시적으로 예외 처리한다. SQLite 소스는 패키징 때마다 임의 최신 버전을 받지 않고, 버전별 URL과 SHA-256을 고정한 매니페스트로 검증한다. 이미 검증된 소스 ZIP을 지정할 수 있는 환경 변수도 제공해 반복 빌드와 오프라인 패키징을 지원한다.

## 검증 및 오류 처리

- 지원하지 않는 SVN 컴파일 SQLite 버전이면 다운로드 전에 명확히 실패한다.
- 소스 ZIP 체크섬이 다르면 컴파일하지 않고 실패한다.
- 내장 SVN의 SQLite 링크가 번들 상대 경로가 아니면 패키징을 실패시킨다.
- 내장 SVN의 `--version --verbose`에서 SQLite 컴파일 버전과 실행 버전이 같지 않으면 실패시킨다.
- 내장 SQLite의 최소 macOS 버전이 14.0을 넘으면 실패시킨다.
- 모든 dylib과 SVN 헬퍼를 기존 순서대로 재서명하고 앱 전체 서명을 검증한다.

## 테스트

패키징 스크립트의 버전 추출, 지원 버전 매핑, 체크섬 검증, SQLite 링크 예외 처리를 쉘 회귀 테스트로 먼저 고정한다. 이후 `swift test`, 실제 앱 패키징, `otool`, `vtool`, `svn --version --verbose`, `codesign`, ZIP 목록 검사를 수행한다.

## 범위 제한

이번 릴리스는 보고된 SQLite 컴파일/실행 버전 불일치를 제거한다. 현재 빌드 Mac의 Homebrew SVN 자체가 macOS 26 최소 대상으로 만들어진 문제는 별도 재현 가능한 SVN 툴체인 작업으로 남는다. 따라서 0.5.6 패키지는 SQLite 런타임은 macOS 14 호환으로 만들지만, 전체 SVN 헬퍼의 실질 지원 OS는 사용한 `SVN_EXECUTABLE`의 최소 OS에 의해 제한된다.
