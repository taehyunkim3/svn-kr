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
    private let onBrowseDemo: () -> Void

    init(onBrowseDemo: @escaping () -> Void = {}) {
        self.onBrowseDemo = onBrowseDemo
    }

    var body: some View {
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
                    if store.isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Text(store.isWorking
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
                .help(appLanguage.localized("ui.register.an.existing.svn.working.folder.in.the.a.361385a1"))
                Spacer()
                Button(appLanguage.localized("ui.browse.sample.project.9ad211da")) {
                    dismiss()
                    onBrowseDemo()
                }
                .help(appLanguage.localized("ui.explore.the.main.features.with.sample.data.and.n.fd16edf5"))
                Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help(appLanguage.localized("ui.cancel.adding.the.repository.and.close.this.wind.113063d1"))
                Button(appLanguage.localized("ui.check.out.and.add.ec5e3d09")) {
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
                .help(appLanguage.localized("ui.check.out.the.svn.repository.into.the.local.fold.4323a8e0"))
            }
        }
        .padding(24)
        .appSheetFrame(minimumSize: AppLayout.addRepositorySheetMinimumSize)
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

/// 프로젝트별 SVN 사용자명, Keychain 비밀번호, 인증서 예외를 관리합니다.
struct CredentialsView: View {
    @Environment(ProjectStore.self) private var store
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
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appLanguage.localized("ui.folder.credentials.b4bd68eb")).font(.title2.bold())
                Text(project.name).foregroundStyle(.secondary)
                Text(project.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
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
                    .help(appLanguage.localized("ui.close.without.saving.credential.changes.97c00986"))
                Button(appLanguage.localized("ui.save.7c93b7e1")) {
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
                .help(appLanguage.localized("ui.save.the.svn.username.and.new.password.for.this..72748974"))
            }
        }
        .padding(24)
        .frame(width: AppLayout.credentialsSheetWidth)
        .onAppear { hasSavedPassword = store.hasSavedPassword(for: project.id) }
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }
}

private struct CredentialFieldsGrid: View {
    @Environment(\.appLanguage) private var appLanguage
    @Binding var username: String
    @Binding var password: String
    let usernamePlaceholder: String
    let passwordPlaceholder: String

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
                SecureField(passwordPlaceholder, text: $password)
                    .textFieldStyle(.roundedBorder)
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
