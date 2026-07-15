import SwiftUI
import SVNCore

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var commitMessage = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedProjectID) {
                Section("작업 복사본") {
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

                    Button(action: store.removeSelectedProject) {
                        Image(systemName: "minus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 30, height: 24)
                        .disabled(store.selectedProject == nil)
                    Spacer()
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 230)
        } detail: {
            if let project = store.selectedProject {
                projectView(project)
            } else {
                ContentUnavailableView("작업 복사본을 추가하세요", systemImage: "externaldrive.badge.plus", description: Text("⌘O를 누르거나 왼쪽 아래 + 버튼을 사용하세요."))
            }
        }
        .toolbar {
            Button("새로고침", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                .disabled(store.selectedProject == nil || store.isWorking)
            Button("업데이트", systemImage: "arrow.down.circle") { Task { await store.update() } }
                .disabled(store.selectedProject == nil || store.isWorking)
            if store.isWorking { ProgressView().controlSize(.small) }
        }
        .onChange(of: store.selectedProjectID) { _, _ in Task { await store.refresh() } }
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
        .alert("오류", isPresented: Binding(get: { !store.isShowingAddRepository && store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("확인", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private func projectView(_ project: SVNProject) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.title2.bold())
                    Text(project.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("인증 설정", systemImage: "person.badge.key") {
                    store.isShowingCredentials = true
                }
                if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            .padding()

            TabView {
                changesView
                    .tabItem { Label("변경 사항", systemImage: "checklist") }
                historyView
                    .tabItem { Label("커밋 기록", systemImage: "clock.arrow.circlepath") }
            }
        }
    }

    private var changesView: some View {
        HSplitView {
            VStack(spacing: 0) {
                if store.statuses.isEmpty {
                    ContentUnavailableView("변경 사항 없음", systemImage: "checkmark.circle", description: Text("작업 복사본이 깨끗합니다."))
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
                    TextField("커밋 메시지", text: $commitMessage)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submitCommit() }
                    HStack {
                        Button("전체 선택") { store.selectedPaths = Set(store.statuses.map(\.path)) }
                        Button("선택 해제") { store.selectedPaths.removeAll() }
                        Spacer()
                        Text("\(store.selectedPaths.count)개 선택").foregroundStyle(.secondary)
                        Button("선택 항목 커밋") { submitCommit() }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.selectedPaths.isEmpty || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
                    }
                }
                .padding()
            }
            .frame(minWidth: 380)

            ScrollView([.horizontal, .vertical]) {
                Text(store.diff)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
            }
            .frame(minWidth: 400)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var historyView: some View {
        List(store.logs) { entry in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("r\(entry.revision)").font(.headline.monospacedDigit())
                    Text(entry.author.isEmpty ? "작성자 없음" : entry.author).foregroundStyle(.secondary)
                    Spacer()
                    if let date = entry.date { Text(date, format: .dateTime.year().month().day().hour().minute()).foregroundStyle(.secondary) }
                }
                Text(entry.message.isEmpty ? "커밋 메시지 없음" : entry.message)
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if store.logs.isEmpty { ContentUnavailableView("커밋 기록 없음", systemImage: "clock") }
        }
    }

    private func statusBadge(_ item: String) -> some View {
        Text(statusLabel(item))
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(statusColor(item), in: Capsule())
    }

    private func statusLabel(_ item: String) -> String {
        switch item {
        case "modified": "수정"
        case "added": "추가"
        case "deleted", "missing": "삭제"
        case "unversioned": "미추적"
        case "conflicted": "충돌"
        case "replaced": "교체"
        default: item
        }
    }

    private func statusColor(_ item: String) -> Color {
        switch item {
        case "modified": .orange
        case "added", "unversioned": .blue
        case "deleted", "missing", "conflicted": .red
        default: .gray
        }
    }

    private func submitCommit() {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        Task {
            if await store.commit(message: message) { commitMessage = "" }
        }
    }
}

private struct AddRepositoryView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var repositoryURL = ""
    @State private var destinationPath = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SVN 저장소 추가").font(.title2.bold())
                Text("저장소 URL을 체크아웃하고 작업 복사본 목록에 등록합니다.")
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text("저장소 URL")
                    TextField("https://server/svn/project/trunk", text: $repositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 440)
                }
                GridRow {
                    Text("로컬 폴더")
                    HStack {
                        TextField("/Users/name/Documents/project", text: $destinationPath)
                            .textFieldStyle(.roundedBorder)
                        Button("선택…") { chooseDestination() }
                    }
                }
                GridRow {
                    Text("사용자명")
                    TextField("SVN 계정명 (선택)", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("비밀번호")
                    SecureField("macOS Keychain에 저장 (선택)", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("인증은 기존 SVN 인증 캐시와 macOS Keychain을 사용합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("체크아웃 중…")
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
                Button("기존 작업 복사본 등록…") {
                    dismiss()
                    store.showFolderPicker()
                }
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("체크아웃 및 추가") {
                    Task {
                        if await store.checkout(repositoryURL: repositoryURL, destinationPath: destinationPath, username: username, password: password) {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
            }
        }
        .padding(24)
        .frame(width: 650)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "체크아웃할 로컬 폴더 선택"
        panel.prompt = "선택"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        destinationPath = destination.standardizedFileURL.path
    }
}

private struct CredentialsView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let project: SVNProject
    @State private var username: String
    @State private var newPassword = ""
    @State private var hasSavedPassword: Bool

    init(project: SVNProject) {
        self.project = project
        _username = State(initialValue: project.username ?? "")
        _hasSavedPassword = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("폴더별 인증 설정").font(.title2.bold())
                Text(project.name).foregroundStyle(.secondary)
                Text(project.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text("사용자명")
                    TextField("SVN 계정명", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 360)
                }
                GridRow {
                    Text("비밀번호")
                    SecureField(hasSavedPassword ? "비우면 기존 값 유지" : "비밀번호 입력", text: $newPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Label(
                hasSavedPassword ? "이 폴더의 비밀번호가 macOS Keychain에 저장되어 있습니다." : "저장된 비밀번호가 없습니다.",
                systemImage: hasSavedPassword ? "checkmark.shield" : "shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
            HStack {
                if hasSavedPassword {
                    Button("저장된 비밀번호 삭제", role: .destructive) {
                        if store.deleteSavedPassword(for: project.id) {
                            hasSavedPassword = false
                            newPassword = ""
                        }
                    }
                }
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("저장") {
                    if store.saveCredentials(for: project.id, username: username, newPassword: newPassword) {
                        dismiss()
                        Task { await store.refresh() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { hasSavedPassword = store.hasSavedPassword(for: project.id) }
    }
}
