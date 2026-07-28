import AppKit
import SwiftUI
import SVNCore

struct ContentView: View {
    // MARK: - 앱 전역 상태와 화면 전용 입력 상태

    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone
    @State private var selectedProjectTab: ProjectTab = .changes
    @State private var fileSearchText = ""
    @State private var historySearchText = ""
    private let onBrowseDemo: () -> Void
    private let onExitDemo: () -> Void

    init(
        onBrowseDemo: @escaping () -> Void = {},
        onExitDemo: @escaping () -> Void = {}
    ) {
        self.onBrowseDemo = onBrowseDemo
        self.onExitDemo = onExitDemo
    }

    // MARK: - 최상위 화면 구성

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: $store.selectedProjectID) {
                Section(appLanguage.localized("ui.local.working.folders.341c44b5")) {
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
                    .help(appLanguage.localized("ui.check.out.a.new.svn.repository.or.register.an.ex.2b1e2b00"))

                    Button(action: store.removeSelectedProject) {
                        Image(systemName: "minus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 30, height: 24)
                    .disabled(store.selectedProject == nil)
                    .help(appLanguage.localized("ui.remove.the.selected.working.folder.from.the.app..ffe092ae"))
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
                    appLanguage.localized("ui.add.a.local.working.folder.816116ca"),
                    systemImage: "externaldrive.badge.plus",
                    description: Text(appLanguage.localized("ui.press.o.or.use.the.button.at.the.bottom.left.42abfdb5"))
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if store.isDemoMode {
                    Button(appLanguage.localized("ui.exit.demo.3a329c52")) {
                        onExitDemo()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .help(appLanguage.localized("ui.close.the.sample.project.and.return.to.normal.mo.6d61e364"))
                }
                Button {
                    Task { await store.refreshSelectedProject(manual: true) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text(appLanguage.localized("ui.refresh.0aca6bd2"))
                    }
                    .padding(.horizontal, AppLayout.toolbarItemHorizontalPadding)
                }
                .disabled(store.selectedProject == nil || store.isSelectedProjectActionBlocked)
                .help(appLanguage.localized("ui.reload.local.changes.and.the.latest.server.commi.19e409f3"))
                Button {
                    Task { await store.previewUpdate() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle")
                        Text(appLanguage.localized("ui.update.0f38eb76"))
                    }
                    .padding(.horizontal, AppLayout.toolbarItemHorizontalPadding)
                }
                .disabled(store.selectedProject == nil || store.isSelectedProjectActionBlocked)
                .help(appLanguage.localized("ui.download.the.latest.server.changes.into.the.curr.17974067"))
                if store.showsGlobalProgress {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                        .padding(.horizontal, AppLayout.toolbarItemHorizontalPadding)
                }
            }
        }
        .task(id: store.selectedProjectID) {
            await store.refreshSelectedProject(manual: false)
        }
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
            AddRepositoryView(onBrowseDemo: onBrowseDemo)
                .environment(store)
        }
        .sheet(isPresented: $store.isShowingCredentials) {
            if let project = store.selectedProject {
                CredentialsView(project: project)
                    .environment(store)
            }
        }
        .sheet(isPresented: $store.isShowingUpdatePreview) {
            UpdatePreviewView()
                .environment(store)
        }
        .sheet(isPresented: $store.isShowingLocks) {
            RepositoryLocksView()
                .environment(store)
        }
        .sheet(item: $store.authenticationRequest) { request in
            AuthenticationRequiredView(request: request)
                .environment(store)
        }
        .detailedErrorPresenter(
            errorMessage: $store.errorMessage,
            isEnabled: !store.hasContextualErrorPresentationOwner
        )
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
                repositoryLocksButton
                Button(appLanguage.localized("ui.open.in.finder.35aa9225"), systemImage: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: project.path, isDirectory: true))
                }
                .help(appLanguage.localized("ui.open.this.svn.local.working.folder.in.finder.9befff0f"))
                Button(appLanguage.localized("ui.credentials.97a976d9"), systemImage: "person.badge.key") {
                    store.isShowingCredentials = true
                }
                .help(appLanguage.localized("ui.configure.the.svn.account.and.keychain.password..daa54ac3"))
                if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            .padding()

            TabView(selection: $selectedProjectTab) {
                ChangesView()
                    .tabItem { Label(appLanguage.localized("ui.changes.0e19f519"), systemImage: "checklist") }
                    .tag(ProjectTab.changes)
                WorkingCopyBrowserView(searchText: $fileSearchText)
                    .tabItem { Label(appLanguage.localized("ui.files.6075adef"), systemImage: "folder") }
                    .tag(ProjectTab.files)
                HistoryView(searchText: $historySearchText)
                    .tabItem { Label(appLanguage.localized("ui.commit.history.07e0f8de"), systemImage: "clock.arrow.circlepath") }
                    .tag(ProjectTab.history)
            }
            .modifier(ProjectTabSearchModifier(
                selectedTab: selectedProjectTab,
                fileSearchText: $fileSearchText,
                historySearchText: $historySearchText,
                filePrompt: appLanguage.localized("ui.search.files.e3607184"),
                historyPrompt: appLanguage.localized("ui.search.author.file.message.or.revision.6c2b5d76")
            ))
        }
    }

    /// 탭 바깥의 프로젝트 공통 머리글에 두어 어느 탭에서도 잠금 현황을 확인할 수 있게 합니다.
    private var repositoryLocksButton: some View {
        Button {
            store.isShowingLocks = true
            Task { await store.loadRepositoryLocks() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock")
                Text(appLanguage.localized("ui.locks.dac8d38d"))
                if !store.repositoryLocks.isEmpty {
                    StatusBadge(
                        label: "\(store.repositoryLocks.count)",
                        color: .accentColor,
                        verticalPadding: 2
                    )
                    .accessibilityLabel(appLanguage.localized("ui.locks.46e6922e", store.repositoryLocks.count))
                }
            }
        }
        .help(appLanguage.localized("ui.view.the.locked.files.and.their.count.in.this.re.1d4d4a51"))
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

    func body(content: Content) -> some View {
        content.searchable(
            text: activeSearchText,
            isPresented: searchIsPresented,
            prompt: activePrompt
        )
    }

    private var activeSearchText: Binding<String> {
        switch selectedTab {
        case .changes:
            .constant("")
        case .files:
            $fileSearchText
        case .history:
            $historySearchText
        }
    }

    private var searchIsPresented: Binding<Bool> {
        Binding(
            get: { selectedTab != .changes },
            set: { _ in }
        )
    }

    private var activePrompt: String {
        selectedTab == .history ? historyPrompt : filePrompt
    }
}
