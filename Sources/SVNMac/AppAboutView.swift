import AppKit
import SwiftUI

struct AppAboutView: View {
    @ObservedObject var updateChecker: AppUpdateChecker
    @Environment(\.appLanguage) private var appLanguage

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)

            VStack(spacing: 4) {
                Text("SVN KR")
                    .font(.title2.bold())
                Text(appLanguage.text("버전 \(version) (\(build))", "Version \(version) (\(build))"))
                    .foregroundStyle(.secondary)
            }

            updateStatus

            Button(appLanguage.text("업데이트 확인", "Check for Updates")) {
                updateChecker.checkManually()
            }
            .disabled(updateChecker.manualStatus == .checking)

            Text("© 2026 Taehyun Kim")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(
            minWidth: AppLayout.aboutWindowSize.width,
            maxWidth: .infinity,
            minHeight: AppLayout.aboutWindowSize.height,
            maxHeight: .infinity
        )
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateChecker.manualStatus {
        case .idle:
            Text(appLanguage.text("App Store에서 최신 버전을 확인할 수 있습니다.", "Check the App Store for the latest version."))
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(appLanguage.text("업데이트 확인 중…", "Checking for updates…"))
            }
        case let .updateAvailable(release):
            VStack(spacing: 8) {
                Text(appLanguage.text("새 버전 \(release.version)을 사용할 수 있습니다.", "Version \(release.version) is available."))
                Button(appLanguage.text("App Store에서 보기", "View in App Store")) {
                    updateChecker.openStore(for: release)
                }
            }
        case let .upToDate(version):
            Text(appLanguage.text("최신 버전(\(version))을 사용 중입니다.", "You're using the latest version (\(version))."))
                .foregroundStyle(.secondary)
        case .failed:
            Text(appLanguage.text("App Store에서 업데이트 정보를 확인하지 못했습니다.", "Unable to check the App Store for updates."))
                .foregroundStyle(.red)
        }
    }
}

struct SVNMacCommands: Commands {
    @ObservedObject var updateChecker: AppUpdateChecker
    let appLanguage: AppLanguage
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(appLanguage.text("SVN KR 정보", "About SVN KR")) {
                openWindow(id: "app-about")
            }
        }

        CommandGroup(after: .appInfo) {
            Button(appLanguage.text("업데이트 확인…", "Check for Updates…")) {
                openWindow(id: "app-about")
                updateChecker.checkManually()
            }
        }
    }
}
