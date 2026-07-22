import AppKit
import SwiftUI
import SVNCore

struct WorkingCopyRecoveryView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @State private var destinationURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(
                    appLanguage.text("한글 경로 자동 복구", "Automatic Unicode Path Recovery"),
                    systemImage: "cross.case"
                )
                .font(.headline)
                Spacer()
                Button(appLanguage.text("닫기", "Close")) {
                    store.isShowingPathRecovery = false
                }
                .disabled(store.isPathRecoveryRunning)
            }

            Text(appLanguage.text(
                "서버에서 새 작업 폴더를 체크아웃한 뒤 실제 로컬 변경만 NFC 한글 경로로 옮깁니다. 현재 작업 폴더와 파일은 변경하거나 삭제하지 않습니다.",
                "A clean working copy is checked out from the server, then only real local changes are migrated using NFC paths. The current working folder and its files are not changed or deleted."
            ))
            .foregroundStyle(.secondary)

            if let preview = store.pathRecoveryPreview {
                GroupBox(appLanguage.text("복구 미리보기", "Recovery Preview")) {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        previewRow(appLanguage.text("수정", "Modified"), value: preview.modifiedCount)
                        previewRow(appLanguage.text("신규", "New"), value: preview.addedCount)
                        previewRow(appLanguage.text("로컬 누락", "Locally missing"), value: preview.deletedCount)
                        previewRow(appLanguage.text("제외할 가짜 경로", "False aliases excluded"), value: preview.ignoredAliasCount)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if !preview.blockingPaths.isEmpty {
                    Label(
                        appLanguage.text(
                            "자동 복구 전에 직접 확인해야 할 경로: \(preview.blockingPaths.joined(separator: ", "))",
                            "Review these paths before automatic recovery: \(preview.blockingPaths.joined(separator: ", "))"
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }

            GroupBox(appLanguage.text("새 작업 폴더", "New Working Folder")) {
                HStack {
                    Text(destinationURL?.path ?? appLanguage.text("비어 있는 폴더를 선택하세요.", "Choose an empty folder."))
                        .foregroundStyle(destinationURL == nil ? .secondary : .primary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                    Button(appLanguage.text("폴더 선택…", "Choose Folder…"), systemImage: "folder") {
                        chooseDestination()
                    }
                    .disabled(store.isPathRecoveryRunning)
                }
                .padding(.vertical, 4)
            }

            if let error = store.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(appLanguage.text("오류", "Error"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    ErrorDetailsText(
                        message: error,
                        maximumHeight: AppLayout.inlineErrorMaximumHeight
                    )
                    HStack {
                        Spacer()
                        ErrorCopyButton(message: error)
                    }
                }
            }

            Spacer()

            HStack {
                Text(appLanguage.text(
                    "성공하면 원본과 복구본이 모두 왼쪽 목록에 남습니다.",
                    "On success, both the original and recovered copies remain in the sidebar."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                if store.isPathRecoveryRunning { ProgressView().controlSize(.small) }
                Button(appLanguage.text("새 작업 폴더로 복구", "Recover to New Working Folder")) {
                    Task { _ = await store.recoverWorkingCopy(to: destinationURL) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    destinationURL == nil
                        || store.pathRecoveryPreview?.blockingPaths.isEmpty != true
                        || store.isPathRecoveryRunning
                )
            }
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.pathRecoverySheetMinimumSize)
    }

    @ViewBuilder
    private func previewRow(_ label: String, value: Int) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value.formatted()).monospacedDigit()
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = appLanguage.text("복구할 빈 폴더 선택", "Choose an Empty Recovery Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { destinationURL = panel.url?.standardizedFileURL }
    }
}
