import AppKit
import SwiftUI

@MainActor
enum ErrorClipboard {
    static func copy(_ message: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(message, forType: .string)
    }
}

/// 오류 원문의 줄바꿈과 긴 경로를 손실 없이 탐색할 수 있는 공통 텍스트 영역입니다.
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
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25))
        }
    }
}

/// 표시 중인 오류 원문 전체를 클립보드에 복사하고 성공 상태를 안내합니다.
struct ErrorCopyButton: View {
    @Environment(\.appLanguage) private var appLanguage
    @State private var didCopy = false

    let message: String

    var body: some View {
        Button(
            didCopy
                ? appLanguage.localized(.ui.copied.label)
                : appLanguage.localized(.ui.copy.errorDetails),
            systemImage: didCopy ? "checkmark" : "doc.on.doc"
        ) {
            didCopy = ErrorClipboard.copy(message)
        }
        .help(appLanguage.localized(.ui.copy.allDisplayedErrorDetailsToTheClipboar))
        .onChange(of: message) { _, _ in didCopy = false }
    }
}

/// 일반 작업에서 발생한 오류를 읽고 복사할 수 있는 공통 상세 화면입니다.
struct DetailedErrorView: View {
    @Environment(\.appLanguage) private var appLanguage

    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(appLanguage.localized(.ui.error.label), systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.red)

            ErrorDetailsText(message: message)

            HStack {
                ErrorCopyButton(message: message)
                Spacer()
                Button(appLanguage.localized(.ui.close.label), role: .cancel) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.errorDetailsSheetMinimumSize)
    }
}

private struct DetailedErrorPresenter: ViewModifier {
    @Binding var errorMessage: String?
    let isEnabled: Bool

    private var isPresented: Binding<Bool> {
        Binding(
            get: { isEnabled && errorMessage != nil },
            set: { presented in
                if isEnabled && !presented { errorMessage = nil }
            }
        )
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: isPresented) {
            if let errorMessage {
                DetailedErrorView(message: errorMessage) {
                    self.errorMessage = nil
                }
            }
        }
    }
}

extension View {
    func detailedErrorPresenter(
        errorMessage: Binding<String?>,
        isEnabled: Bool = true
    ) -> some View {
        modifier(DetailedErrorPresenter(
            errorMessage: errorMessage,
            isEnabled: isEnabled
        ))
    }
}
