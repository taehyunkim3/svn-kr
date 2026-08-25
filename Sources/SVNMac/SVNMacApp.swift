import AppKit
import SwiftUI

@main
struct SVNMacApp: App {
    // ProjectStore는 앱 창의 수명 동안 하나만 유지하며 모든 하위 화면이 공유합니다.
    @State private var liveStore: ProjectStore
    @State private var demoStore: ProjectStore
    @StateObject private var updateChecker: AppUpdateChecker
    @State private var isDemoMode: Bool
    @State private var isShowingContactSupport = false
    @AppStorage(AppSettings.languageKey)
    private var languageIdentifier = AppSettings.defaultLanguage
    @AppStorage(AppSettings.hideTemporaryFilesKey)
    private var hideTemporaryFiles = AppSettings.defaultHideTemporaryFiles

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: languageIdentifier) ?? .korean
    }

    init() {
        let startsInDemoMode = ProcessInfo.processInfo.environment["SVN_MAC_DEMO_MODE"] == "1"
        _liveStore = State(initialValue: ProjectStore())
        _demoStore = State(initialValue: ProjectStore.demo())
        _updateChecker = StateObject(wrappedValue: AppUpdateChecker())
        _isDemoMode = State(initialValue: startsInDemoMode)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                onBrowseDemo: { isDemoMode = true },
                onExitDemo: { isDemoMode = false }
            )
                .environment(isDemoMode ? demoStore : liveStore)
                .environment(\.appLanguage, appLanguage)
                .id(isDemoMode)
                // 앱 안의 기능 동작은 기본적으로 테두리가 있는 버튼으로 표시합니다.
                // 목록 행 선택과 컨텍스트 메뉴처럼 플랫폼 표현이 있는 곳만 화면에서 별도 스타일을 사용합니다.
                .buttonStyle(.bordered)
                .frame(
                    minWidth: AppLayout.windowMinimumWidth,
                    minHeight: AppLayout.windowMinimumHeight
                )
                .task {
                    updateChecker.checkAutomaticallyIfNeeded()
                }
                .onChange(of: hideTemporaryFiles, initial: true) { _, value in
                    liveStore.hideTemporaryFiles = value
                    demoStore.hideTemporaryFiles = value
                }
                .alert(
                    appLanguage.localized(.ui.an.updateIsAvailable),
                    isPresented: Binding(
                        get: { updateChecker.automaticUpdate != nil },
                        set: { if !$0 { updateChecker.dismissAutomaticUpdate() } }
                    ),
                    presenting: updateChecker.automaticUpdate
                ) { release in
                    Button(appLanguage.localized(.ui.view.inAppStore)) {
                        updateChecker.openStore(for: release)
                        updateChecker.dismissAutomaticUpdate()
                    }
                    Button(appLanguage.localized(.ui.later.label), role: .cancel) {
                        updateChecker.dismissAutomaticUpdate()
                    }
                } message: { release in
                    Text(appLanguage.localized(.ui.version.isAvailable, release.version))
                }
                .alert(
                    AppContactSupport.alertTitle(for: appLanguage),
                    isPresented: $isShowingContactSupport
                ) {
                    Button(AppContactSupport.mailButtonTitle(for: appLanguage)) {
                        NSWorkspace.shared.open(AppContactSupport.mailURL)
                    }
                    Button(AppContactSupport.closeButtonTitle(for: appLanguage), role: .cancel) {}
                } message: {
                    Text(AppContactSupport.message(for: appLanguage))
                }
        }
        .defaultSize(
            width: AppLayout.windowDefaultWidth,
            height: AppLayout.windowDefaultHeight
        )
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            SVNMacCommands(updateChecker: updateChecker, appLanguage: appLanguage)
            CommandGroup(after: .newItem) {
                Button(appLanguage.localized(.ui.check.outRepositoryUrl)) {
                    (isDemoMode ? demoStore : liveStore).isShowingAddRepository = true
                }
                    .keyboardShortcut("o", modifiers: [.command])
            }
            CommandGroup(replacing: .help) {
                Button(AppContactSupport.menuTitle(for: appLanguage)) {
                    isShowingContactSupport = true
                }
            }
        }

        Settings {
            AppSettingsView()
                .buttonStyle(.bordered)
        }

        Window(appLanguage.localized(.ui.about.svnKr), id: "app-about") {
            AppAboutView(updateChecker: updateChecker)
                .environment(\.appLanguage, appLanguage)
                .buttonStyle(.bordered)
        }
        .defaultSize(
            width: AppLayout.aboutWindowSize.width,
            height: AppLayout.aboutWindowSize.height
        )
        .windowResizability(.contentSize)
    }
}
