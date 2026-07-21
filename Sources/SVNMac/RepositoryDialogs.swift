import AppKit
import SwiftUI

/// Keychain 접근이 거부됐을 때 사용자가 인증 방식을 다시 선택하는 화면입니다.
/// 원래 수행하려던 작업은 `SVNAuthenticationRequest`에 보존되어 인증 성공 후 재개됩니다.
struct AuthenticationRequiredView: View {
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
struct AddRepositoryView: View {
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

            VStack(alignment: .leading, spacing: 4) {
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

                Text(appLanguage.text(
                    "대상 서버의 인증서가 유효하지 않지만, 해당 서버를 신뢰하는 경우에 사용합니다.",
                    "Use this when the target server's certificate is invalid but you trust the server."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if store.isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Text(store.isWorking
                        ? appLanguage.text("체크아웃 중…", "Checking out…")
                        : appLanguage.text("체크아웃 진행 로그", "Checkout progress log"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.checkoutLog.isEmpty
                                ? appLanguage.text(
                                    "체크아웃을 시작하면 내려받는 파일이 여기에 표시됩니다.",
                                    "Files being downloaded will appear here after checkout starts."
                                )
                                : store.checkoutLog)
                                .foregroundStyle(store.checkoutLog.isEmpty ? .secondary : .primary)

                            if let errorMessage = store.errorMessage {
                                Divider()
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("checkout-log-bottom")
                    }
                    .onChange(of: store.checkoutLog) { _, _ in
                        proxy.scrollTo("checkout-log-bottom", anchor: .bottom)
                    }
                    .onChange(of: store.errorMessage) { _, _ in
                        proxy.scrollTo("checkout-log-bottom", anchor: .bottom)
                    }
                }
                .frame(height: AppLayout.checkoutLogHeight)
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                }
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
        .appSheetFrame(minimumSize: AppLayout.addRepositorySheetMinimumSize)
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
struct CredentialsView: View {
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

            VStack(alignment: .leading, spacing: 4) {
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

                Text(appLanguage.text(
                    "대상 서버의 인증서가 유효하지 않지만, 해당 서버를 신뢰하는 경우에 사용합니다.",
                    "Use this when the target server's certificate is invalid but you trust the server."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

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
