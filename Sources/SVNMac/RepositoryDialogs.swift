import AppKit
import SwiftUI

/// Keychain 접근이 거부됐을 때 사용자가 인증 방식을 다시 선택하는 화면입니다.
/// 원래 수행하려던 작업은 `SVNAuthenticationRequest`에 보존되어 인증 성공 후 재개됩니다.
struct AuthenticationRequiredView: View {
    @Environment(ProjectStore.self) private var store
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
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appLanguage.localized("ui.svn.authentication.required.797a2cdb"))
                    .font(.title2.bold())
                Text(reasonText)
                    .foregroundStyle(.secondary)
            }

            CredentialFieldsGrid(
                username: $username,
                password: $password,
                usernamePlaceholder: appLanguage.localized("ui.svn.username.90a19d48"),
                passwordPlaceholder: appLanguage.localized("ui.svn.password.5e0660b7")
            )

            Text(appLanguage.localized("ui.canceling.does.not.prevent.viewing.local.changes.cf7ece9c"))
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
            HStack {
                Button(appLanguage.localized("ui.try.keychain.again.a762f607")) {
                    isSubmitting = true
                    Task {
                        await store.retryKeychainAccess(for: request)
                        isSubmitting = false
                    }
                }
                .disabled(isSubmitting)
                .help(appLanguage.localized("ui.show.the.macos.keychain.access.prompt.again.d57d9f96"))
                Spacer()
                Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {
                    store.cancelAuthentication(for: request)
                }
                .keyboardShortcut(.cancelAction)
                Button(appLanguage.localized("ui.use.this.session.only.08dcce43")) {
                    submit(saveInKeychain: false)
                }
                .disabled(!canSubmit)
                Button(appLanguage.localized("ui.save.in.keychain.and.use.9c0fd0d4")) {
                    submit(saveInKeychain: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(width: AppLayout.authenticationSheetWidth)
        .onAppear {
            username = store.projects.first(where: { $0.id == request.projectID })?.username ?? ""
        }
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
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
            appLanguage.localized("ui.authentication.is.required.to.load.the.latest.se.2b552fac")
        case .update:
            appLanguage.localized("ui.authentication.is.required.to.download.the.lates.83127c9a")
        case .commit:
            appLanguage.localized("ui.authentication.is.required.to.commit.the.selecte.4837ef80")
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
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @AppStorage(AppSettings.languageKey)
    private var languageIdentifier = AppSettings.defaultLanguage
    @State private var repositoryURL = ""
    @State private var destinationURL: URL?
    @State private var username = ""
    @State private var password = ""
    @State private var allowsUntrustedServerCertificate = false
    @State private var isConfirmingCheckoutCancellation = false
    private let onBrowseDemo: () -> Void

    init(onBrowseDemo: @escaping () -> Void = {}) {
        self.onBrowseDemo = onBrowseDemo
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(appLanguage.localized("ui.add.svn.repository.8b9639fa")).font(.title2.bold())
                    Text(appLanguage.localized("ui.check.out.a.repository.url.and.add.it.to.your.lo.63f0d7ea"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Button {
                            languageIdentifier = language.rawValue
                        } label: {
                            if language.rawValue == languageIdentifier {
                                Label(language.displayName, systemImage: "checkmark")
                            } else {
                                Text(language.displayName)
                            }
                        }
                    }
                } label: {
                    Label(appLanguage.localized("ui.language.8e5b78fb"), systemImage: "globe")
                }
                .fixedSize()
                .help(appLanguage.localized("ui.choose.the.language.used.in.the.app.interface.16c2f863"))
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text(appLanguage.localized("ui.repository.url.a29f5816"))
                    TextField("https://server/svn/project/trunk", text: $repositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: AppLayout.repositoryURLFieldMinimumWidth)
                }
                GridRow {
                    Text(appLanguage.localized("ui.local.folder.63f176e1"))
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
                        Button(appLanguage.localized("ui.choose.71d0de8d")) { chooseDestination() }
                            .help(appLanguage.localized("ui.choose.the.local.folder.for.the.checkout.31ee0035"))
                    }
                }
            }

            CredentialFieldsGrid(
                username: $username,
                password: $password,
                usernamePlaceholder: appLanguage.localized("ui.svn.username.optional.fff42bd5"),
                passwordPlaceholder: appLanguage.localized("ui.save.in.macos.keychain.optional.d544f3fd")
            )

            Text(appLanguage.localized("ui.authentication.uses.the.existing.svn.credential..b6c6fe66"))
                .font(.caption)
                .foregroundStyle(.secondary)

            UntrustedCertificateToggle(
                isAllowed: $allowsUntrustedServerCertificate,
                help: appLanguage.localized("ui.use.only.for.servers.with.self.signed.certificat.cd3b5e55")
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if store.isCheckingOut {
                        ProgressView().controlSize(.small)
                    }
                    Text(store.isCheckingOut
                        ? appLanguage.localized("ui.checking.out.3944eb2e")
                        : appLanguage.localized("ui.checkout.progress.log.ba2c92de"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let errorMessage = store.errorMessage {
                        ErrorCopyButton(message: errorMessage)
                    }
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.checkoutLog.isEmpty
                                ? appLanguage.localized("ui.files.being.downloaded.will.appear.here.after.ch.9dfb3816")
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
                Button(appLanguage.localized("ui.register.existing.local.folder.fcf466c4")) {
                    dismiss()
                    store.showFolderPicker()
                }
                .disabled(store.isCheckingOut)
                .help(appLanguage.localized("ui.register.an.existing.svn.working.folder.in.the.a.361385a1"))
                Spacer()
                Button(appLanguage.localized("ui.browse.sample.project.9ad211da")) {
                    dismiss()
                    onBrowseDemo()
                }
                .disabled(store.isCheckingOut)
                .help(appLanguage.localized("ui.explore.the.main.features.with.sample.data.and.n.fd16edf5"))
                Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) { requestCancellation() }
                    .keyboardShortcut(.cancelAction)
                    .help(appLanguage.localized("ui.cancel.adding.the.repository.and.close.this.wind.113063d1"))
                Button {
                    Task {
                        if await store.startCheckout(
                            repositoryURL: repositoryURL,
                            destinationURL: destinationURL,
                            username: username,
                            password: password,
                            allowsUntrustedServerCertificate: allowsUntrustedServerCertificate
                        ) {
                            dismiss()
                        }
                    }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized("ui.check.out.and.add.ec5e3d09"),
                        inProgressTitle: appLanguage.localized("ui.checking.out.3944eb2e"),
                        isInProgress: store.isCheckingOut
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || destinationURL == nil || store.isWorking)
                .help(appLanguage.localized("ui.check.out.the.svn.repository.into.the.local.fold.4323a8e0"))
            }
        }
        .padding(24)
        .appSheetFrame(minimumSize: AppLayout.addRepositorySheetMinimumSize)
        // 체크아웃 도중 시트가 그냥 닫히면 svn 프로세스만 백그라운드에 남습니다.
        // 닫는 경로를 취소 확인 한곳으로 모읍니다.
        .interactiveDismissDisabled(store.isCheckingOut)
        .alert(
            appLanguage.localized("ui.stop.the.checkout.in.progress.5d0c9b71"),
            isPresented: $isConfirmingCheckoutCancellation
        ) {
            Button(appLanguage.localized("ui.stop.checkout.b0f4e2a7"), role: .destructive) {
                store.cancelCheckout()
            }
            Button(appLanguage.localized("ui.keep.downloading.3c1de80f"), role: .cancel) {}
        } message: {
            Text(appLanguage.localized("ui.the.running.svn.checkout.will.be.stopped.already.4b7d5a19"))
        }
        .sheet(item: $store.canceledCheckoutRecoveryRequest) { request in
            CanceledCheckoutRecoveryView(request: request)
                .environment(store)
        }
    }

    /// 체크아웃이 도는 중이면 되돌리기 어려운 결정이므로 한 번 더 확인합니다.
    private func requestCancellation() {
        guard store.isCheckingOut else {
            dismiss()
            return
        }
        isConfirmingCheckoutCancellation = true
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = appLanguage.localized("ui.choose.local.checkout.folder.c649aa9f")
        panel.prompt = appLanguage.localized("ui.choose.0a13aec8")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        destinationURL = destination.standardizedFileURL
    }
}

/// 프로젝트별 로컬 폴더 위치, SVN 사용자명, Keychain 비밀번호, 인증서 예외를 관리합니다.
struct CredentialsView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    let project: SVNProject
    @State private var username: String
    @State private var newPassword = ""
    @State private var hasSavedPassword: Bool
    @State private var allowsUntrustedServerCertificate: Bool
    @State private var relocatedURL: URL?
    @State private var originalPath: String
    @State private var credentialFailureMessage: String?

    init(project: SVNProject) {
        self.project = project
        _username = State(initialValue: project.username ?? "")
        _hasSavedPassword = State(initialValue: false)
        _allowsUntrustedServerCertificate = State(initialValue: project.allowsUntrustedServerCertificate == true)
        _originalPath = State(initialValue: project.path)
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appLanguage.localized("ui.folder.settings.6f2a0d43")).font(.title2.bold())
                Text(project.name).foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text(appLanguage.localized("ui.local.folder.63f176e1"))
                    HStack {
                        TextField(
                            "",
                            text: Binding(
                                get: { pendingPath },
                                set: { _ in }
                            )
                        )
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        Button(appLanguage.localized("ui.change.7c3aa7d1")) { chooseWorkingFolder() }
                            .disabled(store.isRelocatingProject)
                            .help(appLanguage.localized("ui.pick.the.new.location.of.this.svn.working.folder.0c58fa9e"))
                    }
                }
            }

            if pendingPath != project.path {
                Label(
                    appLanguage.localized("ui.the.new.folder.is.applied.when.you.save.2b70a1cd"),
                    systemImage: "arrow.triangle.swap"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            CredentialFieldsGrid(
                username: $username,
                password: $newPassword,
                usernamePlaceholder: appLanguage.localized("ui.svn.username.90a19d48"),
                passwordPlaceholder: hasSavedPassword
                    ? appLanguage.localized("ui.leave.blank.to.keep.the.current.password.5f89ccfa")
                    : appLanguage.localized("ui.enter.password.48ff7123")
            )

            Label(
                hasSavedPassword
                    ? appLanguage.localized("ui.a.password.for.this.folder.is.stored.in.macos.ke.676ba875")
                    : appLanguage.localized("ui.no.password.is.stored.44110abb"),
                systemImage: hasSavedPassword ? "checkmark.shield" : "shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            UntrustedCertificateToggle(
                isAllowed: $allowsUntrustedServerCertificate,
                help: appLanguage.localized("ui.allow.self.signed.and.certificate.name.mismatch..0bfb9514")
            )

            Divider()
            HStack {
                Button {
                    store.requestSelectedWorkingCopyCleanup()
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized("ui.working.copy.cleanup.62f3ac11"),
                        inProgressTitle: appLanguage.localized("ui.cleaning.working.copy.2a9ed647"),
                        systemImage: "wrench.and.screwdriver",
                        isInProgress: store.isCleaningSelectedWorkingCopy
                    )
                }
                .disabled(isSaving || store.isCleaningSelectedWorkingCopy)
                .help(appLanguage.localized("ui.cleanup.interrupted.working.copy.manually.46d93c1e"))
                if hasSavedPassword {
                    Button(appLanguage.localized("ui.delete.saved.password.a38fa5cf"), role: .destructive) {
                        if store.deleteSavedPassword(for: project.id) {
                            hasSavedPassword = false
                            newPassword = ""
                        }
                    }
                    .help(appLanguage.localized("ui.delete.the.svn.password.stored.in.keychain.for.t.e0944666"))
                }
                Spacer()
                Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                    .help(appLanguage.localized("ui.close.without.saving.credential.changes.97c00986"))
                Button(action: save) {
                    ActionProgressLabel(
                        title: appLanguage.localized("ui.save.7c93b7e1"),
                        inProgressTitle: store.isVerifyingCredentials
                            ? appLanguage.localized("ui.checking.the.account.c47f1a90")
                            : appLanguage.localized("ui.saving.6a1b2f0c"),
                        isInProgress: isSaving
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
                .help(appLanguage.localized("ui.save.the.working.folder.location.svn.username.an.4f0a7c19"))
            }
        }
        .padding(24)
        .frame(width: AppLayout.credentialsSheetWidth)
        .onAppear { hasSavedPassword = store.hasSavedPassword(for: project.id) }
        .sheet(item: $store.workingCopyCleanupRequest) { request in
            WorkingCopyCleanupView(request: request)
                .environment(store)
        }
        .alert(
            appLanguage.localized("ui.the.svn.account.or.password.is.not.valid.6d81e3f4"),
            isPresented: .isPresenting($credentialFailureMessage),
            presenting: credentialFailureMessage
        ) { _ in
            Button(appLanguage.localized("ui.enter.valid.credentials.9a70c5b2")) {
                credentialFailureMessage = nil
            }
            Button(appLanguage.localized("ui.discard.changes.and.close.4e12b8a7"), role: .cancel) {
                credentialFailureMessage = nil
                discardChanges()
            }
        } message: { message in
            Text(message)
        }
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private var isSaving: Bool {
        store.isRelocatingProject || store.isVerifyingCredentials
    }

    private var pendingPath: String {
        relocatedURL?.path ?? project.path
    }

    private func chooseWorkingFolder() {
        let panel = NSOpenPanel()
        panel.title = appLanguage.localized("ui.choose.svn.local.working.folders.6d104bc9")
        panel.prompt = appLanguage.localized("ui.choose.0a13aec8")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: project.path, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        relocatedURL = url.standardizedFileURL
    }

    /// 폴더 이동과 자격 증명 변경을 한 번의 저장으로 처리합니다.
    ///
    /// 자격 증명은 서버 확인을 통과한 뒤에만 Keychain과 프로젝트 목록에 기록합니다.
    /// 확인 전에는 아무것도 바꾸지 않으므로 사용자가 재입력을 고르면 이전 설정이 그대로 남습니다.
    private func save() {
        Task {
            if let relocatedURL, relocatedURL.path != project.path {
                guard await store.relocateProject(project.id, to: relocatedURL) else { return }
            }
            if let failure = await store.verifyCredentials(
                for: project.id,
                username: username,
                password: newPassword,
                allowsUntrustedServerCertificate: allowsUntrustedServerCertificate
            ) {
                credentialFailureMessage = failure
                return
            }
            guard store.saveCredentials(
                for: project.id,
                username: username,
                newPassword: newPassword,
                allowsUntrustedServerCertificate: allowsUntrustedServerCertificate
            ) else { return }
            dismiss()
            await store.refresh()
        }
    }

    /// 확인에 실패한 입력을 버리고 시트를 열었을 때의 상태로 되돌립니다.
    /// 자격 증명은 아직 저장되지 않았으므로 이 화면에서 바꾼 폴더 위치만 복구하면 됩니다.
    private func discardChanges() {
        Task {
            if store.projects.first(where: { $0.id == project.id })?.path != originalPath {
                _ = await store.relocateProject(
                    project.id,
                    to: URL(fileURLWithPath: originalPath, isDirectory: true)
                )
            }
            relocatedURL = nil
            username = project.username ?? ""
            newPassword = ""
            allowsUntrustedServerCertificate = project.allowsUntrustedServerCertificate == true
            dismiss()
        }
    }
}

private struct CredentialFieldsGrid: View {
    @Environment(\.appLanguage) private var appLanguage
    @Binding var username: String
    @Binding var password: String
    let usernamePlaceholder: String
    let passwordPlaceholder: String
    @State private var isPasswordRevealed = false

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
            GridRow {
                Text(appLanguage.localized("ui.username.4e1b650a"))
                TextField(usernamePlaceholder, text: $username)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: AppLayout.credentialFieldMinimumWidth)
            }
            GridRow {
                Text(appLanguage.localized("ui.password.945c94ed"))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        // macOS의 보안 입력 필드는 입력기를 막기 때문에 가려진 상태로는
                        // 한글을 조합할 수 없습니다. 표시 상태에서는 일반 필드를 써서
                        // 같은 값을 한글 입력기로도 입력할 수 있게 합니다.
                        if isPasswordRevealed {
                            TextField(passwordPlaceholder, text: $password)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField(passwordPlaceholder, text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            isPasswordRevealed.toggle()
                        } label: {
                            Image(systemName: isPasswordRevealed ? "eye.slash" : "eye")
                                .frame(width: 14, height: 14)
                        }
                        .buttonStyle(.bordered)
                        .help(isPasswordRevealed
                            ? appLanguage.localized("ui.hide.password.4c8a1f60")
                            : appLanguage.localized("ui.show.password.9b3d2e71"))
                        .accessibilityLabel(isPasswordRevealed
                            ? appLanguage.localized("ui.hide.password.4c8a1f60")
                            : appLanguage.localized("ui.show.password.9b3d2e71"))
                    }
                    if !isPasswordRevealed {
                        Text(appLanguage.localized("ui.secure.entry.blocks.the.korean.input.method.reve.3f7b0c25"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct UntrustedCertificateToggle: View {
    @Environment(\.appLanguage) private var appLanguage
    @Binding var isAllowed: Bool
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                appLanguage.localized("ui.allow.untrusted.ssl.certificates.78b94750"),
                isOn: $isAllowed
            )
            .toggleStyle(.checkbox)
            .help(help)

            Text(appLanguage.localized("ui.use.this.when.the.target.server.s.certificate.is.2fa0c076"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
