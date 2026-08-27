import SwiftUI

enum ConfirmationKeyboardAction: Equatable {
    case cancel
    case confirmCommit
    case openWithoutLock
    case rescanRepositoryPaths
    case reviewRepositoryPathNormalization
}

enum CommitServerDeletionState: CaseIterable {
    case none
    case present
}

enum CommitMessageState: CaseIterable {
    case empty
    case present
}

enum DocumentLockState: CaseIterable {
    case unlocked
    case locked
    case unavailable
}

enum RememberOpenWithoutLockState: CaseIterable {
    case disabled
    case enabled
}

struct ConfirmationKeyboardBehavior: Equatable {
    let returnAction: ConfirmationKeyboardAction?
    let escapeAction: ConfirmationKeyboardAction?

    static func commitConfirmation(
        serverDeletions: CommitServerDeletionState,
        message: CommitMessageState
    ) -> Self {
        switch (serverDeletions, message) {
        case (.none, .empty), (.none, .present):
            Self(returnAction: .confirmCommit, escapeAction: .cancel)
        case (.present, .empty), (.present, .present):
            Self(returnAction: nil, escapeAction: .cancel)
        }
    }

    static let repositoryPathNormalization = Self(
        returnAction: .cancel,
        escapeAction: .cancel
    )

    static let repositoryPathNormalizationDismissal = Self(
        returnAction: nil,
        escapeAction: .cancel
    )

    static let repositoryPathNormalizationRescan = Self(
        returnAction: .rescanRepositoryPaths,
        escapeAction: nil
    )

    static let repositoryPathNormalizationReview = Self(
        returnAction: .reviewRepositoryPathNormalization,
        escapeAction: nil
    )

    static let deletion = Self(returnAction: .cancel, escapeAction: .cancel)
    static let revert = Self(returnAction: nil, escapeAction: .cancel)
    static let commitDeletionRestore = Self(returnAction: nil, escapeAction: .cancel)

    static func documentOpenConfirmation(
        lock: DocumentLockState,
        rememberOpenWithoutLock: RememberOpenWithoutLockState
    ) -> Self {
        switch (lock, rememberOpenWithoutLock) {
        case (.unlocked, .disabled), (.unlocked, .enabled),
             (.locked, .disabled), (.locked, .enabled),
             (.unavailable, .disabled), (.unavailable, .enabled):
            Self(returnAction: .openWithoutLock, escapeAction: .cancel)
        }
    }
}

extension View {
    @ViewBuilder
    func confirmationKeyboardShortcut(
        for action: ConfirmationKeyboardAction,
        behavior: ConfirmationKeyboardBehavior
    ) -> some View {
        switch (behavior.returnAction == action, behavior.escapeAction == action) {
        case (true, _):
            keyboardShortcut(.defaultAction)
        case (false, true):
            keyboardShortcut(.cancelAction)
        case (false, false):
            self
        }
    }
}
