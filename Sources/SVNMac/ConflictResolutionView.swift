import SwiftUI
import SVNCore

enum ConflictResolutionCopy {
    static func backupAlertMessage(for language: AppLanguage) -> String {
        language.text(
            "백업 폴더에는 내 버전과 서버 버전의 비교용 복사본이 보관됩니다. 이 복사본을 편집해도 현재 작업 파일은 바뀌지 않습니다.",
            "The backup folder keeps comparison copies of your version and the server version. Editing those copies does not change the current working file."
        )
    }
}

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
            if let session = store.activeConflictSession {
                conflictBody(session)
            }
            Spacer()
            Divider()
            footer
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.conflictResolutionSheetMinimumSize)
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
            Text(ConflictResolutionCopy.backupAlertMessage(for: appLanguage))
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
    private func conflictBody(_ session: ConflictResolutionSession) -> some View {
        let conflict = session.details
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
            Button(appLanguage.text("백업 폴더 열기", "Open Backup Folder"), systemImage: "folder") {
                store.openConflictBackupFolder()
            }
            .buttonStyle(.borderedProminent)
        } else {
            Label(
                appLanguage.text("외부 편집기에서 충돌 표시를 병합한 뒤 현재 파일을 유지하세요.", "Merge the conflict markers in an external editor, then keep the working file."),
                systemImage: "chevron.left.forwardslash.chevron.right"
            )
        }

        HStack {
            Button(appLanguage.text("내 버전 열기", "Open My Version"), systemImage: "arrow.up.forward.app") {
                store.openConflictVersion(.mineFull)
            }
            Button(appLanguage.text("서버 버전 열기", "Open Server Version"), systemImage: "arrow.up.forward.app") {
                store.openConflictVersion(.theirsFull)
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
        }
    }
}
