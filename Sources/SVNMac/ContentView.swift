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
    @State private var commitMessage = ""
    @FocusState private var isCommitMessageFocused: Bool

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
            .navigationSplitViewColumnWidth(min: 190, ideal: 230)
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
            Button(appLanguage.text("업데이트", "Update"), systemImage: "arrow.down.circle") { Task { await store.update() } }
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
        .sheet(item: $store.authenticationRequest) { request in
            AuthenticationRequiredView(request: request)
                .environmentObject(store)
        }
        .onChange(of: store.lastCompletedCommitMessage) { _, message in
            guard message != nil else { return }
            commitMessage = ""
            isCommitMessageFocused = false
            store.lastCompletedCommitMessage = nil
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
                changesView
                    .tabItem { Label(appLanguage.text("변경 사항", "Changes"), systemImage: "checklist") }
                HistoryView()
                    .tabItem { Label(appLanguage.text("커밋 기록", "Commit History"), systemImage: "clock.arrow.circlepath") }
            }
        }
    }

    // MARK: - 변경 파일과 선택 커밋

    private var changesView: some View {
        HSplitView {
            VStack(spacing: 0) {
                if store.statuses.isEmpty {
                    ContentUnavailableView(
                        appLanguage.text("변경 사항 없음", "No Changes"),
                        systemImage: "checkmark.circle",
                        description: Text(appLanguage.text("로컬에서 수정된 파일이 없습니다.", "There are no locally modified files."))
                    )
                } else {
                    List(store.statuses) { entry in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { store.selectedPaths.contains(entry.path) },
                                set: { checked in
                                    if checked { store.selectedPaths.insert(entry.path) }
                                    else { store.selectedPaths.remove(entry.path) }
                                }
                            )).labelsHidden()
                                .help(appLanguage.text("이 파일을 다음 선택 커밋에 포함하거나 제외합니다.", "Include or exclude this file from the next commit."))
                            statusBadge(entry.item)
                            Text(entry.path).lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { Task { await store.loadDiff(for: entry.path) } }
                        .listRowBackground(store.selectedStatusPath == entry.path ? Color.accentColor.opacity(0.12) : Color.clear)
                    }
                }

                Divider()
                VStack(spacing: 8) {
                    TextField(appLanguage.text("커밋 메시지", "Commit message"), text: $commitMessage)
                        .textFieldStyle(.roundedBorder)
                        .focused($isCommitMessageFocused)
                        .onSubmit { submitCommitAfterEndingTextInput() }
                    HStack {
                        Button(appLanguage.text("전체 선택", "Select All")) { store.selectedPaths = Set(store.statuses.map(\.path)) }
                            .help(appLanguage.text("현재 변경된 파일을 모두 커밋 대상으로 선택합니다.", "Select all currently changed files for commit."))
                        Button(appLanguage.text("선택 해제", "Clear Selection")) { store.selectedPaths.removeAll() }
                            .help(appLanguage.text("현재 선택된 커밋 대상을 모두 해제합니다.", "Clear all selected commit targets."))
                        Spacer()
                        Text(appLanguage.text("\(store.selectedPaths.count)개 선택", "\(store.selectedPaths.count) selected")).foregroundStyle(.secondary)
                        Button(appLanguage.text("선택 항목 커밋", "Commit Selected")) { submitCommitAfterEndingTextInput() }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.selectedPaths.isEmpty || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
                            .help(appLanguage.text("선택한 파일을 입력한 메시지로 SVN 서버에 커밋합니다.", "Commit the selected files to the SVN server with the entered message."))
                    }
                }
                .padding()
            }
            .frame(minWidth: 380)

            ScrollView([.horizontal, .vertical]) {
                Text(store.diffContent.localizedText(appLanguage))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
            }
            .frame(minWidth: 400)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // MARK: - 변경 상태 배지

    private func statusBadge(_ item: SVNStatusKind) -> some View {
        Text(statusLabel(item))
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(statusColor(item), in: Capsule())
    }

    private func statusLabel(_ item: SVNStatusKind) -> String {
        switch item {
        case .modified: appLanguage.text("수정", "Modified")
        case .added: appLanguage.text("추가", "Added")
        case .deleted, .missing: appLanguage.text("삭제", "Deleted")
        case .unversioned: appLanguage.text("미추적", "Unversioned")
        case .conflicted: appLanguage.text("충돌", "Conflict")
        case .replaced: appLanguage.text("교체", "Replaced")
        case let .unknown(value): value
        }
    }

    private func statusColor(_ item: SVNStatusKind) -> Color {
        switch item {
        case .modified: .orange
        case .added, .unversioned: .blue
        case .deleted, .missing, .conflicted: .red
        default: .gray
        }
    }

    // MARK: - 커밋 입력 처리

    private func submitCommit() {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        Task {
            // 성공 후 입력 초기화는 lastCompletedCommitMessage 변경 처리 한곳에서만
            // 수행합니다. 인증 재시도로 나중에 완료되는 커밋도 같은 경로를 사용합니다.
            _ = await store.commit(message: message)
        }
    }

    private func submitCommitAfterEndingTextInput() {
        isCommitMessageFocused = false
        Task { @MainActor in
            await Task.yield()
            submitCommit()
        }
    }
}

/// Keychain 접근이 거부됐을 때 사용자가 인증 방식을 다시 선택하는 화면입니다.
/// 원래 수행하려던 작업은 `SVNAuthenticationRequest`에 보존되어 인증 성공 후 재개됩니다.
private struct AuthenticationRequiredView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    let request: SVNAuthenticationRequest
    @State private var username: String
    @State private var password = ""
    @State private var isSubmitting = false

    init(request: SVNAuthenticationRequest) {
        self.request = request
        _username = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appLanguage.text("SVN 인증 필요", "SVN Authentication Required"))
                    .font(.title2.bold())
                Text(reasonText)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text(appLanguage.text("사용자명", "Username"))
                    TextField(appLanguage.text("SVN 계정명", "SVN username"), text: $username)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 360)
                }
                GridRow {
                    Text(appLanguage.text("비밀번호", "Password"))
                    SecureField(appLanguage.text("SVN 비밀번호", "SVN password"), text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text(appLanguage.text(
                "취소해도 로컬 변경 사항과 diff는 계속 확인할 수 있습니다.",
                "Canceling does not prevent viewing local changes and diffs."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
            HStack {
                Button(appLanguage.text("키체인 다시 시도", "Try Keychain Again")) {
                    isSubmitting = true
                    Task { await store.retryKeychainAccess(for: request) }
                }
                .disabled(isSubmitting)
                .help(appLanguage.text("macOS Keychain 접근 창을 다시 표시합니다.", "Show the macOS Keychain access prompt again."))
                Spacer()
                Button(appLanguage.text("취소", "Cancel"), role: .cancel) {
                    store.cancelAuthentication(for: request)
                }
                .keyboardShortcut(.cancelAction)
                Button(appLanguage.text("이번 실행에만 사용", "Use This Session Only")) {
                    submit(saveInKeychain: false)
                }
                .disabled(!canSubmit)
                Button(appLanguage.text("키체인에 저장하고 사용", "Save in Keychain and Use")) {
                    submit(saveInKeychain: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            username = store.projects.first(where: { $0.id == request.projectID })?.username ?? ""
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !store.isWorking
            && !isSubmitting
    }

    private var reasonText: String {
        switch request.action {
        case .refreshHistory:
            appLanguage.text("서버의 최신 커밋 기록을 불러오려면 인증이 필요합니다.", "Authentication is required to load the latest server history.")
        case .update:
            appLanguage.text("서버의 최신 변경 사항을 내려받으려면 인증이 필요합니다.", "Authentication is required to download the latest server changes.")
        case .commit:
            appLanguage.text("선택한 변경 사항을 서버에 커밋하려면 인증이 필요합니다.", "Authentication is required to commit the selected changes.")
        }
    }

    private func submit(saveInKeychain: Bool) {
        isSubmitting = true
        Task {
            let didStartOperation = await store.useCredentials(
                for: request,
                username: username,
                password: password,
                saveInKeychain: saveInKeychain
            )
            if !didStartOperation { isSubmitting = false }
        }
    }
}

/// 새 저장소 체크아웃에 필요한 입력을 수집하는 모달 화면입니다.
/// 실제 파일 작업과 상태 갱신은 `ProjectStore.checkout`에 위임합니다.
private struct AddRepositoryView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @State private var repositoryURL = ""
    @State private var destinationURL: URL?
    @State private var username = ""
    @State private var password = ""
    @State private var allowsUntrustedServerCertificate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appLanguage.text("SVN 저장소 추가", "Add SVN Repository")).font(.title2.bold())
                Text(appLanguage.text("저장소 URL을 체크아웃하고 로컬 작업 폴더 목록에 등록합니다.", "Check out a repository URL and add it to your local working folders."))
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text(appLanguage.text("저장소 URL", "Repository URL"))
                    TextField("https://server/svn/project/trunk", text: $repositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 440)
                }
                GridRow {
                    Text(appLanguage.text("로컬 폴더", "Local folder"))
                    HStack {
                        TextField(
                            "/Users/name/Documents/project",
                            text: Binding(
                                get: { destinationURL?.path ?? "" },
                                set: { _ in }
                            )
                        )
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        Button(appLanguage.text("선택…", "Choose…")) { chooseDestination() }
                            .help(appLanguage.text("체크아웃 결과를 저장할 로컬 폴더를 선택합니다.", "Choose the local folder for the checkout."))
                    }
                }
                GridRow {
                    Text(appLanguage.text("사용자명", "Username"))
                    TextField(appLanguage.text("SVN 계정명 (선택)", "SVN username (optional)"), text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(appLanguage.text("비밀번호", "Password"))
                    SecureField(appLanguage.text("macOS Keychain에 저장 (선택)", "Save in macOS Keychain (optional)"), text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text(appLanguage.text("인증은 기존 SVN 인증 캐시와 macOS Keychain을 사용합니다.", "Authentication uses the existing SVN credential cache and macOS Keychain."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                appLanguage.text(
                    "신뢰할 수 없는 SSL 인증서 허용",
                    "Allow untrusted SSL certificates"
                ),
                isOn: $allowsUntrustedServerCertificate
            )
            .toggleStyle(.checkbox)
            .help(appLanguage.text(
                "자체 서명 인증서 또는 접속 주소와 인증서 이름이 다른 서버에서만 사용하세요.",
                "Use only for servers with self-signed certificates or certificate name mismatches."
            ))

            if store.isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(appLanguage.text("체크아웃 중…", "Checking out…"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let errorMessage = store.errorMessage {
                ScrollView {
                    Text(errorMessage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 110)
                .padding(10)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.red)
            }

            Divider()
            HStack {
                Button(appLanguage.text("기존 로컬 폴더 등록…", "Register Existing Local Folder…")) {
                    dismiss()
                    store.showFolderPicker()
                }
                .help(appLanguage.text("이미 체크아웃된 SVN 로컬 작업 폴더를 앱 목록에 등록합니다.", "Register an existing SVN working folder in the app."))
                Spacer()
                Button(appLanguage.text("취소", "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help(appLanguage.text("저장소 추가를 취소하고 창을 닫습니다.", "Cancel adding the repository and close this window."))
                Button(appLanguage.text("체크아웃 및 추가", "Check Out and Add")) {
                    Task {
                        if await store.checkout(
                            repositoryURL: repositoryURL,
                            destinationURL: destinationURL,
                            username: username,
                            password: password,
                            allowsUntrustedServerCertificate: allowsUntrustedServerCertificate
                        ) {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || destinationURL == nil || store.isWorking)
                .help(appLanguage.text("입력한 SVN 저장소를 로컬 폴더에 체크아웃하고 앱에 등록합니다.", "Check out the SVN repository into the local folder and add it to the app."))
            }
        }
        .padding(24)
        .frame(width: 650)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = appLanguage.text("체크아웃할 로컬 폴더 선택", "Choose Local Checkout Folder")
        panel.prompt = appLanguage.text("선택", "Choose")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        destinationURL = destination.standardizedFileURL
    }
}

/// 프로젝트별 SVN 사용자명, Keychain 비밀번호, 인증서 예외를 관리합니다.
private struct CredentialsView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    let project: SVNProject
    @State private var username: String
    @State private var newPassword = ""
    @State private var hasSavedPassword: Bool
    @State private var allowsUntrustedServerCertificate: Bool

    init(project: SVNProject) {
        self.project = project
        _username = State(initialValue: project.username ?? "")
        _hasSavedPassword = State(initialValue: false)
        _allowsUntrustedServerCertificate = State(initialValue: project.allowsUntrustedServerCertificate == true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appLanguage.text("폴더별 인증 설정", "Folder Credentials")).font(.title2.bold())
                Text(project.name).foregroundStyle(.secondary)
                Text(project.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text(appLanguage.text("사용자명", "Username"))
                    TextField(appLanguage.text("SVN 계정명", "SVN username"), text: $username)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 360)
                }
                GridRow {
                    Text(appLanguage.text("비밀번호", "Password"))
                    SecureField(
                        hasSavedPassword
                            ? appLanguage.text("비우면 기존 값 유지", "Leave blank to keep the current password")
                            : appLanguage.text("비밀번호 입력", "Enter password"),
                        text: $newPassword
                    )
                        .textFieldStyle(.roundedBorder)
                }
            }

            Label(
                hasSavedPassword
                    ? appLanguage.text("이 폴더의 비밀번호가 macOS Keychain에 저장되어 있습니다.", "A password for this folder is stored in macOS Keychain.")
                    : appLanguage.text("저장된 비밀번호가 없습니다.", "No password is stored."),
                systemImage: hasSavedPassword ? "checkmark.shield" : "shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Toggle(
                appLanguage.text(
                    "신뢰할 수 없는 SSL 인증서 허용",
                    "Allow untrusted SSL certificates"
                ),
                isOn: $allowsUntrustedServerCertificate
            )
            .toggleStyle(.checkbox)
            .help(appLanguage.text(
                "이 저장소의 자체 서명 및 인증서 이름 불일치 오류를 허용합니다.",
                "Allow self-signed and certificate name mismatch errors for this repository."
            ))

            Divider()
            HStack {
                if hasSavedPassword {
                    Button(appLanguage.text("저장된 비밀번호 삭제", "Delete Saved Password"), role: .destructive) {
                        if store.deleteSavedPassword(for: project.id) {
                            hasSavedPassword = false
                            newPassword = ""
                        }
                    }
                    .help(appLanguage.text("이 로컬 작업 폴더용으로 Keychain에 저장된 SVN 비밀번호를 삭제합니다.", "Delete the SVN password stored in Keychain for this local working folder."))
                }
                Spacer()
                Button(appLanguage.text("취소", "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help(appLanguage.text("인증 설정 변경을 저장하지 않고 창을 닫습니다.", "Close without saving credential changes."))
                Button(appLanguage.text("저장", "Save")) {
                    if store.saveCredentials(
                        for: project.id,
                        username: username,
                        newPassword: newPassword,
                        allowsUntrustedServerCertificate: allowsUntrustedServerCertificate
                    ) {
                        dismiss()
                        Task { await store.refresh() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help(appLanguage.text("입력한 SVN 사용자명과 새 비밀번호를 이 로컬 작업 폴더에 저장합니다.", "Save the SVN username and new password for this local working folder."))
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { hasSavedPassword = store.hasSavedPassword(for: project.id) }
    }
}
