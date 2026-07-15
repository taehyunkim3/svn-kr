import SwiftUI
import SVNCore

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone
    @State private var commitMessage = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedProjectID) {
                Section("로컬 작업 폴더") {
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
                    .help("새 SVN 저장소를 체크아웃하거나 기존 로컬 작업 폴더를 등록합니다.")

                    Button(action: store.removeSelectedProject) {
                        Image(systemName: "minus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 30, height: 24)
                    .disabled(store.selectedProject == nil)
                    .help("선택한 로컬 작업 폴더를 앱 목록에서 제거합니다. 로컬 파일은 삭제하지 않습니다.")
                    Spacer()
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 230)
        } detail: {
            if let project = store.selectedProject {
                projectView(project)
            } else {
                ContentUnavailableView("로컬 작업 폴더를 추가하세요", systemImage: "externaldrive.badge.plus", description: Text("⌘O를 누르거나 왼쪽 아래 + 버튼을 사용하세요."))
            }
        }
        .toolbar {
            Button("새로고침", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                .disabled(store.selectedProject == nil || store.isWorking)
                .help("로컬 변경 사항과 최신 서버 커밋 기록을 다시 불러옵니다.")
            Button("업데이트", systemImage: "arrow.down.circle") { Task { await store.update() } }
                .disabled(store.selectedProject == nil || store.isWorking)
                .help("서버의 최신 변경 사항을 현재 로컬 작업 폴더에 내려받습니다.")
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
                .help("오류 메시지를 닫습니다.")
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
                .help("이 로컬 작업 폴더에서 사용할 SVN 계정과 Keychain 비밀번호를 설정합니다.")
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
                    ContentUnavailableView("변경 사항 없음", systemImage: "checkmark.circle", description: Text("로컬에서 수정된 파일이 없습니다."))
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
                                .help("이 파일을 다음 선택 커밋에 포함하거나 제외합니다.")
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
                            .help("현재 변경된 파일을 모두 커밋 대상으로 선택합니다.")
                        Button("선택 해제") { store.selectedPaths.removeAll() }
                            .help("현재 선택된 커밋 대상을 모두 해제합니다.")
                        Spacer()
                        Text("\(store.selectedPaths.count)개 선택").foregroundStyle(.secondary)
                        Button("선택 항목 커밋") { submitCommit() }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.selectedPaths.isEmpty || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
                            .help("선택한 파일을 입력한 메시지로 SVN 서버에 커밋합니다.")
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
                        Label("서버 최신 r\(headRevision)", systemImage: "cloud")
                        if let workingCopyRevision = store.workingCopyRevision {
                            Label("내 로컬 폴더 r\(workingCopyRevision)", systemImage: "macbook")
                            if isWorkingCopyBehind(headRevision: headRevision, workingCopyRevision: workingCopyRevision) {
                                Text("업데이트 필요")
                                    .foregroundStyle(.orange)
                            } else {
                                Text("최신")
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer()
                    }

                    HStack(spacing: 14) {
                        historyLegend(color: .blue, label: "서버 커밋")
                        historyLegend(color: .green, label: "내 로컬 기준")
                        if !store.statuses.isEmpty {
                            historyLegend(color: .orange, label: "미커밋 변경 \(store.statuses.count)개")
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
                        .help("파란 점은 서버 커밋, 초록 테두리는 내 로컬 기준, 주황 가지는 미커밋 변경을 뜻합니다.")

                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text("r\(entry.revision)").font(.headline.monospacedDigit())
                                if entry.revision == store.logs.first?.revision {
                                    historyBadge("서버 최신", color: .blue)
                                }
                                if isWorkingCopyEntry {
                                    historyBadge(workingCopyEntryBadge(for: entry.revision), color: .green)
                                    if !store.statuses.isEmpty {
                                        historyBadge("로컬 변경 \(store.statuses.count)개", color: .orange)
                                    }
                                }
                                Spacer()
                                if let date = entry.date {
                                    Text(formattedHistoryDate(date))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                } else {
                                    Text("커밋 시각 없음")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 12) {
                                Label(entry.author.isEmpty ? "작성자 없음" : entry.author, systemImage: "person")
                                if let email = entry.email, !email.isEmpty {
                                    Label(email, systemImage: "envelope")
                                        .textSelection(.enabled)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Text(entry.message.isEmpty ? "커밋 메시지 없음" : entry.message)
                                .textSelection(.enabled)

                            if !entry.changedPaths.isEmpty {
                                DisclosureGroup("변경 경로 \(entry.changedPaths.count)개") {
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
                                DisclosureGroup("추가 리비전 속성 \(entry.revisionProperties.count)개") {
                                    VStack(alignment: .leading, spacing: 5) {
                                        ForEach(entry.revisionProperties) { property in
                                            HStack(alignment: .firstTextBaseline) {
                                                Text(property.name)
                                                    .font(.caption.monospaced().bold())
                                                Text(property.value.isEmpty ? "값 없음" : property.value)
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
            if store.logs.isEmpty { ContentUnavailableView("커밋 기록 없음", systemImage: "clock") }
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
        entryRevision == store.workingCopyRevision ? "내 로컬 기준" : "내 로컬에 포함"
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
                    Text("… 이전 기록")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("r\(revision)").font(.headline.monospacedDigit())
                    historyBadge("내 로컬 기준", color: .green)
                    if !store.statuses.isEmpty {
                        historyBadge("로컬 변경 \(store.statuses.count)개", color: .orange)
                    }
                }
                Text(isBeforeLoadedHistory
                     ? "내 로컬 기준 리비전이 최근 50개 서버 기록보다 이전입니다."
                     : "두 서버 커밋 사이의 내 로컬 갱신 기준입니다.")
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
        formatter.locale = Locale(identifier: "ko_KR")
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
            changedPath.kind.map { $0 == "dir" ? "폴더" : "파일" },
            changedPath.textModified == "true" ? "내용 변경" : nil,
            changedPath.propertiesModified == "true" ? "속성 변경" : nil,
        ].compactMap { $0 }

        if !details.isEmpty {
            Text(details.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if let copyFromPath = changedPath.copyFromPath {
            Text("복사 원본: \(copyFromPath)\(changedPath.copyFromRevision.map { "@r\($0)" } ?? "")")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func changedPathActionLabel(_ action: String) -> String {
        switch action {
        case "A": "추가"
        case "M": "수정"
        case "D": "삭제"
        case "R": "교체"
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

private struct SVNHistoryGraphLane: View {
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
            return "내 로컬 기준 리비전에서 미커밋 변경이 갈라져 있습니다."
        }
        if isWorkingCopyRevision {
            return "내 로컬 기준 리비전입니다."
        }
        return "서버 커밋입니다."
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
                Text("저장소 URL을 체크아웃하고 로컬 작업 폴더 목록에 등록합니다.")
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
                            .help("체크아웃 결과를 저장할 로컬 폴더를 선택합니다.")
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
                Button("기존 로컬 폴더 등록…") {
                    dismiss()
                    store.showFolderPicker()
                }
                .help("이미 체크아웃된 SVN 로컬 작업 폴더를 앱 목록에 등록합니다.")
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("저장소 추가를 취소하고 창을 닫습니다.")
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
                .help("입력한 SVN 저장소를 로컬 폴더에 체크아웃하고 앱에 등록합니다.")
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
                    .help("이 로컬 작업 폴더용으로 Keychain에 저장된 SVN 비밀번호를 삭제합니다.")
                }
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("인증 설정 변경을 저장하지 않고 창을 닫습니다.")
                Button("저장") {
                    if store.saveCredentials(for: project.id, username: username, newPassword: newPassword) {
                        dismiss()
                        Task { await store.refresh() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("입력한 SVN 사용자명과 새 비밀번호를 이 로컬 작업 폴더에 저장합니다.")
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { hasSavedPassword = store.hasSavedPassword(for: project.id) }
    }
}
