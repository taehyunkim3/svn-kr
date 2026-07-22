import AppKit
import SwiftUI
import SVNCore

struct ContentView: View {
    // MARK: - 앱 전역 상태와 화면 전용 입력 상태

    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone
    @State private var selectedProjectTab: ProjectTab = .changes
    @State private var fileSearchText = ""
    @State private var historySearchText = ""

    // MARK: - 최상위 화면 구성

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedProjectID) {
                Section(appLanguage.text("로컬 작업 폴더", "Local working folders")) {
                    ForEach(store.projects) { project in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                if let username = project.username, !username.isEmpty {
                                    Text(username).font(.caption).foregroundStyle(.secondary)
                                }
                                ProjectStatusBadges(summary: store.projectSummaries[project.id])
                            }
                        } icon: {
                            Image(systemName: "shippingbox")
                        }
                            .tag(project.id)
                            .help(project.path)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Button(action: { store.isShowingAddRepository = true }) {
                        Image(systemName: "plus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 30, height: 24)
                    .help(appLanguage.text("새 SVN 저장소를 체크아웃하거나 기존 로컬 작업 폴더를 등록합니다.", "Check out a new SVN repository or register an existing local working folder."))

                    Button(action: store.removeSelectedProject) {
                        Image(systemName: "minus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 30, height: 24)
                    .disabled(store.selectedProject == nil)
                    .help(appLanguage.text("선택한 로컬 작업 폴더를 앱 목록에서 제거합니다. 로컬 파일은 삭제하지 않습니다.", "Remove the selected working folder from the app. Local files are not deleted."))
                    Spacer()
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(
                min: AppLayout.sidebarMinimumWidth,
                ideal: AppLayout.sidebarIdealWidth,
                max: AppLayout.sidebarMaximumWidth
            )
        } detail: {
            if let project = store.selectedProject {
                projectView(project)
            } else {
                ContentUnavailableView(
                    appLanguage.text("로컬 작업 폴더를 추가하세요", "Add a local working folder"),
                    systemImage: "externaldrive.badge.plus",
                    description: Text(appLanguage.text("⌘O를 누르거나 왼쪽 아래 + 버튼을 사용하세요.", "Press ⌘O or use the + button at the bottom left."))
                )
            }
        }
        .toolbar {
            Button(appLanguage.text("새로고침", "Refresh"), systemImage: "arrow.clockwise") { Task { await refreshSelectedProject() } }
                .disabled(store.selectedProject == nil || store.isWorking)
                .help(appLanguage.text("로컬 변경 사항과 최신 서버 커밋 기록을 다시 불러옵니다.", "Reload local changes and the latest server commit history."))
            Button(appLanguage.text("업데이트", "Update"), systemImage: "arrow.down.circle") { Task { await store.previewUpdate() } }
                .disabled(store.selectedProject == nil || store.isWorking)
                .help(appLanguage.text("서버의 최신 변경 사항을 현재 로컬 작업 폴더에 내려받습니다.", "Download the latest server changes into the current local working folder."))
            if store.showsGlobalProgress {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            }
        }
        .onChange(of: store.selectedProjectID) { _, _ in Task { await refreshSelectedProject() } }
        .background {
            MainWindowActivationView {
                Task { await store.refreshForMainWindowActivation() }
            }
            .frame(width: 0, height: 0)
        }
        .task {
            if store.projects.isEmpty {
                store.isShowingAddRepository = true
            }
        }
        .sheet(isPresented: $store.isShowingAddRepository) {
            AddRepositoryView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isShowingCredentials) {
            if let project = store.selectedProject {
                CredentialsView(project: project)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $store.isShowingUpdatePreview) {
            UpdatePreviewView()
                .environmentObject(store)
        }
        .sheet(item: $store.authenticationRequest) { request in
            AuthenticationRequiredView(request: request)
                .environmentObject(store)
        }
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    // MARK: - 선택 프로젝트 화면

    /// 선택한 프로젝트의 공통 머리글과 변경/기록 탭을 구성합니다.
    private func projectView(_ project: SVNProject) -> some View {
        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.title2.bold())
                    Text(project.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button(appLanguage.text("Finder에서 열기", "Open in Finder"), systemImage: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: project.path, isDirectory: true))
                }
                .help(appLanguage.text(
                    "이 SVN 로컬 작업 폴더를 Finder에서 엽니다.",
                    "Open this SVN local working folder in Finder."
                ))
                Button(appLanguage.text("인증 설정", "Credentials"), systemImage: "person.badge.key") {
                    store.isShowingCredentials = true
                }
                .help(appLanguage.text("이 로컬 작업 폴더에서 사용할 SVN 계정과 Keychain 비밀번호를 설정합니다.", "Configure the SVN account and Keychain password for this local working folder."))
                if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            .padding()

            TabView(selection: $selectedProjectTab) {
                ChangesView()
                    .tabItem { Label(appLanguage.text("변경 사항", "Changes"), systemImage: "checklist") }
                    .tag(ProjectTab.changes)
                WorkingCopyBrowserView(searchText: $fileSearchText)
                    .tabItem { Label(appLanguage.text("파일", "Files"), systemImage: "folder") }
                    .tag(ProjectTab.files)
                HistoryView(searchText: $historySearchText)
                    .tabItem { Label(appLanguage.text("커밋 기록", "Commit History"), systemImage: "clock.arrow.circlepath") }
                    .tag(ProjectTab.history)
            }
            .modifier(ProjectTabSearchModifier(
                selectedTab: selectedProjectTab,
                fileSearchText: $fileSearchText,
                historySearchText: $historySearchText,
                filePrompt: appLanguage.text("파일 검색", "Search Files"),
                historyPrompt: appLanguage.text("작성자, 파일, 메시지, 리비전 검색", "Search author, file, message, or revision")
            ))
        }
    }

    private func refreshSelectedProject() async {
        guard !store.isDemoMode else { return }
        async let project: Void = store.refresh()
        async let files: Void = store.refreshWorkingCopyBrowser()
        _ = await (project, files)
    }

}

private enum ProjectTab: Hashable {
    case changes
    case files
    case history
}

private struct ProjectTabSearchModifier: ViewModifier {
    let selectedTab: ProjectTab
    @Binding var fileSearchText: String
    @Binding var historySearchText: String
    let filePrompt: String
    let historyPrompt: String

    @ViewBuilder
    func body(content: Content) -> some View {
        switch selectedTab {
        case .changes:
            content
        case .files:
            content.searchable(text: $fileSearchText, prompt: filePrompt)
        case .history:
            content.searchable(text: $historySearchText, prompt: historyPrompt)
        }
    }
}
