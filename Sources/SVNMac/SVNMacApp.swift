import AppKit
import SwiftUI

@main
struct SVNMacApp: App {
    // ProjectStore는 앱 창의 수명 동안 하나만 유지하며 모든 하위 화면이 공유합니다.
    @StateObject private var store: ProjectStore
    @State private var isShowingContactSupport = false
    @AppStorage(AppSettings.languageKey)
    private var languageIdentifier = AppSettings.defaultLanguage

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: languageIdentifier) ?? .korean
    }

    init() {
        let isDemoMode = ProcessInfo.processInfo.environment["SVN_MAC_DEMO_MODE"] == "1"
        _store = StateObject(wrappedValue: isDemoMode ? ProjectStore.demo() : ProjectStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.appLanguage, appLanguage)
                // 앱 안의 기능 동작은 기본적으로 테두리가 있는 버튼으로 표시합니다.
                // 목록 행 선택과 컨텍스트 메뉴처럼 플랫폼 표현이 있는 곳만 화면에서 별도 스타일을 사용합니다.
                .buttonStyle(.bordered)
                .frame(
                    minWidth: AppLayout.windowMinimumWidth,
                    minHeight: AppLayout.windowMinimumHeight
                )
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
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button(appLanguage.text("저장소 URL 체크아웃…", "Check Out Repository URL…")) { store.isShowingAddRepository = true }
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
    }
}
