import AppKit
import SwiftUI
import SVNCore

struct ContentView: View {
    // MARK: - 앱 전역 상태와 화면 전용 입력 상태

    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone
    @AppStorage(AppSettings.fileBrowserViewModeKey)
    private var fileBrowserViewModeIdentifier = AppSettings.defaultFileBrowserViewMode
    @State private var selectedProjectTab: ProjectTab = .changes
    @State private var fileSearchText = ""
    @State private var historySearchText = ""
    @State private var projectPendingRemoval: SVNProject?
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
                Section(appLanguage.localized(.ui.repository.localWorkingFolders)) {
                    ForEach(store.projects) { project in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                if let username = project.username, !username.isEmpty {
                                    Text(username).font(.caption).foregroundStyle(.secondary)
                                }
                                ProjectStatusBadges(
                                    summary: store.projectSummaries[project.id],
                                    hasFilenameNormalizationWarning:
                                        store.filenameNormalizationWarningProjectIDs.contains(project.id)
                                )
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
                    .help(appLanguage.localized(.ui.checkout.checkOutNewSvnRepositoryRegisterExistingLocalWorkingFolder))

                    Button(action: { projectPendingRemoval = store.selectedProject }) {
                        Image(systemName: "minus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 30, height: 24)
                    .disabled(store.selectedProject == nil)
                    .help(appLanguage.localized(.ui.repository.removeSelectedWorkingFolderAppLocalFilesNotDeleted))

                    // 전체 설정은 상단 메뉴에만 있어 찾기 어려우므로 사이드바에도 노출합니다.
                    SettingsLink {
                        Label(
                            appLanguage.localized(.ui.settings.settings),
                            systemImage: "gearshape"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(height: 24)
                    .help(appLanguage.localized(.ui.settings.openAppWideSettingsWindow))
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
                    appLanguage.localized(.ui.repository.addLocalWorkingFolder),
                    systemImage: "externaldrive.badge.plus",
                    description: Text(appLanguage.localized(.ui.repository.pressOUseButtonBottomLeft))
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if store.isDemoMode {
                    Button(appLanguage.localized(.ui.demo.exitDemo)) {
                        onExitDemo()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .help(appLanguage.localized(.ui.demo.closeSampleProjectReturnNormalMode))
                }
                Button {
                    Task { await store.refreshSelectedProject(manual: true) }
                } label: {
                    HStack(spacing: 5) {
                        if store.isRefreshingSelectedProject {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(appLanguage.localized(.ui.common.refresh))
                    }
                    .padding(.horizontal, AppLayout.toolbarItemHorizontalPadding)
                }
                .disabled(store.selectedProject == nil || store.isSelectedProjectActionBlocked)
                .help(appLanguage.localized(.ui.history.reloadLocalChangesLatestServerCommitHistory))
                Button {
                    Task { await store.previewUpdate() }
                } label: {
                    HStack(spacing: 5) {
                        if isUpdateInProgress {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text(appLanguage.localized(.ui.update.update))
                        if let badgeText = store.incomingUpdateCommitBadgeText {
                            Text(badgeText)
                                .font(.caption2.bold())
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.red, in: Capsule())
                                .offset(y: -6)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, AppLayout.toolbarItemHorizontalPadding)
                }
                .disabled(store.selectedProject == nil || store.isSelectedProjectActionBlocked)
                .help(appLanguage.localized(.ui.update.downloadLatestServerChangesCurrentLocalWorkingFolder))
                .accessibilityValue(
                    store.isWorkingCopyOutOfDate == true
                        ? appLanguage.localized(.ui.update.sidebarAvailableBadge)
                        : ""
                )
            }
            ToolbarItem(placement: .navigation) {
                if store.showsGlobalProgress {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                        .padding(.horizontal, AppLayout.toolbarItemHorizontalPadding)
                }
            }
        }
        .alert(
            projectPendingRemoval.map {
                appLanguage.localized(.ui.repository.removeApp, $0.name)
            } ?? "",
            isPresented: .isPresenting($projectPendingRemoval),
            presenting: projectPendingRemoval
        ) { project in
            Button(appLanguage.localized(.ui.common.remove), role: .destructive) {
                store.removeProject(project.id)
                projectPendingRemoval = nil
            }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                projectPendingRemoval = nil
            }
        } message: { _ in
            Text(appLanguage.localized(.ui.repository.removeSelectedWorkingFolderAppLocalFilesNotDeleted))
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
        .sheet(isPresented: $store.isShowingTemporaryFileCleanup) {
            TemporaryFileCleanupView()
                .environment(store)
                .interactiveDismissDisabled(store.isCleaningSelectedProjectTemporaryFiles)
        }
        .sheet(isPresented: $store.isShowingLocks) {
            RepositoryLocksView()
                .environment(store)
        }
        .sheet(isPresented: $store.isShowingRepositoryPathNormalization) {
            RepositoryPathNormalizationView()
                .environment(store)
        }
        .sheet(item: rootAuthenticationRequest) { request in
            AuthenticationRequiredView(request: request)
                .environment(store)
        }
        .detailedErrorPresenter(
            errorMessage: $store.errorMessage,
            isEnabled: !store.hasContextualErrorPresentationOwner
        )
    }

    private var isUpdateInProgress: Bool {
        store.isPreviewingSelectedProjectUpdate || store.isUpdatingSelectedProject
    }

    private var rootAuthenticationRequest: Binding<SVNAuthenticationRequest?> {
        Binding(
            get: { store.isShowingCredentials ? nil : store.authenticationRequest },
            set: { request in
                if request == nil { store.authenticationRequest = nil }
            }
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
                    if store.filenameNormalizationWarningProjectIDs.contains(project.id) {
                        Label(
                            appLanguage.localized(.ui.status.diskContainingFolderStoresKoreanFilenamesOnlyDecomposedFormFilenames),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                Spacer()
                repositoryPathNormalizationButton
                repositoryLocksButton
                Button(appLanguage.localized(.ui.repository.openFinder), systemImage: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: project.path, isDirectory: true))
                }
                .help(appLanguage.localized(.ui.repository.openSvnLocalWorkingFolderFinder))
                Button(appLanguage.localized(.ui.settings.folderSettings), systemImage: "person.badge.key") {
                    store.isShowingCredentials = true
                }
                .help(appLanguage.localized(.ui.authentication.changeFolderLocationSvnAccountKeychainPassword))
                if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            .padding()

            TabView(selection: $selectedProjectTab) {
                ChangesView()
                    .tabItem { Label(appLanguage.localized(.ui.common.changes), systemImage: "checklist") }
                    .tag(ProjectTab.changes)
                FileBrowserTabView(
                    searchText: $fileSearchText,
                    viewModeIdentifier: $fileBrowserViewModeIdentifier
                )
                    .tabItem { Label(appLanguage.localized(.ui.browser.files), systemImage: "folder") }
                    .tag(ProjectTab.files)
                HistoryView(searchText: $historySearchText)
                    .tabItem { Label(appLanguage.localized(.ui.history.commitHistory), systemImage: "clock.arrow.circlepath") }
                    .tag(ProjectTab.history)
            }
            .modifier(ProjectTabSearchModifier(
                selectedTab: selectedProjectTab,
                fileSearchText: $fileSearchText,
                historySearchText: $historySearchText,
                filePrompt: appLanguage.localized(.ui.browser.searchFiles),
                historyPrompt: appLanguage.localized(.ui.revision.searchAuthorFileMessageRevision)
            ))
        }
    }

    /// 저장소 전체를 검사하는 작업이므로 자동 실행하지 않고 공통 머리글의 명시적 액션으로 제공합니다.
    private var repositoryPathNormalizationButton: some View {
        Button {
            Task { await store.beginRepositoryPathNormalization() }
        } label: {
            ActionProgressLabel(
                title: appLanguage.localized(.repository.pathNormalization.action),
                inProgressTitle: appLanguage.localized(.repository.pathNormalization.scanning),
                systemImage: "character.book.closed",
                isInProgress: store.isScanningRepositoryPaths
            )
        }
        .disabled(store.isSelectedProjectActionBlocked)
        .help(appLanguage.localized(.repository.pathNormalization.actionHelp))
    }

    /// 탭 바깥의 프로젝트 공통 머리글에 두어 어느 탭에서도 잠금 현황을 확인할 수 있게 합니다.
    private var repositoryLocksButton: some View {
        Button {
            store.isShowingLocks = true
            Task { await store.loadRepositoryLocks() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock")
                Text(appLanguage.localized(.ui.lock.sheetTitle))
                if !store.repositoryLocks.isEmpty {
                    StatusBadge(
                        label: "\(store.repositoryLocks.count)",
                        color: .accentColor,
                        verticalPadding: 2
                    )
                    .accessibilityLabel(appLanguage.localized(.ui.lock.countAccessibilityLabel, store.repositoryLocks.count))
                }
            }
        }
        .help(appLanguage.localized(.ui.lock.viewLockedFilesTheirCountRepository))
    }

}

private struct FileBrowserTabView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Binding var searchText: String
    @Binding var viewModeIdentifier: String
    @State private var hasActivatedSplitView: Bool

    init(searchText: Binding<String>, viewModeIdentifier: Binding<String>) {
        _searchText = searchText
        _viewModeIdentifier = viewModeIdentifier
        _hasActivatedSplitView = State(
            initialValue: viewModeIdentifier.wrappedValue == FileBrowserViewMode.split.rawValue
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Picker(
                    appLanguage.localized(.ui.browser.chooseHowFilesDisplayed),
                    selection: $viewModeIdentifier
                ) {
                    Label(
                        appLanguage.localized(.ui.browser.treeView),
                        systemImage: "list.bullet.indent"
                    )
                    .tag(FileBrowserViewMode.tree.rawValue)
                    Label(
                        appLanguage.localized(.ui.browser.splitView),
                        systemImage: "sidebar.left"
                    )
                    .tag(FileBrowserViewMode.split.rawValue)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help(appLanguage.localized(.ui.browser.chooseHowFilesDisplayed))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ZStack {
                WorkingCopyBrowserView(searchText: $searchText)
                    .opacity(showsTreeBrowser ? 1 : 0)
                    .allowsHitTesting(showsTreeBrowser)
                    .accessibilityHidden(!showsTreeBrowser)

                if hasActivatedSplitView {
                    WorkingCopySplitBrowserView()
                        .opacity(showsSplitBrowser ? 1 : 0)
                        .allowsHitTesting(showsSplitBrowser)
                        .accessibilityHidden(!showsSplitBrowser)
                }
            }
        }
        .onChange(of: viewModeIdentifier, initial: true) { _, identifier in
            if identifier == FileBrowserViewMode.split.rawValue {
                hasActivatedSplitView = true
            }
        }
    }

    private var viewMode: FileBrowserViewMode {
        FileBrowserViewMode(rawValue: viewModeIdentifier) ?? .tree
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsTreeBrowser: Bool {
        viewMode == .tree || !normalizedSearchText.isEmpty
    }

    private var showsSplitBrowser: Bool {
        viewMode == .split && normalizedSearchText.isEmpty
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
