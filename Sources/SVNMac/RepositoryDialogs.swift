import AppKit
import SVNCore
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

    @ViewBuilder
    var body: some View {
        if let trust = request.serverCertificateTrust {
            ServerCertificateTrustView(request: request, trust: trust)
        } else {
            authenticationForm
        }
    }

    private var authenticationForm: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appLanguage.localized(.ui.authentication.svnAuthenticationRequired))
                    .font(.title2.bold())
                Text(reasonText)
                    .foregroundStyle(.secondary)
            }

            CredentialFieldsGrid(
                username: $username,
                password: $password,
                usernamePlaceholder: appLanguage.localized(.ui.authentication.svnUsername),
                passwordPlaceholder: appLanguage.localized(.ui.authentication.svnPassword)
            )

            Text(appLanguage.localized(.ui.authentication.cancelingDoesNotPreventViewingLocalChangesDiffs))
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
            HStack {
                Button(appLanguage.localized(.ui.authentication.tryKeychainAgain)) {
                    isSubmitting = true
                    Task {
                        await store.retryKeychainAccess(for: request)
                        isSubmitting = false
                    }
                }
                .disabled(isSubmitting)
                .help(appLanguage.localized(.ui.authentication.showMacosKeychainAccessPromptAgain))
                Spacer()
                Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                    store.cancelAuthentication(for: request)
                }
                .keyboardShortcut(.cancelAction)
                Button(appLanguage.localized(.ui.authentication.useSessionOnly)) {
                    submit(saveInKeychain: false)
                }
                .disabled(!canSubmit)
                Button(appLanguage.localized(.ui.authentication.saveKeychainUse)) {
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
            appLanguage.localized(.ui.authentication.requiredLoadLatestServerHistory)
        case .update:
            appLanguage.localized(.ui.authentication.requiredDownloadLatestServerChanges)
        case .commit:
            appLanguage.localized(.ui.authentication.requiredCommitSelectedChanges)
        case .retryManually:
            appLanguage.localized(.ui.authentication.requiredLoadLatestServerHistory)
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

private struct ServerCertificateTrustView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    let request: SVNAuthenticationRequest
    let trust: ServerCertificateTrust

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label(
                    appLanguage.localized(.ui.certificate.serverCertificateProblem),
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.title2.bold())
                .foregroundStyle(.orange)
                Text(appLanguage.localized(.ui.certificate.svnRejectedServerCertificateReviewDetectedProblemBeforeDeciding))
                    .foregroundStyle(.secondary)
            }

            ForEach(orderedFailures, id: \.self) { failure in
                Text(SVNErrorLocalization.serverCertificateGuidance(
                    for: failure,
                    language: appLanguage
                ))
            }

            Text(appLanguage.localized(.ui.certificate.exceptionSecurityWarning))
                .font(.callout.weight(.semibold))

            Text(trust.diagnosticDetails)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(8)

            Divider()
            HStack {
                Spacer()
                Button(appLanguage.localized(.ui.certificate.doNotAllow), role: .cancel) {
                    store.cancelAuthentication(for: request)
                }
                .keyboardShortcut(.cancelAction)
                if trust.canAllow {
                    Button(
                        appLanguage.localized(.ui.certificate.allowProject),
                        role: .destructive
                    ) {
                        store.allowServerCertificateFailure(for: request)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: AppLayout.authenticationSheetWidth)
    }

    private var orderedFailures: [SVNServerCertificateFailure] {
        SVNServerCertificateFailure.allCases.filter(trust.failures.contains)
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
    @State private var isShowingRepositoryBrowser = false
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
                    Text(appLanguage.localized(.ui.repository.addSvnRepository)).font(.title2.bold())
                    Text(appLanguage.localized(.ui.checkout.checkOutRepositoryUrlAddItLocalWorkingFolders))
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
                    Label(appLanguage.localized(.ui.settings.language), systemImage: "globe")
                }
                .fixedSize()
                .help(appLanguage.localized(.ui.settings.chooseLanguageUsedAppInterface))
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text(appLanguage.localized(.ui.browser.repositoryUrl))
                    HStack {
                        TextField("https://server/svn/project/trunk", text: $repositoryURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: AppLayout.repositoryURLFieldMinimumWidth)
                        Button(appLanguage.localized(.ui.browser.browseRepository)) {
                            store.recoveryState.repositoryBrowseSelectedURL = nil
                            isShowingRepositoryBrowser = true
                        }
                        .disabled(store.isWorking)
                    }
                }
                GridRow {
                    Text(appLanguage.localized(.ui.repository.localFolder))
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
                        Button(appLanguage.localized(.ui.repository.localFolderPickerAction)) { chooseDestination() }
                            .help(appLanguage.localized(.ui.checkout.localFolderPickerHelp))
                    }
                }
            }

            CredentialFieldsGrid(
                username: $username,
                password: $password,
                usernamePlaceholder: appLanguage.localized(.ui.authentication.svnUsernameOptional),
                passwordPlaceholder: appLanguage.localized(.ui.authentication.saveMacosKeychainOptional)
            )

            Text(appLanguage.localized(.ui.authentication.usesExistingSvnCredentialCacheMacosKeychain))
                .font(.caption)
                .foregroundStyle(.secondary)

            UntrustedCertificateToggle(
                isAllowed: $allowsUntrustedServerCertificate,
                help: appLanguage.localized(.ui.certificate.useOnlyServersSelfSignedCertificatesCertificateNameMismatches)
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if store.isCheckingOut {
                        ProgressView().controlSize(.small)
                    }
                    Text(store.isCheckingOut
                        ? appLanguage.localized(.ui.checkout.checkingOut)
                        : appLanguage.localized(.ui.checkout.progressLog))
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
                                ? appLanguage.localized(.ui.checkout.filesDownloadedAppearHereAfterCheckoutStarts)
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
                Button(appLanguage.localized(.ui.repository.registerExistingLocalFolder)) {
                    dismiss()
                    store.showFolderPicker()
                }
                .disabled(store.isCheckingOut)
                .help(appLanguage.localized(.ui.repository.registerExistingSvnWorkingFolderApp))
                Spacer()
                Button(appLanguage.localized(.ui.demo.browseSampleProject)) {
                    dismiss()
                    onBrowseDemo()
                }
                .disabled(store.isCheckingOut)
                .help(appLanguage.localized(.ui.demo.exploreMainFeaturesSampleDataNoServerConnectionAccount))
                Button(appLanguage.localized(.ui.common.cancel), role: .cancel) { requestCancellation() }
                    .keyboardShortcut(.cancelAction)
                    .help(appLanguage.localized(.ui.repository.cancelAddingRepositoryCloseWindow))
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
                        title: appLanguage.localized(.ui.checkout.checkOutAdd),
                        inProgressTitle: appLanguage.localized(.ui.checkout.checkingOut),
                        isInProgress: store.isCheckingOut
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || destinationURL == nil || store.isWorking)
                .help(appLanguage.localized(.ui.checkout.checkOutSvnRepositoryLocalFolderAddItApp))
            }
        }
        .padding(24)
        .appSheetFrame(minimumSize: AppLayout.addRepositorySheetMinimumSize)
        // 체크아웃 도중 시트가 그냥 닫히면 svn 프로세스만 백그라운드에 남습니다.
        // 닫는 경로를 취소 확인 한곳으로 모읍니다.
        .interactiveDismissDisabled(store.isCheckingOut)
        .alert(
            appLanguage.localized(.ui.checkout.stopCheckoutProgress),
            isPresented: $isConfirmingCheckoutCancellation
        ) {
            Button(appLanguage.localized(.ui.checkout.stopCheckout), role: .destructive) {
                store.cancelCheckout()
            }
            Button(appLanguage.localized(.ui.checkout.keepDownloading), role: .cancel) {}
        } message: {
            Text(appLanguage.localized(.ui.checkout.runningSvnCheckoutStoppedAlreadyDownloadedFilesStayLocalFolder))
        }
        .sheet(item: $store.canceledCheckoutRecoveryRequest) { request in
            CanceledCheckoutRecoveryView(request: request)
                .environment(store)
        }
        .sheet(isPresented: $isShowingRepositoryBrowser) {
            let settings = RepositoryBrowserConnectionSettings(
                username: username,
                password: password,
                allowsUntrustedServerCertificate: allowsUntrustedServerCertificate
            )
            RepositoryBrowserView(
                repositoryListing: store.client,
                repositoryURL: repositoryURL,
                credentials: settings.credentials,
                allowUntrustedServerCertificate: settings.allowUntrustedServerCertificate,
                allowedServerCertificateFailures: settings.allowedServerCertificateFailures
            )
            .environment(store)
        }
        .onChange(of: store.recoveryState.repositoryBrowseSelectedURL) { _, selectedURL in
            guard let selectedURL else { return }
            repositoryURL = selectedURL
            store.recoveryState.repositoryBrowseSelectedURL = nil
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
        panel.title = appLanguage.localized(.ui.checkout.chooseLocalCheckoutFolder)
        panel.prompt = appLanguage.localized(.ui.repository.filePanelPrompt)
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
                Text(appLanguage.localized(.ui.settings.folderSettings)).font(.title2.bold())
                Text(project.name).foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text(appLanguage.localized(.ui.repository.localFolder))
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
                        Button(appLanguage.localized(.ui.repository.change)) { chooseWorkingFolder() }
                            .disabled(store.isRelocatingProject)
                            .help(appLanguage.localized(.ui.repository.pickNewLocationSvnWorkingFolder))
                    }
                }
                GridRow {
                    Text(appLanguage.localized(.ui.repository.currentRepositoryUrl))
                    HStack {
                        Text(store.recoveryState.repositoryURL ?? "")
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(store.recoveryState.repositoryURL ?? "")
                        Spacer(minLength: 0)
                        Button(appLanguage.localized(.ui.repository.changeRepositoryLocation)) {
                            Task { await store.requestRepositoryRelocation() }
                        }
                        .disabled(store.isWorking)
                    }
                }
            }

            if pendingPath != project.path {
                Label(
                    appLanguage.localized(.ui.repository.newFolderAppliedWhenSave),
                    systemImage: "arrow.triangle.swap"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            CredentialFieldsGrid(
                username: $username,
                password: $newPassword,
                usernamePlaceholder: appLanguage.localized(.ui.authentication.svnUsername),
                passwordPlaceholder: hasSavedPassword
                    ? appLanguage.localized(.ui.authentication.leaveBlankKeepCurrentPassword)
                    : appLanguage.localized(.ui.authentication.enterPassword)
            )

            Label(
                hasSavedPassword
                    ? appLanguage.localized(.ui.authentication.passwordFolderStoredMacosKeychain)
                    : appLanguage.localized(.ui.authentication.noPasswordStored),
                systemImage: hasSavedPassword ? "checkmark.shield" : "shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            UntrustedCertificateToggle(
                isAllowed: $allowsUntrustedServerCertificate,
                help: appLanguage.localized(.ui.certificate.allowSelfSignedCertificateNameMismatchErrorsRepository)
            )

            Divider()
            HStack {
                Button {
                    store.requestSelectedWorkingCopyCleanup()
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(.ui.cleanup.workingCopyCleanup),
                        inProgressTitle: appLanguage.localized(.ui.cleanup.cleaningWorkingCopy),
                        systemImage: "wrench.and.screwdriver",
                        isInProgress: store.isCleaningSelectedWorkingCopy
                    )
                }
                .disabled(isSaving || store.isCleaningSelectedWorkingCopy)
                .help(appLanguage.localized(.ui.cleanup.manuallyCleanUpInterruptedLockedSvnWorkingCopy))
                if hasSavedPassword {
                    Button(appLanguage.localized(.ui.authentication.deleteSavedPassword), role: .destructive) {
                        if store.deleteSavedPassword(for: project.id) {
                            hasSavedPassword = false
                            newPassword = ""
                        }
                    }
                    .help(appLanguage.localized(.ui.authentication.deleteSvnPasswordStoredKeychainLocalWorkingFolder))
                }
                Spacer()
                Button(appLanguage.localized(.ui.common.cancel), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                    .help(appLanguage.localized(.ui.authentication.closeWithoutSavingCredentialChanges))
                Button(action: save) {
                    ActionProgressLabel(
                        title: appLanguage.localized(.ui.common.save),
                        inProgressTitle: store.isVerifyingCredentials
                            ? appLanguage.localized(.ui.authentication.checkingAccount)
                            : appLanguage.localized(.ui.authentication.saving),
                        isInProgress: isSaving
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
                .help(appLanguage.localized(.ui.authentication.saveWorkingFolderLocationSvnUsernameNewPasswordFolder))
            }
        }
        .padding(24)
        .frame(width: AppLayout.credentialsSheetWidth)
        .onAppear { hasSavedPassword = store.hasSavedPassword(for: project.id) }
        .task(id: project.id) { await store.loadSelectedRepositoryURL() }
        .sheet(item: $store.recoveryState.repositoryRelocationRequest) { request in
            RepositoryRelocationView(request: request)
                .environment(store)
        }
        .sheet(item: $store.workingCopyCleanupRequest) { request in
            WorkingCopyCleanupView(request: request)
                .environment(store)
        }
        .sheet(item: $store.authenticationRequest) { request in
            AuthenticationRequiredView(request: request)
                .environment(store)
        }
        .alert(
            appLanguage.localized(.ui.authentication.svnAccountPasswordNotValid),
            isPresented: .isPresenting($credentialFailureMessage),
            presenting: credentialFailureMessage
        ) { _ in
            Button(appLanguage.localized(.ui.authentication.enterValidCredentials)) {
                credentialFailureMessage = nil
            }
            Button(appLanguage.localized(.ui.authentication.discardChangesClose), role: .cancel) {
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
        panel.title = appLanguage.localized(.ui.repository.chooseSvnLocalWorkingFolders)
        panel.prompt = appLanguage.localized(.ui.repository.filePanelPrompt)
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

struct RepositoryRelocationView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    let request: RepositoryRelocationRequest
    @State private var newRepositoryURL = ""
    @State private var isConfirming = false

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 18) {
            Label(
                appLanguage.localized(.ui.repository.changeRepositoryLocation),
                systemImage: "arrow.triangle.swap"
            )
            .font(.title2.bold())

            if let connectionErrorMessage = request.connectionErrorMessage {
                Label(
                    appLanguage.localized(.ui.repository.mayMovedRelocateNewUrlRestoreRemoteOperations),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                ErrorDetailsText(message: connectionErrorMessage)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text(appLanguage.localized(.ui.repository.currentRepositoryUrl))
                    Text(request.currentURL)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text(appLanguage.localized(.ui.repository.newRepositoryUrl))
                    TextField("https://server/svn/project/trunk", text: $newRepositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: AppLayout.repositoryURLFieldMinimumWidth)
                }
            }

            Label(
                appLanguage.localized(.ui.repository.relocationPreservesAllUncommittedLocalChanges),
                systemImage: "checkmark.shield"
            )
            .font(.callout)

            if let failure = store.recoveryState.repositoryRelocationFailureMessage {
                ErrorDetailsText(message: failure)
            }

            Divider()
            HStack {
                Spacer()
                Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                    store.recoveryState.repositoryRelocationRequest = nil
                    store.recoveryState.repositoryRelocationFailureMessage = nil
                }
                .disabled(store.isWorking)
                Button(appLanguage.localized(.ui.repository.reviewRelocation)) {
                    isConfirming = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(newRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
            }
        }
        .padding(24)
        .frame(width: AppLayout.credentialsSheetWidth)
        .interactiveDismissDisabled(store.isWorking)
        .alert(
            appLanguage.localized(.ui.repository.relocationConfirmationTitle),
            isPresented: $isConfirming
        ) {
            Button(appLanguage.localized(.ui.repository.relocateAction)) {
                Task { _ = await store.relocateSelectedRepository(to: newRepositoryURL) }
            }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {}
        } message: {
            Text(appLanguage.localized(
                .ui.repository.currentUrlNewUrlOnlyWorkingCopyRepositoryConnectionChanges,
                request.currentURL,
                newRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
    }
}

struct VersionedFileActionView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    let request: VersionedFileActionRequest
    @State private var destinationName: String

    init(request: VersionedFileActionRequest) {
        self.request = request
        _destinationName = State(initialValue: (request.sourceRelativePath as NSString).lastPathComponent)
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: request.kind == .move ? "pencil" : "doc.on.doc")
                .font(.title2.bold())
            Text(request.sourceRelativePath)
                .font(.callout.monospaced())
                .textSelection(.enabled)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Text(appLanguage.localized(.ui.repository.newFileName))
                    TextField("", text: $destinationName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Label(
                appLanguage.localized(.ui.repository.commitChangeApplyItServer, destinationName),
                systemImage: "info.circle"
            )
            .font(.callout)

            if let failure = store.recoveryState.versionedFileActionFailureMessage {
                ErrorDetailsText(message: failure)
            }

            Divider()
            HStack {
                Spacer()
                Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                    store.recoveryState.versionedFileActionRequest = nil
                    store.recoveryState.versionedFileActionFailureMessage = nil
                }
                .disabled(store.isWorking)
                Button(title) {
                    Task {
                        _ = await store.performVersionedFileAction(
                            request,
                            destinationName: destinationName
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(destinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
            }
        }
        .padding(24)
        .frame(width: AppLayout.credentialsSheetWidth)
        .interactiveDismissDisabled(store.isWorking)
    }

    private var title: String {
        appLanguage.localized(
            request.kind == .move
                ? .ui.history.renameHistory
                : .ui.history.copyHistory
        )
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
                Text(appLanguage.localized(.ui.authentication.username))
                TextField(usernamePlaceholder, text: $username)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: AppLayout.credentialFieldMinimumWidth)
            }
            GridRow {
                Text(appLanguage.localized(.ui.authentication.password))
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
                            ? appLanguage.localized(.ui.authentication.hidePassword)
                            : appLanguage.localized(.ui.authentication.showPassword))
                        .accessibilityLabel(isPasswordRevealed
                            ? appLanguage.localized(.ui.authentication.hidePassword)
                            : appLanguage.localized(.ui.authentication.showPassword))
                    }
                    if !isPasswordRevealed {
                        Text(appLanguage.localized(.ui.authentication.secureEntryBlocksKoreanInputMethodRevealPasswordEyeButton))
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
                appLanguage.localized(.ui.certificate.allowUntrustedSslCertificates),
                isOn: $isAllowed
            )
            .toggleStyle(.checkbox)
            .help(help)

            Text(appLanguage.localized(.ui.certificate.useWhenTargetServerCertificateInvalidButTrustServer))
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(appLanguage.localized(.ui.certificate.expiredNotYetValidCertificatesRequireSeparateConsentAfterSvn))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
