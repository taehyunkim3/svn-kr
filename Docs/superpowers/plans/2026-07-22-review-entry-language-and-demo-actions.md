# Review Entry Language and Demo Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an extensible language menu to the first-run repository sheet, keep sample-project entry secondary, and make the demo-exit action unmistakable.

**Architecture:** Continue using `AppSettings.languageKey` as the single persisted language source. `AppLanguage` owns native language names, `AddRepositoryView` renders all cases through a menu, and `ContentView` applies demo-only toolbar styling without changing the existing store-switching flow.

**Tech Stack:** Swift 6.2, SwiftUI for macOS 14, Swift Testing, Swift Package Manager, shell packaging scripts.

## Global Constraints

- The language control label is localized as `언어` or `Language` and exposes every `AppLanguage.allCases` entry.
- `샘플 프로젝트 둘러보기` / `Browse Sample Project` remains a normal bordered secondary action without an accent tint.
- `데모 종료` / `Exit Demo` is always textual and uses an orange `borderedProminent` style.
- Keep the existing add-repository sheet minimum size and container structure; do not add layout numbers outside `Sources/SVNMac/AppLayout.swift`.
- Preserve `com.mrdevello.svnmac` and the internal executable name `SVNMac`.

---

### Task 1: Extensible first-run language menu

**Files:**
- Modify: `Sources/SVNMac/AppSettings.swift`
- Modify: `Sources/SVNMac/RepositoryDialogs.swift`
- Modify: `Tests/SVNMacTests/AppReviewReadinessTests.swift`

**Interfaces:**
- Consumes: `AppSettings.languageKey`, `AppLanguage.allCases`, and the existing `appLanguage` environment value.
- Produces: `AppLanguage.displayName: String` and an `@AppStorage`-backed language menu in `AddRepositoryView`.

- [ ] **Step 1: Write failing language metadata and menu tests**

Add tests that expect native language names and source wiring:

```swift
@Test func supportedLanguagesExposeNativeDisplayNames() {
    #expect(AppLanguage.allCases.map(\.displayName) == ["한국어", "English"])
}

@Test func firstRunRepositorySheetExposesExtensibleLanguageMenu() throws {
    let source = try String(
        contentsOf: repositoryRoot().appendingPathComponent("Sources/SVNMac/RepositoryDialogs.swift"),
        encoding: .utf8
    )

    #expect(source.contains("@AppStorage(AppSettings.languageKey)"))
    #expect(source.contains("ForEach(AppLanguage.allCases"))
    #expect(source.contains("appLanguage.text(\"언어\", \"Language\")"))
    #expect(source.contains("systemImage: \"globe\""))
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter AppReviewReadinessTests`

Expected: compilation fails because `AppLanguage.displayName` does not exist and the source wiring assertions are not satisfied.

- [ ] **Step 3: Implement native language names**

Add to `AppLanguage`:

```swift
var displayName: String {
    switch self {
    case .korean: "한국어"
    case .english: "English"
    }
}
```

- [ ] **Step 4: Implement the first-run language menu**

Add `@AppStorage(AppSettings.languageKey)` to `AddRepositoryView`. Replace the heading `VStack` with an `HStack` that keeps the existing title and description on the left and adds this menu on the right:

```swift
Menu {
    ForEach(AppLanguage.allCases, id: \.self) { language in
        Button {
            languageIdentifier = language.rawValue
        } label: {
            if language.rawValue == languageIdentifier {
                Label(language.displayName, systemImage: "checkmark")
            } else {
                Text(language.displayName)
            }
        }
    }
} label: {
    Label(appLanguage.text("언어", "Language"), systemImage: "globe")
}
.fixedSize()
```

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run: `swift test --filter AppReviewReadinessTests`

Expected: all `AppReviewReadinessTests` pass.

### Task 2: Secondary sample entry and prominent demo exit

**Files:**
- Modify: `Sources/SVNMac/ContentView.swift`
- Modify: `Sources/SVNMac/RepositoryDialogs.swift`
- Modify: `Tests/SVNMacTests/AppReviewReadinessTests.swift`

**Interfaces:**
- Consumes: existing `onBrowseDemo` and `onExitDemo` closures.
- Produces: footer ordering `register → spacer → sample → cancel → checkout` and an orange text-only demo exit button.

- [ ] **Step 1: Write failing action-style tests**

Add source-contract tests:

```swift
@Test func sampleEntryIsSecondaryAndPlacedWithTrailingActions() throws {
    let source = try repositorySource("RepositoryDialogs.swift")
    let footer = try #require(source.range(of: "Button(appLanguage.text(\"기존 로컬 폴더 등록…\""))
    let sample = try #require(source.range(of: "Button(appLanguage.text(\"샘플 프로젝트 둘러보기\""))
    let cancel = try #require(source.range(of: "Button(appLanguage.text(\"취소\""))

    #expect(footer.lowerBound < sample.lowerBound)
    #expect(sample.lowerBound < cancel.lowerBound)
}

@Test func demoExitUsesVisibleOrangeTextButton() throws {
    let source = try repositorySource("ContentView.swift")
    let start = try #require(source.range(of: "Button(appLanguage.text(\"데모 종료\", \"Exit Demo\"))"))
    let end = try #require(source.range(of: "Button(appLanguage.text(\"새로고침\"", range: start.upperBound..<source.endIndex))
    let demoButton = String(source[start.lowerBound..<end.lowerBound])

    #expect(demoButton.contains(".buttonStyle(.borderedProminent)"))
    #expect(demoButton.contains(".tint(.orange)"))
    #expect(!demoButton.contains("systemImage:"))
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter AppReviewReadinessTests`

Expected: sample ordering and demo button styling tests fail.

- [ ] **Step 3: Move the sample entry into the trailing action group**

Keep `Register Existing Local Folder…` before `Spacer()`. Move the existing sample button after `Spacer()` and before Cancel. Do not add `.tint` or `.buttonStyle(.borderedProminent)` to it.

- [ ] **Step 4: Make demo exit textual and orange**

Replace the system-image overload with:

```swift
Button(appLanguage.text("데모 종료", "Exit Demo")) {
    onExitDemo()
}
.buttonStyle(.borderedProminent)
.tint(.orange)
```

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter AppReviewReadinessTests`

Expected: focused suite passes.

Run: `swift test`

Expected: all tests pass.

### Task 3: Release verification, packaging, and commit

**Files:**
- Verify: `Resources/Info.plist`
- Verify: `scripts/package-app.sh`
- Verify: `store-assets/metadata/beta-review-en.md`
- Stage: all scoped source, test, metadata, and screenshot changes from the App Review response.

**Interfaces:**
- Consumes: version `0.5.11`, build `22`, App Store profile for `com.mrdevello.svnmac`, Apple Distribution identity for team `L735D6UX53`, and installer identity `3rd Party Mac Developer Installer: Mr.Devello Inc (L735D6UX53)`.
- Produces: a signed `dist/SVN-for-Mac-0.5.11-app-store.pkg` plus a Git commit containing the complete review response.

- [ ] **Step 1: Verify version and source diff**

Run:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist
git diff --check
```

Expected: `0.5.11`, `22`, and no diff errors.

- [ ] **Step 2: Build the App Store package**

Use the matching Mac App Store provisioning profile from the user-provided Apple key folder and run:

```bash
CODE_SIGN_IDENTITY='Apple Distribution: Mr.Devello Inc (L735D6UX53)' \
PROVISIONING_PROFILE='/Users/user/Library/CloudStorage/GoogleDrive-agart319@gmail.com/내 드라이브/MrD개인폴더/apple key (mrdevello 배포용)/SVN_Mac_App_Store.provisionprofile' \
INSTALLER_SIGN_IDENTITY='3rd Party Mac Developer Installer: Mr.Devello Inc (L735D6UX53)' \
./scripts/package-app-store.sh
```

Expected: `dist/SVN-for-Mac-0.5.11-app-store.pkg` is created.

- [ ] **Step 3: Verify signatures and embedded identity**

Run:

```bash
pkgutil --check-signature dist/SVN-for-Mac-0.5.11-app-store.pkg
codesign --verify --deep --strict 'dist/SVN for Mac.app'
codesign -d --entitlements :- 'dist/SVN for Mac.app'
```

Expected: installer and app signatures are valid, the application identifier ends with `com.mrdevello.svnmac`, and App Sandbox is enabled.

- [ ] **Step 4: Stage only scoped changes and commit**

Stage the App Review source, tests, metadata, regenerated screenshots, release version, and this plan. Commit with:

```bash
git commit -m 'feat: SVN for Mac 심사 대응과 데모 진입 개선'
```

- [ ] **Step 5: Confirm clean delivery state**

Run: `git status --short`

Expected: no remaining scoped changes.
