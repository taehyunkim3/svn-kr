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
            confirmationTitle,
            isPresented: Binding(get: { pendingChoice != nil }, set: { if !$0 { pendingChoice = nil } })
        ) {
            Button(confirmationActionTitle, role: .destructive) {
                guard let choice = pendingChoice else { return }
                Task { await store.resolveActiveConflict(using: choice) }
            }
            Button(appLanguage.text("취소", "Cancel"), role: .cancel) { pendingChoice = nil }
        } message: {
            if let choice = pendingChoice {
                Text(confirmationMessage(for: choice))
            }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Label(
                    appLanguage.text(
                        "내 파일과 서버 파일은 백업 폴더에 복사되었습니다. 열어 수정해도 실제 작업 파일에는 반영되지 않습니다.",
                        "Both versions were copied to a backup folder. Editing these copies does not change the working file."
                    ),
                    systemImage: "externaldrive.badge.checkmark"
                )
                .foregroundStyle(.secondary)
                Spacer()
                Button(appLanguage.text("백업 폴더 열기", "Open Backup Folder"), systemImage: "folder") {
                    store.openConflictBackupFolder()
                }
            }

            versionCard(
                title: appLanguage.text("내 파일", "My File"),
                version: session.mine,
                openTitle: appLanguage.text("내 파일 열기", "Open My File"),
                useTitle: appLanguage.text("내 파일 사용", "Use My File"),
                choice: .mineFull
            )

            versionCard(
                title: appLanguage.text("서버 파일", "Server File"),
                version: session.server,
                openTitle: appLanguage.text("서버 파일 열기", "Open Server File"),
                useTitle: appLanguage.text("서버 파일 사용", "Use Server File"),
                choice: .theirsFull
            )
        }
    }

    private func versionCard(
        title: String,
        version: ConflictVersionBackup,
        openTitle: String,
        useTitle: String,
        choice: SVNConflictChoice
    ) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                Text(version.url.lastPathComponent)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(ByteCountFormatter.string(fromByteCount: version.byteCount, countStyle: .file))
                    .foregroundStyle(.secondary)
                Text(versionMetadata(for: version))
                    .foregroundStyle(.secondary)
                HStack {
                    Button(openTitle) {
                        store.openConflictVersion(choice)
                    }
                    Spacer()
                    Button(useTitle) {
                        pendingChoice = choice
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var confirmationTitle: String {
        guard let choice = pendingChoice else { return "" }
        switch choice {
        case .mineFull:
            return appLanguage.text("내 파일을 사용할까요?", "Use My File?")
        case .theirsFull:
            return appLanguage.text("서버 파일을 사용할까요?", "Use Server File?")
        case .working:
            return ""
        }
    }

    private var confirmationActionTitle: String {
        guard let choice = pendingChoice else { return "" }
        switch choice {
        case .mineFull:
            return appLanguage.text("내 파일 사용", "Use My File")
        case .theirsFull:
            return appLanguage.text("서버 파일 사용", "Use Server File")
        case .working:
            return ""
        }
    }

    private func confirmationMessage(for choice: SVNConflictChoice) -> String {
        switch choice {
        case .mineFull:
            appLanguage.text(
                "내 파일을 유지합니다. 이후 커밋하면 서버 파일이 이 내용으로 변경됩니다.",
                "Keep your file. A later commit will replace the repository file with this content."
            )
        case .theirsFull:
            appLanguage.text(
                "서버 파일로 교체합니다. 작업 중이던 내 변경 내용은 작업 폴더에서 사라집니다. 내 원본은 백업 폴더에 보관됩니다.",
                "Replace with the server file. Your local edits leave the working copy but remain in the backup folder."
            )
        case .working:
            ""
        }
    }

    private func versionMetadata(for version: ConflictVersionBackup) -> String {
        if let revision = version.revision {
            return appLanguage.text("서버 리비전 \(revision)", "Server revision \(revision)")
        }
        if let modificationDate = version.modificationDate {
            return appLanguage.text(
                "수정 시각 \(modificationDate.formatted(date: .abbreviated, time: .shortened))",
                "Modified \(modificationDate.formatted(date: .abbreviated, time: .shortened))"
            )
        }
        return appLanguage.text("수정 시각을 알 수 없음", "Modification date unavailable")
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
