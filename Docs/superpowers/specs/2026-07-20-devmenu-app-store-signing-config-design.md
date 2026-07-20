# devmenu App Store 서명 기본값 설계

## 목표

devmenu에서 `scripts/package-app-store.sh`를 환경변수 없이 실행해도 개인용 App Store 서명 설정을 자동으로 적용해 0.5.5 PKG를 생성한다.

## 결정

- 개인용 저장소이므로 로컬 프로비저닝 프로파일 경로와 인증서 이름을 추적 설정 파일로 커밋한다.
- 설정 파일은 `scripts/app-store-signing.defaults.zsh`로 분리한다.
- `scripts/package-app-store.sh`가 기본값 파일을 읽은 뒤 기존 `scripts/package-app.sh`를 App Store 모드로 실행한다.
- 호출자가 `CODE_SIGN_IDENTITY`, `PROVISIONING_PROFILE`, `INSTALLER_SIGN_IDENTITY`를 직접 전달한 경우 해당 값을 우선한다.

## 설정 흐름

1. `package-app-store.sh`가 저장소 루트를 계산한다.
2. `app-store-signing.defaults.zsh`를 읽는다.
3. 각 기본값은 대응 환경변수가 비어 있을 때만 적용된다.
4. 프로비저닝 프로파일이 실제 파일인지 확인한다.
5. 기존 `package-app.sh`에 `DISTRIBUTION=app-store`를 전달한다.

인증서 개인 키나 비밀번호는 파일에 저장하지 않는다. 커밋되는 값은 인증서의 공개 표시 이름과 로컬 프로파일 경로뿐이다.

## 오류 처리

- 기본값 파일이 없으면 어떤 파일이 필요한지 명시해 종료한다.
- 프로파일 경로가 존재하지 않으면 해당 경로를 포함한 명확한 오류를 출력한다.
- 직접 전달된 환경변수는 기본값으로 덮어쓰지 않는다.
- 인증서 유효성, App ID 일치, 코드 서명과 PKG 서명 검증은 기존 패키징 스크립트가 계속 담당한다.

## 검증

- shell 구문 검사로 두 스크립트가 유효한지 확인한다.
- 환경변수를 비운 상태에서 `package-app-store.sh`를 실행해 devmenu와 같은 조건으로 PKG가 생성되는지 확인한다.
- 생성된 PKG에 `pkgutil --check-signature`를 실행한다.
- PKG를 풀어 내부 앱에 `codesign --verify --deep --strict`를 실행한다.
- 내부 앱의 application identifier와 App Sandbox entitlement를 확인한다.
- 직접 환경변수를 전달했을 때 기본값보다 우선하는지 별도 셸 회귀 테스트로 확인한다.

## 범위 제외

- 프로비저닝 프로파일 자동 다운로드 또는 갱신
- 여러 팀 인증서 중 자동 선택
- App Store Connect 업로드
- 인증서 또는 개인 키를 저장소에 포함하는 작업
