import AppKit
import SwiftUI
import SVNCore

struct ContentView: View {
    // MARK: - 앱 전역 상태와 화면 전용 입력 상태

    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone

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
            Button(appLanguage.text("새로고침", "Refresh"), systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                .disabled(store.selectedProject == nil || store.isWorking)
                .help(appLanguage.text("로컬 변경 사항과 최신 서버 커밋 기록을 다시 불러옵니다.", "Reload local changes and the latest server commit history."))
            Button(appLanguage.text("업데이트", "Update"), systemImage: "arrow.down.circle") { Task { await store.previewUpdate() } }
                .disabled(store.selectedProject == nil || store.isWorking)
                .help(appLanguage.text("서버의 최신 변경 사항을 현재 로컬 작업 폴더에 내려받습니다.", "Download the latest server changes into the current local working folder."))
            if store.isWorking { ProgressView().controlSize(.small) }
        }
        .onChange(of: store.selectedProjectID) { _, _ in Task { await store.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, store.selectedProject != nil, !store.isWorking else { return }
            Task { await store.refresh() }
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
        .alert(appLanguage.text("오류", "Error"), isPresented: Binding(get: { !store.isShowingAddRepository && store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button(appLanguage.text("확인", "OK"), role: .cancel) { store.errorMessage = nil }
                .help(appLanguage.text("오류 메시지를 닫습니다.", "Close the error message."))
        } message: { Text(store.errorMessage ?? "") }
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

            TabView {
                ChangesView()
                    .tabItem { Label(appLanguage.text("변경 사항", "Changes"), systemImage: "checklist") }
                HistoryView()
                    .tabItem { Label(appLanguage.text("커밋 기록", "Commit History"), systemImage: "clock.arrow.circlepath") }
            }
        }
    }

}
