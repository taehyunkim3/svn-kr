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
                Button("작업 복사본 추가…") { store.showFolderPicker() }
                    .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
