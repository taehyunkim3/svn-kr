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
                        Label(project.name, systemImage: "shippingbox")
                            .tag(project.id)
                            .help(project.path)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(action: { store.isShowingAddRepository = true }) { Image(systemName: "plus") }
                    Button(action: store.removeSelectedProject) { Image(systemName: "minus") }
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
        .alert("오류", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
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
            }

            Text("인증은 기존 SVN 인증 캐시와 macOS Keychain을 사용합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                        if await store.checkout(repositoryURL: repositoryURL, destinationPath: destinationPath) {
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
        panel.title = "체크아웃할 상위 폴더 선택"
        panel.prompt = "선택"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        destinationPath = parent.appendingPathComponent(suggestedFolderName).path
    }

    private var suggestedFolderName: String {
        let trimmed = repositoryURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let name = trimmed.split(separator: "/").last.map(String.init) ?? "svn-project"
        return name.removingPercentEncoding ?? name
    }
}
