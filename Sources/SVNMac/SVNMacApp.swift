import SwiftUI

@main
struct SVNMacApp: App {
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1120, minHeight: 700)
        }
        .defaultSize(width: 1280, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("저장소 URL 체크아웃…") { store.isShowingAddRepository = true }
                    .keyboardShortcut("o", modifiers: [.command])
            }
        }

        Settings {
            AppSettingsView()
        }
    }
}
