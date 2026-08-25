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
                Text(appLanguage.localized(.ui.version.label, version, build))
                    .foregroundStyle(.secondary)
            }

            updateStatus

            Button(appLanguage.localized(.ui.check.forUpdatesSecondary)) {
                updateChecker.checkManually()
            }
            .disabled(updateChecker.manualStatus == .checking)

            VStack(spacing: 3) {
                Text("Distributed by MR.DEVELLO")
                Text("© 2026 Taehyun Kim")
            }
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
            Text(appLanguage.localized(.ui.check.theAppStoreForTheLatestVersion))
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(appLanguage.localized(.ui.checking.forUpdates))
            }
        case let .updateAvailable(release):
            VStack(spacing: 8) {
                Text(appLanguage.localized(.ui.version.isAvailable, release.version))
                Button(appLanguage.localized(.ui.view.inAppStore)) {
                    updateChecker.openStore(for: release)
                }
            }
        case let .upToDate(version):
            Text(appLanguage.localized(.ui.you.reUsingTheLatestVersion, version))
                .foregroundStyle(.secondary)
        case .failed:
            Text(appLanguage.localized(.ui.unable.toCheckTheAppStoreForUpdates))
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
            Button(appLanguage.localized(.ui.about.svnKr)) {
                openWindow(id: "app-about")
            }
        }

        CommandGroup(after: .appInfo) {
            Button(appLanguage.localized(.ui.check.forUpdatesAction)) {
                openWindow(id: "app-about")
                updateChecker.checkManually()
            }
        }
    }
}
