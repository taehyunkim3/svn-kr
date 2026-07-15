import SwiftUI

@main
struct SVNMacApp: App {
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("저장소 URL 체크아웃…") { store.isShowingAddRepository = true }
                    .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
