import SwiftUI

@main
struct SVNMacApp: App {
    @StateObject private var store = ProjectStore()
    @AppStorage(AppSettings.languageKey)
    private var languageIdentifier = AppSettings.defaultLanguage

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: languageIdentifier) ?? .korean
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.appLanguage, appLanguage)
                .frame(minWidth: 1120, minHeight: 700)
        }
        .defaultSize(width: 1280, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button(appLanguage.text("저장소 URL 체크아웃…", "Check Out Repository URL…")) { store.isShowingAddRepository = true }
                    .keyboardShortcut("o", modifiers: [.command])
            }
        }

        Settings {
            AppSettingsView()
        }
    }
}
