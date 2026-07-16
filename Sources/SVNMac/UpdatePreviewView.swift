import SwiftUI
import SVNCore

/// 작업 복사본을 변경하기 전에 서버에서 내려올 경로를 확인시키는 안전 장치입니다.
struct UpdatePreviewView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(appLanguage.text("업데이트 미리보기", "Update Preview")).font(.title2.bold())
                Spacer()
                Button(appLanguage.text("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            if store.remoteChanges.isEmpty {
                ContentUnavailableView(
                    appLanguage.text("내려받을 변경 없음", "No Incoming Changes"),
                    systemImage: "checkmark.circle",
                    description: Text(appLanguage.text("현재 로컬 작업 폴더가 서버와 최신 상태입니다.", "The working copy is up to date with the server."))
                )
            } else {
                List(store.remoteChanges) { entry in
                    HStack {
                        remoteBadge(entry.item)
                        Text(entry.path).font(.body.monospaced()).textSelection(.enabled)
                    }
                }
            }

            Divider()
            HStack {
                Text(appLanguage.text("업데이트 중 로컬 변경과 겹치면 SVN 충돌이 발생할 수 있습니다.", "Incoming changes that overlap local edits may create an SVN conflict."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.remoteChanges.isEmpty {
                    Button(appLanguage.text("업데이트 실행", "Run Update")) { Task { await store.update() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isWorking)
                }
            }
            .padding()
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private func remoteBadge(_ item: SVNStatusKind) -> some View {
        Text(item.rawValue.uppercased())
            .font(.caption2.bold()).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(item == .deleted ? Color.red : Color.blue, in: Capsule())
    }
}
