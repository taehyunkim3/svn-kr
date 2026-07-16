import SwiftUI
import SVNCore

/// 텍스트 충돌과 병합이 어려운 문서 충돌을 서로 다른 안전한 흐름으로 안내합니다.
struct ConflictResolutionView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var pendingChoice: SVNConflictChoice?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            if let conflict = store.activeConflict {
                conflictBody(conflict)
            }
            Spacer()
            Divider()
            footer
        }
        .padding()
        .frame(minWidth: 680, minHeight: 480)
        .alert(
            appLanguage.text("이 버전으로 파일 전체를 교체할까요?", "Replace the Entire File with This Version?"),
            isPresented: Binding(get: { pendingChoice != nil }, set: { if !$0 { pendingChoice = nil } })
        ) {
            Button(appLanguage.text("교체하고 해결", "Replace and Resolve"), role: .destructive) {
                guard let choice = pendingChoice else { return }
                Task { await store.resolveActiveConflict(using: choice) }
            }
            Button(appLanguage.text("취소", "Cancel"), role: .cancel) { pendingChoice = nil }
        } message: {
            Text(appLanguage.text("현재 파일은 앱 지원 폴더에 먼저 백업됩니다. 교체 후 diff를 다시 확인하세요.", "The current file is backed up in Application Support first. Review the diff after replacement."))
        }
    }

    private var header: some View {
        HStack {
            Label(appLanguage.text("충돌 해결", "Resolve Conflict"), systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.orange)
            Spacer()
            Button(appLanguage.text("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private func conflictBody(_ conflict: SVNConflictDetails) -> some View {
        Text(conflict.path).font(.body.monospaced()).textSelection(.enabled)
        if DocumentFilePolicy.recommendsLock(for: conflict.path) {
            Label(
                appLanguage.text("문서·이미지 파일은 줄 단위 자동 병합이 안전하지 않습니다.", "Line-by-line automatic merging is unsafe for documents and images."),
                systemImage: "doc.richtext"
            )
            Text(appLanguage.text(
                "내 버전과 서버 버전을 모두 보관한 뒤 Word, PowerPoint 또는 원래 편집 프로그램에서 비교해 최종 파일을 만드세요.",
                "Preserve both versions, compare them in Word, PowerPoint, or the original editor, and create the final file."
            ))
            .foregroundStyle(.secondary)
            Button(appLanguage.text("두 버전 모두 원본 옆에 보관", "Preserve Both Versions Next to Original"), systemImage: "doc.on.doc") {
                store.preserveConflictVersions()
            }
            .buttonStyle(.borderedProminent)
        } else {
            Label(
                appLanguage.text("외부 편집기에서 충돌 표시를 병합한 뒤 현재 파일을 유지하세요.", "Merge the conflict markers in an external editor, then keep the working file."),
                systemImage: "chevron.left.forwardslash.chevron.right"
            )
        }

        HStack {
            Button(appLanguage.text("현재 파일 열기", "Open Working File"), systemImage: "arrow.up.forward.app") {
                store.openActiveConflictFile()
            }
            Button(appLanguage.text("내 버전 전체 사용", "Use My Entire Version")) { pendingChoice = .mineFull }
            Button(appLanguage.text("서버 버전 전체 사용", "Use Entire Server Version")) { pendingChoice = .theirsFull }
        }
        .buttonStyle(.bordered)
    }

    private var footer: some View {
        HStack {
            Text(appLanguage.text("해결 완료 전에는 이 파일을 커밋할 수 없습니다.", "This file cannot be committed until it is marked resolved."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(appLanguage.text("현재 파일로 충돌 해결 완료", "Mark Resolved Using Working File")) {
                Task { await store.resolveActiveConflict(using: .working) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isWorking)
        }
    }
}
