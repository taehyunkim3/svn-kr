import AppKit
import SwiftUI
import SVNCore

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone
    @State private var commitMessage = ""

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
            if message == commitMessage { commitMessage = "" }
        }
        .alert(appLanguage.text("오류", "Error"), isPresented: Binding(get: { !store.isShowingAddRepository && store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button(appLanguage.text("확인", "OK"), role: .cancel) { store.errorMessage = nil }
                .help(appLanguage.text("오류 메시지를 닫습니다.", "Close the error message."))
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
                historyView
                    .tabItem { Label(appLanguage.text("커밋 기록", "Commit History"), systemImage: "clock.arrow.circlepath") }
            }
        }
    }

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
                        .onSubmit { submitCommit() }
                    HStack {
                        Button(appLanguage.text("전체 선택", "Select All")) { store.selectedPaths = Set(store.statuses.map(\.path)) }
                            .help(appLanguage.text("현재 변경된 파일을 모두 커밋 대상으로 선택합니다.", "Select all currently changed files for commit."))
                        Button(appLanguage.text("선택 해제", "Clear Selection")) { store.selectedPaths.removeAll() }
                            .help(appLanguage.text("현재 선택된 커밋 대상을 모두 해제합니다.", "Clear all selected commit targets."))
                        Spacer()
                        Text(appLanguage.text("\(store.selectedPaths.count)개 선택", "\(store.selectedPaths.count) selected")).foregroundStyle(.secondary)
                        Button(appLanguage.text("선택 항목 커밋", "Commit Selected")) { submitCommit() }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.selectedPaths.isEmpty || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
                            .help(appLanguage.text("선택한 파일을 입력한 메시지로 SVN 서버에 커밋합니다.", "Commit the selected files to the SVN server with the entered message."))
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
        VStack(spacing: 0) {
            if let headRevision = store.logs.first?.revision {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Label(appLanguage.text("서버 최신 r\(headRevision)", "Server latest r\(headRevision)"), systemImage: "cloud")
                        if let workingCopyRevision = store.workingCopyRevision {
                            Label(appLanguage.text("내 로컬 폴더 r\(workingCopyRevision)", "My local folder r\(workingCopyRevision)"), systemImage: "macbook")
                            if isWorkingCopyBehind(headRevision: headRevision, workingCopyRevision: workingCopyRevision) {
                                Text(appLanguage.text("업데이트 필요", "Update required"))
                                    .foregroundStyle(.orange)
                            } else {
                                Text(appLanguage.text("최신", "Up to date"))
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer()
                    }

                    HStack(spacing: 14) {
                        historyLegend(color: .blue, label: appLanguage.text("서버 커밋", "Server commit"))
                        historyLegend(color: .green, label: appLanguage.text("내 로컬 기준", "My local base"))
                        if !store.statuses.isEmpty {
                            historyLegend(color: .orange, label: appLanguage.text("미커밋 변경 \(store.statuses.count)개", "\(store.statuses.count) uncommitted changes"))
                        }
                        Spacer()
                    }
                }
                .font(.caption)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()
            }

            List {
                ForEach(Array(store.logs.enumerated()), id: \.element.id) { index, entry in
                    if workingCopyInsertionIndex == index, let workingCopyRevision = store.workingCopyRevision {
                        workingCopyMarkerRow(revision: workingCopyRevision, isBeforeLoadedHistory: false)
                    }

                    let isWorkingCopyEntry = entry.revision == workingCopyGraphEntryRevision
                    HStack(alignment: .top, spacing: 0) {
                        SVNHistoryGraphLane(
                            isFirst: index == 0,
                            isLast: index == store.logs.count - 1 && !isWorkingCopyBeforeLoadedHistory,
                            showsServerCommit: true,
                            isWorkingCopyRevision: isWorkingCopyEntry,
                            hasLocalChanges: isWorkingCopyEntry && !store.statuses.isEmpty
                        )
                        .frame(width: 76)
                        .help(appLanguage.text("파란 점은 서버 커밋, 초록 테두리는 내 로컬 기준, 주황 가지는 미커밋 변경을 뜻합니다.", "Blue dots are server commits, the green ring is your local base, and the orange branch is uncommitted work."))

                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text("r\(entry.revision)").font(.headline.monospacedDigit())
                                if entry.revision == store.logs.first?.revision {
                                    historyBadge(appLanguage.text("서버 최신", "Server latest"), color: .blue)
                                }
                                if isWorkingCopyEntry {
                                    historyBadge(workingCopyEntryBadge(for: entry.revision), color: .green)
                                    if !store.statuses.isEmpty {
                                        historyBadge(appLanguage.text("로컬 변경 \(store.statuses.count)개", "\(store.statuses.count) local changes"), color: .orange)
                                    }
                                }
                                Spacer()
                                if let date = entry.date {
                                    Text(formattedHistoryDate(date))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                } else {
                                    Text(appLanguage.text("커밋 시각 없음", "Commit time unavailable"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 12) {
                                Label(entry.author.isEmpty ? appLanguage.text("작성자 없음", "Unknown author") : entry.author, systemImage: "person")
                                if let email = entry.email, !email.isEmpty {
                                    Label(email, systemImage: "envelope")
                                        .textSelection(.enabled)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Text(entry.message.isEmpty ? appLanguage.text("커밋 메시지 없음", "No commit message") : entry.message)
                                .textSelection(.enabled)

                            if !entry.changedPaths.isEmpty {
                                DisclosureGroup(appLanguage.text("변경 경로 \(entry.changedPaths.count)개", "\(entry.changedPaths.count) changed paths")) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        ForEach(entry.changedPaths) { changedPath in
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                changedPathBadge(changedPath.action)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(changedPath.path)
                                                        .font(.caption.monospaced())
                                                        .textSelection(.enabled)
                                                    changedPathDetails(changedPath)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.top, 6)
                                }
                                .font(.caption)
                            }

                            if !entry.revisionProperties.isEmpty {
                                DisclosureGroup(appLanguage.text("추가 리비전 속성 \(entry.revisionProperties.count)개", "\(entry.revisionProperties.count) additional revision properties")) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        ForEach(entry.revisionProperties) { property in
                                            HStack(alignment: .firstTextBaseline) {
                                                Text(property.name)
                                                    .font(.caption.monospaced().bold())
                                                Text(property.value.isEmpty ? appLanguage.text("값 없음", "No value") : property.value)
                                                    .font(.caption)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                    .padding(.top, 6)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }

                if let workingCopyRevision = store.workingCopyRevision, isWorkingCopyBeforeLoadedHistory {
                    workingCopyMarkerRow(revision: workingCopyRevision, isBeforeLoadedHistory: true)
                }
            }
        }
        .overlay {
            if store.logs.isEmpty { ContentUnavailableView(appLanguage.text("커밋 기록 없음", "No Commit History"), systemImage: "clock") }
        }
    }

    private var workingCopyGraphEntryRevision: String? {
        guard let workingCopyRevision = store.workingCopyRevision,
              let headRevision = store.logs.first?.revision else { return nil }
        if let workingCopy = Int(workingCopyRevision), let head = Int(headRevision), workingCopy >= head {
            return headRevision
        }
        return store.logs.contains { $0.revision == workingCopyRevision } ? workingCopyRevision : nil
    }

    private var workingCopyInsertionIndex: Int? {
        guard workingCopyGraphEntryRevision == nil,
              let workingCopyRevision = store.workingCopyRevision,
              let workingCopy = Int(workingCopyRevision) else { return nil }
        return store.logs.firstIndex { entry in
            guard let revision = Int(entry.revision) else { return false }
            return revision < workingCopy
        }
    }

    private var isWorkingCopyBeforeLoadedHistory: Bool {
        guard store.workingCopyRevision != nil, !store.logs.isEmpty else { return false }
        return workingCopyGraphEntryRevision == nil && workingCopyInsertionIndex == nil
    }

    private func workingCopyEntryBadge(for entryRevision: String) -> String {
        entryRevision == store.workingCopyRevision
            ? appLanguage.text("내 로컬 기준", "My local base")
            : appLanguage.text("내 로컬에 포함", "Included locally")
    }

    private func workingCopyMarkerRow(revision: String, isBeforeLoadedHistory: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            SVNHistoryGraphLane(
                isFirst: store.logs.isEmpty,
                isLast: isBeforeLoadedHistory,
                showsServerCommit: false,
                isWorkingCopyRevision: true,
                hasLocalChanges: !store.statuses.isEmpty
            )
            .frame(width: 76, height: 72)

            VStack(alignment: .leading, spacing: 6) {
                if isBeforeLoadedHistory {
                    Text(appLanguage.text("… 이전 기록", "… Earlier history"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("r\(revision)").font(.headline.monospacedDigit())
                    historyBadge(appLanguage.text("내 로컬 기준", "My local base"), color: .green)
                    if !store.statuses.isEmpty {
                        historyBadge(appLanguage.text("로컬 변경 \(store.statuses.count)개", "\(store.statuses.count) local changes"), color: .orange)
                    }
                }
                Text(isBeforeLoadedHistory
                     ? appLanguage.text("내 로컬 기준 리비전이 최근 50개 서버 기록보다 이전입니다.", "Your local base revision is earlier than the latest 50 server records.")
                     : appLanguage.text("두 서버 커밋 사이의 내 로컬 갱신 기준입니다.", "Your local update base falls between two server commits."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    private func historyLegend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private func historyBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func isWorkingCopyBehind(headRevision: String, workingCopyRevision: String) -> Bool {
        guard let head = Int(headRevision), let workingCopy = Int(workingCopyRevision) else { return false }
        return workingCopy < head
    }

    private var historyTimeZone: TimeZone {
        if historyTimeZoneIdentifier == AppSettings.systemHistoryTimeZone {
            return .current
        }
        return TimeZone(identifier: historyTimeZoneIdentifier)
            ?? TimeZone(identifier: AppSettings.defaultHistoryTimeZone)
            ?? .current
    }

    private func formattedHistoryDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage == .english ? "en_US_POSIX" : "ko_KR")
        formatter.timeZone = historyTimeZone
        formatter.dateFormat = "yyyy-MM-dd (EEE) HH:mm:ss.SSS"
        let abbreviation = historyTimeZoneIdentifier == "Asia/Seoul"
            ? "KST"
            : (historyTimeZone.abbreviation(for: date) ?? historyTimeZone.identifier)
        return "\(formatter.string(from: date)) \(abbreviation)"
    }

    private func changedPathBadge(_ action: String) -> some View {
        Text(changedPathActionLabel(action))
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(changedPathActionColor(action), in: Capsule())
    }

    @ViewBuilder
    private func changedPathDetails(_ changedPath: SVNChangedPath) -> some View {
        let details = [
            changedPath.kind.map { $0 == "dir" ? appLanguage.text("폴더", "Folder") : appLanguage.text("파일", "File") },
            changedPath.textModified == "true" ? appLanguage.text("내용 변경", "Content changed") : nil,
            changedPath.propertiesModified == "true" ? appLanguage.text("속성 변경", "Properties changed") : nil,
        ].compactMap { $0 }

        if !details.isEmpty {
            Text(details.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if let copyFromPath = changedPath.copyFromPath {
            Text(appLanguage.text("복사 원본: \(copyFromPath)\(changedPath.copyFromRevision.map { "@r\($0)" } ?? "")", "Copied from: \(copyFromPath)\(changedPath.copyFromRevision.map { "@r\($0)" } ?? "")"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func changedPathActionLabel(_ action: String) -> String {
        switch action {
        case "A": appLanguage.text("추가", "Added")
        case "M": appLanguage.text("수정", "Modified")
        case "D": appLanguage.text("삭제", "Deleted")
        case "R": appLanguage.text("교체", "Replaced")
        default: action
        }
    }

    private func changedPathActionColor(_ action: String) -> Color {
        switch action {
        case "A": .blue
        case "M": .orange
        case "D": .red
        case "R": .purple
        default: .gray
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
        case "modified": appLanguage.text("수정", "Modified")
        case "added": appLanguage.text("추가", "Added")
        case "deleted", "missing": appLanguage.text("삭제", "Deleted")
        case "unversioned": appLanguage.text("미추적", "Unversioned")
        case "conflicted": appLanguage.text("충돌", "Conflict")
        case "replaced": appLanguage.text("교체", "Replaced")
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

private struct SVNHistoryGraphLane: View {
    @Environment(\.appLanguage) private var appLanguage
    let isFirst: Bool
    let isLast: Bool
    let showsServerCommit: Bool
    let isWorkingCopyRevision: Bool
    let hasLocalChanges: Bool

    var body: some View {
        Canvas { context, size in
            let serverX: CGFloat = 22
            let localX: CGFloat = 58
            let nodeY: CGFloat = min(24, size.height / 2)

            var serverLine = Path()
            serverLine.move(to: CGPoint(x: serverX, y: isFirst ? nodeY : 0))
            serverLine.addLine(to: CGPoint(x: serverX, y: isLast ? nodeY : size.height))
            context.stroke(serverLine, with: .color(.secondary.opacity(0.35)), lineWidth: 2)

            if showsServerCommit {
                let serverNode = CGRect(x: serverX - 5, y: nodeY - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: serverNode), with: .color(.blue))
            }

            if isWorkingCopyRevision {
                let localRing = CGRect(x: serverX - 9, y: nodeY - 9, width: 18, height: 18)
                context.stroke(Path(ellipseIn: localRing), with: .color(.green), lineWidth: 3)
            }

            if hasLocalChanges {
                var localBranch = Path()
                localBranch.move(to: CGPoint(x: serverX + 5, y: nodeY))
                localBranch.addCurve(
                    to: CGPoint(x: localX, y: nodeY),
                    control1: CGPoint(x: serverX + 18, y: nodeY),
                    control2: CGPoint(x: localX - 16, y: nodeY)
                )
                context.stroke(
                    localBranch,
                    with: .color(.orange),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3])
                )
                let localNode = CGRect(x: localX - 5, y: nodeY - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: localNode), with: .color(.orange))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if hasLocalChanges {
            return appLanguage.text("내 로컬 기준 리비전에서 미커밋 변경이 갈라져 있습니다.", "Uncommitted changes branch from your local base revision.")
        }
        if isWorkingCopyRevision {
            return appLanguage.text("내 로컬 기준 리비전입니다.", "This is your local base revision.")
        }
        return appLanguage.text("서버 커밋입니다.", "This is a server commit.")
    }
}

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
