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
                Text(appLanguage.localized("ui.version.6bb2f91c", version, build))
                    .foregroundStyle(.secondary)
            }

            updateStatus

            Button(appLanguage.localized("ui.check.for.updates.d0ccb7fe")) {
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
            Text(appLanguage.localized("ui.check.the.app.store.for.the.latest.version.969078c0"))
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(appLanguage.localized("ui.checking.for.updates.967c32b4"))
            }
        case let .updateAvailable(release):
            VStack(spacing: 8) {
                Text(appLanguage.localized("ui.version.is.available.7e5cfb4e", release.version))
                Button(appLanguage.localized("ui.view.in.app.store.7c79e972")) {
                    updateChecker.openStore(for: release)
                }
            }
        case let .upToDate(version):
            Text(appLanguage.localized("ui.you.re.using.the.latest.version.18d5624c", version))
                .foregroundStyle(.secondary)
        case .failed:
            Text(appLanguage.localized("ui.unable.to.check.the.app.store.for.updates.a1a5b5ac"))
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
            Button(appLanguage.localized("ui.about.svn.kr.ddc63e52")) {
                openWindow(id: "app-about")
            }
        }

        CommandGroup(after: .appInfo) {
            Button(appLanguage.localized("ui.check.for.updates.6ba78913")) {
                openWindow(id: "app-about")
                updateChecker.checkManually()
            }
        }
    }
}
