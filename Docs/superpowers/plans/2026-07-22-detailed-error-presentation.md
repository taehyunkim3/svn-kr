# Detailed Error Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱의 모든 오류 원문을 스크롤해서 읽고 전체 내용을 클립보드에 복사할 수 있는 공통 상세 오류 UI를 제공한다.

**Architecture:** `ProjectStore.errorMessage`를 기존 단일 오류 상태로 유지하고, 새 `DetailedErrorView`와 `detailedErrorPresenter` 뷰 수정자가 이를 표시한다. 클립보드 쓰기는 `ErrorClipboard`로 분리해 실제 문자열 보존을 단위 테스트하며, 체크아웃과 복구의 기존 인라인 오류 영역은 같은 복사 동작과 스크롤 가능한 텍스트 표현을 재사용한다.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSPasteboard`, Swift Testing

## Global Constraints

- `ProjectStore.errorMessage: String?`를 단일 오류 상태로 유지한다.
- 오류 문자열의 줄바꿈, 긴 경로, SVN stderr를 자르거나 다시 조합하지 않는다.
- 비밀번호, Keychain 값, 표준입력 내용을 새로 수집하거나 오류에 결합하지 않는다.
- 오류 이력 저장, 파일 내보내기, 서버 전송은 추가하지 않는다.
- 상세 오류의 크기 값은 `Sources/SVNMac/AppLayout.swift`에만 둔다.
- 기존 시트 최소 크기와 주요 창 크기는 변경하지 않는다.

---

### Task 1: 클립보드 동작과 공통 상세 오류 컴포넌트

**Files:**
- Create: `Sources/SVNMac/DetailedErrorView.swift`
- Create: `Tests/SVNMacTests/DetailedErrorPresentationTests.swift`
- Modify: `Sources/SVNMac/AppLayout.swift`

**Interfaces:**
- Produces: `@MainActor enum ErrorClipboard` with `static func copy(_ message: String, to pasteboard: NSPasteboard = .general) -> Bool`
- Produces: `struct ErrorDetailsText: View` initialized with `message: String` and optional `maximumHeight: CGFloat?`
- Produces: `struct ErrorCopyButton: View` initialized with `message: String`
- Produces: `struct DetailedErrorView: View` initialized with `message: String` and `onDismiss: () -> Void`
- Produces: `View.detailedErrorPresenter(errorMessage: Binding<String?>) -> some View`

- [ ] **Step 1: Write the failing clipboard preservation test**

```swift
import AppKit
import Testing
@testable import SVNMac

@MainActor
@Test func errorClipboardCopiesLongMultilineMessageWithoutModification() {
    let pasteboard = NSPasteboard(name: .init("DetailedErrorPresentationTests"))
    let message = "svn info 실패: 첫 줄\n경로: /한글 폴더/아주-긴-파일명.xlsx\nsvn: E200009: 상세 원문"

    #expect(ErrorClipboard.copy(message, to: pasteboard))
    #expect(pasteboard.string(forType: .string) == message)
}
```

- [ ] **Step 2: Run the new test and verify RED**

Run: `swift test --filter errorClipboardCopiesLongMultilineMessageWithoutModification`

Expected: compile failure because `ErrorClipboard` does not exist.

- [ ] **Step 3: Implement the minimal clipboard helper**

```swift
@MainActor
enum ErrorClipboard {
    static func copy(_ message: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(message, forType: .string)
    }
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `swift test --filter errorClipboardCopiesLongMultilineMessageWithoutModification`

Expected: one matching test passes.

- [ ] **Step 5: Add a failing source contract test for the common UI**

Append a test that reads `DetailedErrorView.swift` and asserts these contracts:

```swift
@Test func detailedErrorViewProvidesScrollableSelectableCopyableContent() throws {
    let source = try String(contentsOf: svnMacSources().appendingPathComponent("DetailedErrorView.swift"), encoding: .utf8)

    #expect(source.contains("ScrollView([.horizontal, .vertical])"))
    #expect(source.contains(".textSelection(.enabled)"))
    #expect(source.contains("ErrorCopyButton"))
    #expect(source.contains("detailedErrorPresenter"))
}
```

Add the local `svnMacSources()` helper by walking three parent directories from `#filePath` and appending `Sources/SVNMac`.

- [ ] **Step 6: Run the source contract test and verify RED**

Run: `swift test --filter detailedErrorViewProvidesScrollableSelectableCopyableContent`

Expected: failure because `DetailedErrorView.swift` does not yet contain the UI.

- [ ] **Step 7: Implement the common views and presenter**

In `DetailedErrorView.swift`, build:

```swift
struct ErrorDetailsText: View {
    let message: String
    var maximumHeight: CGFloat? = nil

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: maximumHeight)
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)) }
    }
}
```

`ErrorCopyButton` must call `ErrorClipboard.copy(message)`, show the localized `오류 내용 복사` / `Copy Error Details` label, and change to `복사됨` / `Copied` only when the pasteboard write succeeds. Reset its copied state in `.onChange(of: message)`.

`DetailedErrorView` must contain the localized title, `ErrorDetailsText`, `ErrorCopyButton`, and a localized `닫기` / `Close` button that calls `onDismiss`. Apply `appSheetFrame(minimumSize: AppLayout.errorDetailsSheetMinimumSize)`.

`DetailedErrorPresenter` must map the optional binding to `.sheet(isPresented:)`, render the current non-nil message, and set the binding to `nil` when dismissed.

Add this size contract to `AppLayout`:

```swift
static let errorDetailsSheetMinimumSize = CGSize(width: 640, height: 380)
static let inlineErrorMaximumHeight: CGFloat = 160
```

- [ ] **Step 8: Run Task 1 tests**

Run: `swift test --filter DetailedErrorPresentationTests`

Expected: clipboard and source contract tests pass.

- [ ] **Step 9: Commit Task 1**

```bash
git add Sources/SVNMac/DetailedErrorView.swift Sources/SVNMac/AppLayout.swift Tests/SVNMacTests/DetailedErrorPresentationTests.swift
git commit -m "feat: 상세 오류 공통 화면 추가"
```

---

### Task 2: 루트 화면과 활성 시트에 공통 오류 표시 연결

**Files:**
- Modify: `Sources/SVNMac/ContentView.swift`
- Modify: `Sources/SVNMac/RepositoryDialogs.swift`
- Modify: `Sources/SVNMac/UpdatePreviewView.swift`
- Modify: `Sources/SVNMac/IgnoreRulesView.swift`
- Modify: `Sources/SVNMac/RepositoryLocksView.swift`
- Modify: `Sources/SVNMac/ConflictResolutionView.swift`
- Modify: `Sources/SVNMac/FileHistoryView.swift`
- Modify: `Tests/SVNMacTests/DetailedErrorPresentationTests.swift`

**Interfaces:**
- Consumes: `View.detailedErrorPresenter(errorMessage:)` from Task 1.
- Produces: Every top-level error host displays `store.errorMessage` in the common detailed error sheet.

- [ ] **Step 1: Write the failing wiring contract test**

```swift
@Test func applicationErrorHostsUseDetailedPresenterInsteadOfRootAlert() throws {
    let sources = try svnMacSources()
    let content = try String(contentsOf: sources.appendingPathComponent("ContentView.swift"), encoding: .utf8)
    let expectedHosts = [
        "RepositoryDialogs.swift",
        "UpdatePreviewView.swift",
        "IgnoreRulesView.swift",
        "RepositoryLocksView.swift",
        "ConflictResolutionView.swift",
        "FileHistoryView.swift"
    ]

    #expect(!content.contains(".alert(appLanguage.text(\"오류\", \"Error\")"))
    #expect(content.contains(".detailedErrorPresenter(errorMessage: $store.errorMessage)"))
    for file in expectedHosts {
        let source = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
        #expect(source.contains(".detailedErrorPresenter(errorMessage: $store.errorMessage)"), "Missing presenter in \(file)")
    }
}
```

- [ ] **Step 2: Run the wiring test and verify RED**

Run: `swift test --filter applicationErrorHostsUseDetailedPresenterInsteadOfRootAlert`

Expected: failures because the root alert remains and modal hosts lack the presenter.

- [ ] **Step 3: Replace the root alert and wire modal hosts**

In `ContentView`, remove the generic error `.alert` and add:

```swift
.detailedErrorPresenter(errorMessage: $store.errorMessage)
```

Add the same modifier at the outer body of `AuthenticationRequiredView`, `CredentialsView`, `UpdatePreviewView`, `IgnoreRulesView`, `RepositoryLocksView`, `ConflictResolutionView`, and `FileHistoryView`. Do not replace task-specific confirmation alerts such as conflict choice or revert confirmation.

For `AddRepositoryView`, retain its in-context checkout log instead of opening a nested error sheet; Task 3 supplies its copy action.

- [ ] **Step 4: Run the wiring test and verify GREEN**

Run: `swift test --filter applicationErrorHostsUseDetailedPresenterInsteadOfRootAlert`

Expected: the wiring contract test passes.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/SVNMac/ContentView.swift Sources/SVNMac/RepositoryDialogs.swift Sources/SVNMac/UpdatePreviewView.swift Sources/SVNMac/IgnoreRulesView.swift Sources/SVNMac/RepositoryLocksView.swift Sources/SVNMac/ConflictResolutionView.swift Sources/SVNMac/FileHistoryView.swift Tests/SVNMacTests/DetailedErrorPresentationTests.swift
git commit -m "feat: 앱 오류를 상세 화면으로 연결"
```

---

### Task 3: 체크아웃과 복구의 인라인 오류를 스크롤·복사 가능하게 변경

**Files:**
- Modify: `Sources/SVNMac/RepositoryDialogs.swift`
- Modify: `Sources/SVNMac/WorkingCopyRecoveryView.swift`
- Modify: `Tests/SVNMacTests/DetailedErrorPresentationTests.swift`
- Read: `Docs/LayoutArchitecture.md`

**Interfaces:**
- Consumes: `ErrorCopyButton`, `ErrorDetailsText`, `AppLayout.inlineErrorMaximumHeight` from Task 1.
- Produces: Checkout retains its progress log and exposes an explicit copy action; recovery uses the common scrollable error text and copy action.

- [ ] **Step 1: Write the failing inline error contract test**

```swift
@Test func checkoutAndRecoveryErrorsExposeCopyAndScrolling() throws {
    let sources = try svnMacSources()
    let dialogs = try String(contentsOf: sources.appendingPathComponent("RepositoryDialogs.swift"), encoding: .utf8)
    let recovery = try String(contentsOf: sources.appendingPathComponent("WorkingCopyRecoveryView.swift"), encoding: .utf8)

    #expect(dialogs.contains("ErrorCopyButton(message: errorMessage)"))
    #expect(dialogs.contains("store.checkoutLog"))
    #expect(recovery.contains("ErrorDetailsText(message: error)"))
    #expect(recovery.contains("ErrorCopyButton(message: error)"))
}
```

- [ ] **Step 2: Run the inline contract test and verify RED**

Run: `swift test --filter checkoutAndRecoveryErrorsExposeCopyAndScrolling`

Expected: failures because the copy button and common recovery text are not wired.

- [ ] **Step 3: Add checkout copy action without removing progress output**

In `AddRepositoryView`'s checkout log block, keep the existing `ScrollView`, `store.checkoutLog`, error divider, automatic scroll, and `AppLayout.checkoutLogHeight`. When `store.errorMessage` is non-nil, add `ErrorCopyButton(message: errorMessage)` beside the progress-log heading or directly above the error text.

- [ ] **Step 4: Replace the recovery plain error text**

Replace the red plain `Text(error)` with:

```swift
VStack(alignment: .leading, spacing: 8) {
    ErrorDetailsText(message: error, maximumHeight: AppLayout.inlineErrorMaximumHeight)
    HStack {
        Spacer()
        ErrorCopyButton(message: error)
    }
}
```

- [ ] **Step 5: Run the inline contract test and verify GREEN**

Run: `swift test --filter checkoutAndRecoveryErrorsExposeCopyAndScrolling`

Expected: the inline error contract test passes.

- [ ] **Step 6: Verify layout rules and all tests**

Read `Docs/LayoutArchitecture.md`, then run:

```bash
swift test
```

Expected: all tests pass, including the 154-test baseline and new detailed-error tests.

- [ ] **Step 7: Inspect the final diff**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors and only the planned detailed-error files are modified.

- [ ] **Step 8: Commit Task 3**

```bash
git add Sources/SVNMac/RepositoryDialogs.swift Sources/SVNMac/WorkingCopyRecoveryView.swift Tests/SVNMacTests/DetailedErrorPresentationTests.swift
git commit -m "feat: 체크아웃과 복구 오류 복사 지원"
```

---

### Task 4: 최종 회귀 검증

**Files:**
- Verify only: all files changed by Tasks 1-3

**Interfaces:**
- Consumes: completed common error UI and all host integrations.
- Produces: verified branch ready for user-directed integration and push.

- [ ] **Step 1: Run the complete test suite from a clean build result**

Run: `swift test`

Expected: all tests pass with zero failures.

- [ ] **Step 2: Verify repository scope and commit history**

Run:

```bash
git status --short --branch
git log --oneline master..HEAD
git diff --stat master...HEAD
```

Expected: clean worktree, only the design plus detailed-error commits ahead of `master`, and no generated package artifacts.

- [ ] **Step 3: Report delivery state**

Report the worktree path, branch, test count, commits, changed files, and whether the branch has been pushed. Do not merge into `master` or push unless the user explicitly requests that delivery action.
