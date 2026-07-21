# macOS 14 고정 SVN 런타임 설계

## 목표

빌드 Mac의 Homebrew 설치 상태와 macOS 버전에 영향을 받지 않는 SVN 1.14.5 arm64 런타임을 만든다. 앱과 모든 내장 Mach-O는 macOS 14에서 실행 가능해야 하며, 릴리스 버전은 0.5.7, 빌드 번호는 18로 올린다.

## 아키텍처

새 `scripts/build-svn-runtime.sh`가 버전과 SHA-256을 고정한 공식 소스만 사용해 별도의 빌드 루트에서 의존성을 컴파일한다. SQLite 3.51.0, APR 1.7.6, APR-util 1.6.3, Serf 1.3.10, OpenSSL 3.6.3, Expat 2.7.1, LZ4 1.10.0, utf8proc 2.11.3과 SVN 1.14.5를 `MACOSX_DEPLOYMENT_TARGET=14.0`, arm64로 빌드한다.

제3자 라이브러리는 가능한 한 정적으로 SVN 헬퍼에 연결한다. 최종 런타임은 `bin/svn`, 라이선스, 빌드 매니페스트만 노출하고 Homebrew 경로를 포함하지 않는다. macOS의 안정된 시스템 ABI인 libSystem, Security/CoreFoundation 같은 플랫폼 프레임워크만 동적 의존성으로 허용한다.

`scripts/embed-svn.sh`는 릴리스 시 `SVN_RUNTIME_DIR`의 검증된 결과만 앱에 복사한다. 임의의 `command -v svn`은 개발용 명시적 opt-in에서만 허용하고 릴리스 패키징에는 사용하지 않는다. SQLite는 고정 런타임 빌드 단계에서 해결하므로 앱 조립 중 즉석 컴파일하지 않는다.

## 검증

- 소스 아카이브는 다운로드 또는 캐시 사용 전후에 고정 SHA-256과 비교한다.
- `vtool`로 SVN과 내장 dylib의 최소 OS가 14.0 이하인지 검사한다.
- `otool` 결과에 `/opt/homebrew`, `/usr/local`, 빌드 스테이징 경로가 남으면 실패한다.
- SVN verbose 출력의 SQLite, APR, APR-util, utf8proc, LZ4 컴파일/실행 버전을 검사한다.
- 실제 런타임으로 로컬 저장소 생성, 체크아웃, 상태 조회, 추가, 커밋을 수행한다.
- 앱 패키징 후 deep 서명, ZIP 무결성, 버전, 최소 OS를 다시 검사한다.

## 오류 처리와 유지보수

지원 버전을 변경하려면 매니페스트의 URL과 체크섬을 함께 갱신해야 한다. 다운로드 실패, 체크섬 불일치, 빌드 도구 누락, 잘못된 최소 OS 또는 외부 경로 누출은 패키징 전 단계에서 명확한 오류로 중단한다. 빌드 캐시와 결과물은 Git에 포함하지 않는다.

## 범위

이번 릴리스는 Apple Silicon arm64와 macOS 14 이상을 대상으로 한다. Intel 및 Universal 2는 동일 런타임을 x86_64로 별도 빌드한 뒤 추가하는 후속 범위다. Developer ID 공증 자동화는 포함하지 않는다.
