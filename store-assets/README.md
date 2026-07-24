# SVN KR App Store Assets

## 제출 파일

• 앱 아이콘 원본: `icon/AppIcon-1024.png`
• 편집 가능한 아이콘 원본: `icon/AppIcon.svg`
• 앱 번들 아이콘: `../Resources/AppIcon.icns`
• 한국어 Mac 스크린샷: `screenshots/ko/*.png` (2880×1800)
• 한국어·영어 메타데이터: `metadata/ko.md`, `metadata/en.md`
• 개인정보 처리방침 초안: `metadata/privacy-policy-*.md`
• TestFlight 심사 안내와 답변 초안: `metadata/beta-review-en.md`

## 스크린샷 업로드 순서

1. `01-timeline-overview.png`
2. `02-selective-commit.png`
3. `03-working-copy-files.png`
4. `04-repository-locks.png`
5. `05-project-credentials.png`
6. `06-add-repository.png`

## 재생성

```bash
./scripts/store-assets/build-icon.sh
./scripts/store-assets/build-screenshots.sh
```

스크린샷은 실제 SVN KR 화면으로 구성했으며 데모 저장소명과 데모 로컬 경로만 포함합니다.

영어 스크린샷은 영어 UI로 동일한 세 장을 다시 촬영한 뒤 별도 현지화 세트로 제작하는 것이 좋습니다. 한국어를 기본 언어로 먼저 제출하는 경우 현재 한국어 세트만으로 필수 스크린샷 요구사항을 충족합니다.

## 제출 전 남은 외부 항목

• 배포 국가에서 프랑스 제외 (`ITSAppUsesNonExemptEncryption = NO` 기준)
• App Store Connect 앱 레코드와 SKU 생성
• 지원 URL 공개
• 개인정보 처리방침을 공개 URL에 게시
• 가격과 배포 국가 설정
• 연령 등급 설문 작성
• 앱 개인정보 항목 작성
• Developer ID가 아닌 Mac App Store 배포 인증서와 프로비저닝 프로파일로 빌드
• App Sandbox entitlement와 포함된 SVN helper 검증
• 심사용 연락처와 테스트 안내 작성
