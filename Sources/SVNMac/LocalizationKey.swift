struct LocalizationKey: Hashable, Sendable {
    let rawValue: String

    fileprivate init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static let error = LocalizationErrorKeys()
    static let history = LocalizationHistoryKeys()
    static let recovery = LocalizationRecoveryKeys()
    static let repository = LocalizationRepositoryKeys()
    static let ui = LocalizationUIKeys()

    private static let errorDeletionKeys: [LocalizationKey] = [
        Self.error.deletion.chooseMissingItems,
        Self.error.deletion.partial,
        Self.error.deletion.unresolvedMissingPaths,
        Self.error.deletion.validation,
    ]

    private static let errorPathKeys: [LocalizationKey] = [
        Self.error.path.aliasRepair,
        Self.error.path.normalizationCollision,
        Self.error.path.unsupportedTarget,
    ]

    private static let errorRecoveryKeys: [LocalizationKey] = [
        Self.error.recovery.blocked,
        Self.error.recovery.fileReplacement,
        Self.error.recovery.validation,
    ]

    private static let errorKeys: [LocalizationKey] = [
        errorDeletionKeys,
        errorPathKeys,
        errorRecoveryKeys,
    ].flatMap { $0 }

    private static let historyCopyKeys: [LocalizationKey] = [
        Self.history.copy.copiedFrom,
    ]

    private static let historyKeys: [LocalizationKey] = [
        historyCopyKeys,
    ].flatMap { $0 }

    private static let recoveryPathKeys: [LocalizationKey] = [
        Self.recovery.path.reviewPaths,
    ]

    private static let recoveryKeys: [LocalizationKey] = [
        recoveryPathKeys,
    ].flatMap { $0 }

    private static let repositoryPathNormalizationKeys: [LocalizationKey] = [
        Self.repository.pathNormalization.action,
        Self.repository.pathNormalization.actionHelp,
        Self.repository.pathNormalization.after,
        Self.repository.pathNormalization.before,
        Self.repository.pathNormalization.codepointsDetail,
        Self.repository.pathNormalization.confirmationCommits,
        Self.repository.pathNormalization.confirmationDeleteAdd,
        Self.repository.pathNormalization.confirmationDirectory,
        Self.repository.pathNormalization.confirmationRun,
        Self.repository.pathNormalization.confirmationTeam,
        Self.repository.pathNormalization.confirmationTitle,
        Self.repository.pathNormalization.defaultCommitMessage,
        Self.repository.pathNormalization.deselectAll,
        Self.repository.pathNormalization.differentComponent,
        Self.repository.pathNormalization.directoryNote,
        Self.repository.pathNormalization.errorInvalidTargets,
        Self.repository.pathNormalization.errorLocalChanges,
        Self.repository.pathNormalization.errorLocks,
        Self.repository.pathNormalization.errorPartialFailure,
        Self.repository.pathNormalization.errorUnknown,
        Self.repository.pathNormalization.formComposed,
        Self.repository.pathNormalization.formDecomposed,
        Self.repository.pathNormalization.noPaths,
        Self.repository.pathNormalization.problem,
        Self.repository.pathNormalization.result,
        Self.repository.pathNormalization.resultRevisions,
        Self.repository.pathNormalization.resultSummary,
        Self.repository.pathNormalization.reviewAction,
        Self.repository.pathNormalization.running,
        Self.repository.pathNormalization.sameAppearanceNote,
        Self.repository.pathNormalization.scanAgain,
        Self.repository.pathNormalization.scanning,
        Self.repository.pathNormalization.scanningDetail,
        Self.repository.pathNormalization.skipped,
        Self.repository.pathNormalization.skippedReason,
        Self.repository.pathNormalization.targets,
        Self.repository.pathNormalization.title,
        Self.repository.pathNormalization.waiting,
        Self.repository.pathNormalization.windowsNote,
    ]

    private static let repositoryKeys: [LocalizationKey] = [
        repositoryPathNormalizationKeys,
    ].flatMap { $0 }

    private static let uiAboutKeys: [LocalizationKey] = [
        Self.ui.about.needHelp,
        Self.ui.about.pleaseSendQuestions,
        Self.ui.about.questionsSupport,
        Self.ui.about.sendEmail,
        Self.ui.about.svnKr,
        Self.ui.about.version,
    ]

    private static let uiAuthenticationKeys: [LocalizationKey] = [
        Self.ui.authentication.canceledLocalChangesRemainAvailable,
        Self.ui.authentication.cancelingDoesNotPreventViewingLocalChangesDiffs,
        Self.ui.authentication.changeFolderLocationSvnAccountKeychainPassword,
        Self.ui.authentication.checkingAccount,
        Self.ui.authentication.checkoutCompletedButPasswordCouldNotSavedKeychain,
        Self.ui.authentication.closeWithoutSavingCredentialChanges,
        Self.ui.authentication.configureSvnAccountKeychainPasswordLocalWorkingFolder,
        Self.ui.authentication.credentials,
        Self.ui.authentication.credentialsSaved,
        Self.ui.authentication.deleteSavedPassword,
        Self.ui.authentication.deleteSvnPasswordStoredKeychainLocalWorkingFolder,
        Self.ui.authentication.discardChangesClose,
        Self.ui.authentication.enterPassword,
        Self.ui.authentication.enterValidCredentials,
        Self.ui.authentication.folderCredentials,
        Self.ui.authentication.hidePassword,
        Self.ui.authentication.keychainAccessDenied,
        Self.ui.authentication.keychainAccessDeniedChooseHowAuthenticate,
        Self.ui.authentication.keychainOperationFailed,
        Self.ui.authentication.leaveBlankKeepCurrentPassword,
        Self.ui.authentication.noPasswordStored,
        Self.ui.authentication.password,
        Self.ui.authentication.passwordFolderStoredMacosKeychain,
        Self.ui.authentication.repositoryAuthenticationFailed,
        Self.ui.authentication.requiredCommitSelectedChanges,
        Self.ui.authentication.requiredDownloadLatestServerChanges,
        Self.ui.authentication.requiredLoadLatestServerHistory,
        Self.ui.authentication.saveKeychainUse,
        Self.ui.authentication.saveMacosKeychainOptional,
        Self.ui.authentication.saveSvnUsernameNewPasswordLocalWorkingFolder,
        Self.ui.authentication.saveWorkingFolderLocationSvnUsernameNewPasswordFolder,
        Self.ui.authentication.savedPasswordDeleted,
        Self.ui.authentication.saving,
        Self.ui.authentication.secureEntryBlocksKoreanInputMethodRevealPasswordEyeButton,
        Self.ui.authentication.showMacosKeychainAccessPromptAgain,
        Self.ui.authentication.showPassword,
        Self.ui.authentication.svnAccountPasswordNotValid,
        Self.ui.authentication.svnAuthenticationRequired,
        Self.ui.authentication.svnPassword,
        Self.ui.authentication.svnServerDeniedReadAccessFileCheckProjectCredentialsServer,
        Self.ui.authentication.svnUsername,
        Self.ui.authentication.svnUsernameOptional,
        Self.ui.authentication.tryKeychainAgain,
        Self.ui.authentication.useSessionOnly,
        Self.ui.authentication.username,
        Self.ui.authentication.usesExistingSvnCredentialCacheMacosKeychain,
    ]

    private static let uiBrowserKeys: [LocalizationKey] = [
        Self.ui.browser.actions,
        Self.ui.browser.browse,
        Self.ui.browser.browseRepository,
        Self.ui.browser.browseSvnRepository,
        Self.ui.browser.checkFoldersFilesBeforeChoosingRepositoryPathCheckOut,
        Self.ui.browser.chooseHowFilesDisplayed,
        Self.ui.browser.couldNotConnectRepository,
        Self.ui.browser.couldNotLoadRepositoryContents,
        Self.ui.browser.dateModified,
        Self.ui.browser.directory,
        Self.ui.browser.directoryEmpty,
        Self.ui.browser.enterRepositoryUrlBrowse,
        Self.ui.browser.fileAccessibilityLabel,
        Self.ui.browser.files,
        Self.ui.browser.items,
        Self.ui.browser.kind,
        Self.ui.browser.loadingFiles,
        Self.ui.browser.loadingRepositoryContents,
        Self.ui.browser.name,
        Self.ui.browser.noFiles,
        Self.ui.browser.noSearchResults,
        Self.ui.browser.openSelectedDirectory,
        Self.ui.browser.parentDirectory,
        Self.ui.browser.repositoryReturnedNoFilesSubdirectoriesPath,
        Self.ui.browser.repositoryUrl,
        Self.ui.browser.revisionOptional,
        Self.ui.browser.searchFiles,
        Self.ui.browser.size,
        Self.ui.browser.splitView,
        Self.ui.browser.symbolicLink,
        Self.ui.browser.treeView,
        Self.ui.browser.useRepositoryPath,
        Self.ui.browser.workingCopy,
    ]

    private static let uiCertificateKeys: [LocalizationKey] = [
        Self.ui.certificate.allowProject,
        Self.ui.certificate.allowSelfSignedCertificateNameMismatchErrorsRepository,
        Self.ui.certificate.allowUntrustedSslCertificates,
        Self.ui.certificate.doNotAllow,
        Self.ui.certificate.exceptionNotAllowedNoProjectSettingChanged,
        Self.ui.certificate.exceptionSecurityWarning,
        Self.ui.certificate.expiredNotYetValidCertificatesRequireSeparateConsentAfterSvn,
        Self.ui.certificate.issuedDifferentHostnameCheckRepositoryUrlCertificateHostnameBeforeAllowing,
        Self.ui.certificate.issuerNotTrustedConfirmIssuerServerAdministratorAllowingItBypasses,
        Self.ui.certificate.notYetValidCheckServerMacClocksCertificateStartDate,
        Self.ui.certificate.savedCertificateExceptionRetrySvnOperation,
        Self.ui.certificate.serverCertificateExpiredRenewingItSafestAllowingItLetsProject,
        Self.ui.certificate.serverCertificateProblem,
        Self.ui.certificate.svnRejectedServerCertificateReviewDetectedProblemBeforeDeciding,
        Self.ui.certificate.svnReportedCertificateProblemButDidNotIdentifySupportedReason,
        Self.ui.certificate.useOnlyServersSelfSignedCertificatesCertificateNameMismatches,
        Self.ui.certificate.useWhenTargetServerCertificateInvalidButTrustServer,
    ]

    private static let uiChangesKeys: [LocalizationKey] = [
        Self.ui.changes.affected,
        Self.ui.changes.cancelDeletionRestore,
        Self.ui.changes.collapseFolder,
        Self.ui.changes.deletePendingItems,
        Self.ui.changes.deleteRepository,
        Self.ui.changes.expandFolder,
        Self.ui.changes.filesInsideFolderAddedTogether,
        Self.ui.changes.includeCommit,
        Self.ui.changes.includeExcludeFileNextCommit,
        Self.ui.changes.localChangesRefreshed,
        Self.ui.changes.multipleCanonicallyEquivalentServerPathsExistSoAppCannotChoose,
        Self.ui.changes.noChanges,
        Self.ui.changes.pathPointsDifferentRepositoryLocationVerifyCommitDestination,
        Self.ui.changes.pendingDeletionStatus,
        Self.ui.changes.propertiesModified,
        Self.ui.changes.resolveDuplicateServerPathsManually,
        Self.ui.changes.restoreLocalFile,
        Self.ui.changes.restorePendingDeletions,
        Self.ui.changes.revertConflictLocalChanges,
        Self.ui.changes.selectChangedFileViewItsDiff,
        Self.ui.changes.showIgnoredFiles,
        Self.ui.changes.showsDiffFile,
        Self.ui.changes.switchedPath,
        Self.ui.changes.temporary,
        Self.ui.changes.thereNoLocallyModifiedFiles,
        Self.ui.changes.unicodePathConflict,
        Self.ui.changes.unversionedLocalFileBlockingServerFileSameNameMoveRename,
    ]

    private static let uiCheckoutKeys: [LocalizationKey] = [
        Self.ui.checkout.checkOutAdd,
        Self.ui.checkout.checkOutNewSvnRepositoryRegisterExistingLocalWorkingFolder,
        Self.ui.checkout.checkOutRepositoryUrl,
        Self.ui.checkout.checkOutRepositoryUrlAddItLocalWorkingFolders,
        Self.ui.checkout.checkOutSvnRepositoryLocalFolderAddItApp,
        Self.ui.checkout.checkingOut,
        Self.ui.checkout.chooseLocalCheckoutFolder,
        Self.ui.checkout.filesDownloadedAppearHereAfterCheckoutStarts,
        Self.ui.checkout.keepDownloading,
        Self.ui.checkout.localFolderPickerHelp,
        Self.ui.checkout.localFolderRequiredError,
        Self.ui.checkout.progressLog,
        Self.ui.checkout.runningSvnCheckoutStoppedAlreadyDownloadedFilesStayLocalFolder,
        Self.ui.checkout.stopCheckout,
        Self.ui.checkout.stopCheckoutProgress,
    ]

    private static let uiCleanupKeys: [LocalizationKey] = [
        Self.ui.cleanup.candidateNotRegularFile,
        Self.ui.cleanup.cleanUpEquivalentPath,
        Self.ui.cleanup.cleaningCommitting,
        Self.ui.cleanup.cleaningWorkingCopy,
        Self.ui.cleanup.deleteCommitCleanup,
        Self.ui.cleanup.fileContentsCouldNotRead,
        Self.ui.cleanup.fileDoesNotAppledoubleMagicBytes,
        Self.ui.cleanup.fileDoesNotDsStoreBud1Signature,
        Self.ui.cleanup.fileNotFoundAfterUpdate,
        Self.ui.cleanup.manuallyCleanUpInterruptedLockedSvnWorkingCopy,
        Self.ui.cleanup.needed,
        Self.ui.cleanup.officeLockFileExceedsByteSafetyLimit,
        Self.ui.cleanup.onlyVerifiedCandidatesSelectedReviewEveryPathBeforeDeletingCommitting,
        Self.ui.cleanup.operationInterruptedLikeCleanUpWorkingCopyTryAgainCleanup,
        Self.ui.cleanup.pathOutsideWorkingCopySafetyBoundary,
        Self.ui.cleanup.repositoryTemporaryFileCleanup,
        Self.ui.cleanup.runCleanup,
        Self.ui.cleanup.symbolicLinksNeverCleanedAutomatically,
        Self.ui.cleanup.workingCopyCleanup,
        Self.ui.cleanup.workingCopyCleanupCompleted,
        Self.ui.cleanup.workingCopyCleanupFailedDoNotRetryCleanupRepeatedlyCopy,
    ]

    private static let uiCommitKeys: [LocalizationKey] = [
        Self.ui.commit.cancelRepositoryDeletionStateRestoreRepositoryVersionLocally,
        Self.ui.commit.clearAllSelectedCommitTargets,
        Self.ui.commit.clearSelection,
        Self.ui.commit.committing,
        Self.ui.commit.confirm,
        Self.ui.commit.diffUnavailableUntilFileAddedSvnItAddedAutomaticallyWhen,
        Self.ui.commit.includeRestore,
        Self.ui.commit.item,
        Self.ui.commit.itemDeletedServer,
        Self.ui.commit.markDeletion,
        Self.ui.commit.markRepositoryDeletion,
        Self.ui.commit.markedItemDeletionCommitDeleteThemRepository,
        Self.ui.commit.message,
        Self.ui.commit.messageSavedIncorrectEncodingShownAfterRestorationOtherSvnUsers,
        Self.ui.commit.no,
        Self.ui.commit.noCommitMessage,
        Self.ui.commit.noFilesDeleted,
        Self.ui.commit.onlyMarksItemsDeletionTheyDeletedSvnRepositoryWhenCommitted,
        Self.ui.commit.outputAppearsHereAfterCommitStarts,
        Self.ui.commit.pendingDeletionCount,
        Self.ui.commit.progressLog,
        Self.ui.commit.recordedEmptyMessage,
        Self.ui.commit.restoreSelectedDeletionFileServer,
        Self.ui.commit.restoreSelectedFilesAction,
        Self.ui.commit.restoreSelectedFilesConfirmationTitle,
        Self.ui.commit.restoreSelectionHelp,
        Self.ui.commit.restoreServer,
        Self.ui.commit.revert,
        Self.ui.commit.revertLocalChangesAction,
        Self.ui.commit.revertLocalChangesConfirmationTitle,
        Self.ui.commit.reviewCommit,
        Self.ui.commit.selectAll,
        Self.ui.commit.selectAllCurrentlyChangedFilesCommit,
        Self.ui.commit.selected,
        Self.ui.commit.selectedFilesSvnServerEnteredMessage,
        Self.ui.commit.someFilesDeletedReviewListBelowConfirmThatTheyShould,
        Self.ui.commit.uncommittedChangesDiscardedCannotRestoredSvn,
        Self.ui.commit.versionedItemsBelowSelectedDirectoryAlsoMarkedDeletion,
        Self.ui.commit.withoutMessage,
    ]

    private static let uiCommonKeys: [LocalizationKey] = [
        Self.ui.common.cancel,
        Self.ui.common.changes,
        Self.ui.common.close,
        Self.ui.common.copyFullPath,
        Self.ui.common.couldNotOpenFile,
        Self.ui.common.fileType,
        Self.ui.common.folder,
        Self.ui.common.noTextDiffAvailableMayNewBinaryFile,
        Self.ui.common.openFile,
        Self.ui.common.refresh,
        Self.ui.common.refreshed,
        Self.ui.common.remove,
        Self.ui.common.revealFinder,
        Self.ui.common.save,
        Self.ui.common.selectedCount,
        Self.ui.common.unknownAuthor,
        Self.ui.common.yes,
    ]

    private static let uiConflictKeys: [LocalizationKey] = [
        Self.ui.conflict.afterReviewingBothBackupsKeepContentCurrentlySavedWorkingFile,
        Self.ui.conflict.applyServerProperties,
        Self.ui.conflict.applyServerVersion,
        Self.ui.conflict.bothVersionsCopiedBackupFolderEditingCopiesDoesNotChange,
        Self.ui.conflict.confirmCurrentLocalPropertiesResolvedValues,
        Self.ui.conflict.confirmCurrentWorkingCopyState,
        Self.ui.conflict.confirmManuallyEditedContent,
        Self.ui.conflict.conflict,
        Self.ui.conflict.conflictedProperties,
        Self.ui.conflict.conflictedPropertyNameCouldNotDetermined,
        Self.ui.conflict.currentWorkingFile,
        Self.ui.conflict.discardLocalChangeRestoreServerFile,
        Self.ui.conflict.fileAlsoPropertyConflictChoosingVersionBelowResolvesPropertiesSame,
        Self.ui.conflict.fileCannotCommittedUntilItMarkedResolved,
        Self.ui.conflict.fileThatNotRepository,
        Self.ui.conflict.ifDeletedItLocallyDeletionRemainsCommitDeleteItServer,
        Self.ui.conflict.incomingServerPropertyValuesDiscardedWorkingCopy,
        Self.ui.conflict.keepFileCurrentlySavedWorkingCopyMarkConflictResolvedFile,
        Self.ui.conflict.keepFileLaterCommitReplaceRepositoryFileContent,
        Self.ui.conflict.keepMyChange,
        Self.ui.conflict.keepMyProperties,
        Self.ui.conflict.localPropertyValuesDiscarded,
        Self.ui.conflict.macosUnicodePathMatchedActualSvnManagedPath,
        Self.ui.conflict.modificationDateUnavailable,
        Self.ui.conflict.modified,
        Self.ui.conflict.more,
        Self.ui.conflict.myFile,
        Self.ui.conflict.openBackupFolder,
        Self.ui.conflict.openMyFile,
        Self.ui.conflict.openResolutionAction,
        Self.ui.conflict.openServerFile,
        Self.ui.conflict.overwriteMyVersion,
        Self.ui.conflict.overwritingVersionRemovesIncomingServerChangesWorkingFileServerFile,
        Self.ui.conflict.pathCannotCommittedUntilItsPropertyConflictResolved,
        Self.ui.conflict.propertyConflict,
        Self.ui.conflict.propertyConflictResolvedReviewPropertiesBeforeCommitting,
        Self.ui.conflict.propertyValuesKeptWell,
        Self.ui.conflict.replaceLocalPropertiesServerValues,
        Self.ui.conflict.replaceServerFileLocalEditsLeaveWorkingCopyButRemain,
        Self.ui.conflict.resolutionHeader,
        Self.ui.conflict.resolveConflictedFilesBeforeCommitting,
        Self.ui.conflict.resolvedBackupsRemovedItemCreated,
        Self.ui.conflict.resolvedReviewFileBeforeCommitting,
        Self.ui.conflict.resolving,
        Self.ui.conflict.restoreFileServerVersion,
        Self.ui.conflict.revertingRemovesItemsBelowWorkingFolderTheyCopiedBackupFolder,
        Self.ui.conflict.serverFile,
        Self.ui.conflict.serverPropertyValuesAppliedWell,
        Self.ui.conflict.serverRevision,
        Self.ui.conflict.treeConflict,
        Self.ui.conflict.treeConflictConcernsPathStateNotFileContentsNotChoice,
        Self.ui.conflict.treeConflictLocalServerTarget,
        Self.ui.conflict.uncommittedChange,
        Self.ui.conflict.uncommittedLocalChangesDiscarded,
        Self.ui.conflict.useMineAction,
        Self.ui.conflict.useMineConfirmationTitle,
        Self.ui.conflict.useServerAction,
        Self.ui.conflict.useServerConfirmationTitle,
        Self.ui.conflict.useWorkingFileAction,
        Self.ui.conflict.useWorkingFileConfirmationTitle,
        Self.ui.conflict.whenChooseVersionCurrentWorkingFilePreservedSeparatelyHiddenRecovery,
    ]

    private static let uiDemoKeys: [LocalizationKey] = [
        Self.ui.demo.browseSampleProject,
        Self.ui.demo.closeSampleProjectReturnNormalMode,
        Self.ui.demo.exitDemo,
        Self.ui.demo.exploreMainFeaturesSampleDataNoServerConnectionAccount,
    ]

    private static let uiErrorKeys: [LocalizationKey] = [
        Self.ui.error.bundledSvnExecutableCouldNotFoundReinstallApp,
        Self.ui.error.commitBasedOlderWorkingCopyStateRunUpdateResolveAny,
        Self.ui.error.commitCompletedButWorkingCopyValidationFailedDoNotRetry,
        Self.ui.error.conflictBackupsMustStoredOutsideWorkingCopy,
        Self.ui.error.conflictFilePathPointsOutsideWorkingCopy,
        Self.ui.error.conflictRemainsAfterSvnCommandReviewBackupsTryAgain,
        Self.ui.error.copied,
        Self.ui.error.copyAllDisplayedErrorDetailsClipboard,
        Self.ui.error.copyErrorDetails,
        Self.ui.error.currentWorkingFileCouldNotFound,
        Self.ui.error.currentWorkingFileMustRegularFileNotSymbolicLink,
        Self.ui.error.error,
        Self.ui.error.failed,
        Self.ui.error.failedRemoveIncompleteConflictBackup,
        Self.ui.error.fileRemainsConflictGoChangesChooseResolveConflictsResolveIt,
        Self.ui.error.fileVersionCouldNotFound,
        Self.ui.error.fileVersionMustRegularFileNotSymbolicLink,
        Self.ui.error.lockTokenDoesNotBelongCurrentWorkingCopyReviewOwner,
        Self.ui.error.recoveryBackupCurrentWorkingFileCouldNotVerified,
        Self.ui.error.recoveryDestinationFolderMustEmpty,
        Self.ui.error.selectedFolderNotSvnLocalWorkingFolder,
        Self.ui.error.selectedVersionFileCouldNotRestoredWorkingFile,
        Self.ui.error.serverFileVersionCouldNotFound,
        Self.ui.error.serverFileVersionMustRegularFileNotSymbolicLink,
        Self.ui.error.svnResponseCouldNotRead,
        Self.ui.error.unableLoadChanges,
        Self.ui.error.unableOpenFile,
        Self.ui.error.unknownError,
        Self.ui.error.unsupportedConflictType,
        Self.ui.error.workingCopyOperationInterruptedRunWorkingCopyCleanupTryOperation,
    ]

    private static let uiFileKeys: [LocalizationKey] = [
        Self.ui.file.copiedFilePath,
        Self.ui.file.noLongerMarkedDeleted,
        Self.ui.file.restoredButFailed,
        Self.ui.file.restoredSelectedDeletionFileServer,
        Self.ui.file.revertedLocalChanges,
    ]

    private static let uiHistoryKeys: [LocalizationKey] = [
        Self.ui.history.additionalRevisionProperties,
        Self.ui.history.blueDotsServerCommitsGreenRingHighestLocalRevisionOrange,
        Self.ui.history.blueDotsServerCommitsGreenRingLocalBaseOrangeBranch,
        Self.ui.history.changedPaths,
        Self.ui.history.commitHistory,
        Self.ui.history.commitTimeUnavailable,
        Self.ui.history.contentChanged,
        Self.ui.history.copyHistory,
        Self.ui.history.earlierHistory,
        Self.ui.history.fileCommitHistory,
        Self.ui.history.highestLocalRevision,
        Self.ui.history.includedLocally,
        Self.ui.history.load50More,
        Self.ui.history.loading,
        Self.ui.history.loadingCommitHistory,
        Self.ui.history.localBaseRevision,
        Self.ui.history.localBaseRevisionEarlierThanLatest50ServerRecords,
        Self.ui.history.localChanges,
        Self.ui.history.localUpdateBaseFallsBetweenTwoServerCommits,
        Self.ui.history.mixedRevisions,
        Self.ui.history.myLocalBase,
        Self.ui.history.myLocalFolderR,
        Self.ui.history.noCommitHistory,
        Self.ui.history.noValue,
        Self.ui.history.originalMessage,
        Self.ui.history.propertiesChanged,
        Self.ui.history.refreshed,
        Self.ui.history.reloadLocalChangesLatestServerCommitHistory,
        Self.ui.history.renameHistory,
        Self.ui.history.restored,
        Self.ui.history.serverCommitDetail,
        Self.ui.history.serverCommitLegend,
        Self.ui.history.serverLatest,
        Self.ui.history.serverLatestR,
        Self.ui.history.uncommittedChanges,
        Self.ui.history.uncommittedChangesBranchLocalBaseRevision,
        Self.ui.history.upDate,
        Self.ui.history.viewChangesCommit,
        Self.ui.history.viewOriginalMessageBeforeRestoration,
        Self.ui.history.workingCopyContainsMixedRevisionsRMarkerShowsHighestRevision,
    ]

    private static let uiIgnoreKeys: [LocalizationKey] = [
        Self.ui.ignore.addRule,
        Self.ui.ignore.addedIgnoreRuleCommitDirectoryPropertyShareItTeam,
        Self.ui.ignore.addingRule,
        Self.ui.ignore.alreadyVersionedFilesNotHiddenIgnoreRules,
        Self.ui.ignore.applied,
        Self.ui.ignore.appliedGitRuleSvnIgnorePropertiesCommitPropertyChangesShare,
        Self.ui.ignore.apply,
        Self.ui.ignore.applyGlobalIgnoreRules,
        Self.ui.ignore.applySelectedRules,
        Self.ui.ignore.applying,
        Self.ui.ignore.available,
        Self.ui.ignore.clear,
        Self.ui.ignore.compareGitRules,
        Self.ui.ignore.directory,
        Self.ui.ignore.duplicateRule,
        Self.ui.ignore.enterPattern,
        Self.ui.ignore.fileExtension,
        Self.ui.ignore.gitignoreNotModifiedImportOneWaySvnPropertyChangesMust,
        Self.ui.ignore.globalRulesCanAffectManyDirectoriesBelowWorkingCopyApply,
        Self.ui.ignore.importGitRules,
        Self.ui.ignore.inherited,
        Self.ui.ignore.inheritedRulesCanOnlyRemovedParentDirectoryThatOwnsProperty,
        Self.ui.ignore.item,
        Self.ui.ignore.lastCompared,
        Self.ui.ignore.manageIgnoreRules,
        Self.ui.ignore.noGitignore,
        Self.ui.ignore.noGitignoreFileFoundWorkingCopy,
        Self.ui.ignore.noSvnIgnoreRulesConfigured,
        Self.ui.ignore.pattern,
        Self.ui.ignore.patternMustNotContainSlashOrLineBreak,
        Self.ui.ignore.propertyKind,
        Self.ui.ignore.removeInheritedRulesParentDirectoryThatOwnsProperty,
        Self.ui.ignore.removeRule,
        Self.ui.ignore.removedIgnoreRule,
        Self.ui.ignore.resolveUnicodePathConflictsBeforeComparingGitRulesSoProperty,
        Self.ui.ignore.review,
        Self.ui.ignore.selectAll,
        Self.ui.ignore.svnIgnoreRules,
        Self.ui.ignore.thereNoGitRulesImport,
        Self.ui.ignore.unsupported,
    ]

    private static let uiLockKeys: [LocalizationKey] = [
        Self.ui.lock.alreadyHoldLocksAllSelectedFiles,
        Self.ui.lock.changedRequiredLockPropertyFileCommitItApplyChangeOther,
        Self.ui.lock.countAccessibilityLabel,
        Self.ui.lock.currentSvnClientDoesNotSupportForcedMultiFileLocking,
        Self.ui.lock.editingDocumentSvnKr,
        Self.ui.lock.file,
        Self.ui.lock.fileBeforeOpening,
        Self.ui.lock.fileCurrentlyLockedOpeningWithoutLockMayPreventCommittingCause,
        Self.ui.lock.fileLockedSuccessfulCommitAutomaticallyReleasesLock,
        Self.ui.lock.forceLock,
        Self.ui.lock.forceLockingSelectedFileRemovesExistingUsersLocksReviewOwners,
        Self.ui.lock.forceReleaseLock,
        Self.ui.lock.forceReleaseRepositoryLock,
        Self.ui.lock.forceReleasingCanInterruptSomeoneElseWorkPathOwnerLocked,
        Self.ui.lock.forceUnlockAccessForbidden,
        Self.ui.lock.forceUnlockAuthenticationRequiredOrFailed,
        Self.ui.lock.forceUnlockFailureCode,
        Self.ui.lock.forceUnlockOwnerOnlyHook,
        Self.ui.lock.informationCouldNotCheckedCanOpenFileWithoutLockingIt,
        Self.ui.lock.loadingRepositoryLocks,
        Self.ui.lock.lockAndOpenAction,
        Self.ui.lock.lockedByCurrentUser,
        Self.ui.lock.lockedByOwner,
        Self.ui.lock.lockedFile,
        Self.ui.lock.lockedFileMarkedSvnServerPreventAnotherUserCommittingIt,
        Self.ui.lock.lockingPreventsConcurrentCommitsOtherUsersReducesDocumentConflictsSuccessful,
        Self.ui.lock.noLockedFiles,
        Self.ui.lock.notAvailable,
        Self.ui.lock.openWithoutLock,
        Self.ui.lock.openWithoutLockingDonTAskAgain,
        Self.ui.lock.openedWithoutLockConcurrentCommitAnotherUserMayCauseConflict,
        Self.ui.lock.openingFileLocked,
        Self.ui.lock.releaseAllAction,
        Self.ui.lock.releaseAllConfirmationTitle,
        Self.ui.lock.releaseFromBrowserAction,
        Self.ui.lock.releaseFromListAction,
        Self.ui.lock.releaseLocks,
        Self.ui.lock.releaseLocksOwnedCurrentUserOtherUsersAbleModifyFiles,
        Self.ui.lock.releaseMyLock,
        Self.ui.lock.released,
        Self.ui.lock.releasedAllLocks,
        Self.ui.lock.releasedLocksLocksBelowCouldNotReleased,
        Self.ui.lock.removeRequiredLock,
        Self.ui.lock.repositoryLockForceReleased,
        Self.ui.lock.repositoryLocks,
        Self.ui.lock.requireLockBeforeEditing,
        Self.ui.lock.requiredBeforeEditing,
        Self.ui.lock.reviewForceLock,
        Self.ui.lock.selectedFile,
        Self.ui.lock.sheetTitle,
        Self.ui.lock.someLocksNotReleased,
        Self.ui.lock.takeAnotherUserLock,
        Self.ui.lock.tryNormalUnlockFirstIfWorkingCopyNoMatchingLock,
        Self.ui.lock.viewLockedFilesTheirCountRepository,
    ]

    private static let uiRecoveryKeys: [LocalizationKey] = [
        Self.ui.recovery.allContentsVerifiedInterruptedSvnWorkingCopyFolderBelowDeleted,
        Self.ui.recovery.automaticUnicodePathRecovery,
        Self.ui.recovery.checkoutCanceledPartiallyDownloadedFilesMayRemain,
        Self.ui.recovery.checkoutInterrupted,
        Self.ui.recovery.chooseAction,
        Self.ui.recovery.chooseEmptyFolder,
        Self.ui.recovery.chooseEmptyRecoveryFolder,
        Self.ui.recovery.chooseFolder,
        Self.ui.recovery.cleanWorkingCopyCheckedOutServerOnlyRealLocalChanges,
        Self.ui.recovery.cleaningContinuing,
        Self.ui.recovery.continueCheckout,
        Self.ui.recovery.emptiedInterruptedCheckoutFolder,
        Self.ui.recovery.emptyFolderConfirmationAction,
        Self.ui.recovery.emptyFolderRequestAction,
        Self.ui.recovery.emptyInterruptedCheckoutFolder,
        Self.ui.recovery.falseAliasesExcluded,
        Self.ui.recovery.folderAlreadyFilesBeforeCheckoutSoAppNotEmptyIt,
        Self.ui.recovery.folderIncompleteSvnWorkingCopyContinueRegisteringItCleaningIt,
        Self.ui.recovery.folderNotEmptiedBecauseItCouldNotVerifiedSafelyInterrupted,
        Self.ui.recovery.interruptedCheckoutFolderNoLongerValidSvnWorkingCopySo,
        Self.ui.recovery.localWorkingFolderAlreadyRegistered,
        Self.ui.recovery.locallyMissing,
        Self.ui.recovery.locallyMissingActionRequired,
        Self.ui.recovery.new,
        Self.ui.recovery.newWorkingFolder,
        Self.ui.recovery.newWorkingFolderRecoveryAction,
        Self.ui.recovery.newWorkingFolderRecoveryHelp,
        Self.ui.recovery.pathRecoveryCompletedOriginalWorkingFolderPreserved,
        Self.ui.recovery.preparingNewWorkingFolderRecovery,
        Self.ui.recovery.preview,
        Self.ui.recovery.recoverNewWorkingFolder,
        Self.ui.recovery.recoveryFolderMustBeOutsideCurrentWorkingFolder,
        Self.ui.recovery.successBothOriginalRecoveredCopiesRemainSidebar,
    ]

    private static let uiRepositoryKeys: [LocalizationKey] = [
        Self.ui.repository.addLocalWorkingFolder,
        Self.ui.repository.addSvnRepository,
        Self.ui.repository.cancelAddingRepositoryCloseWindow,
        Self.ui.repository.change,
        Self.ui.repository.changeRepositoryLocation,
        Self.ui.repository.chooseSvnLocalWorkingFolders,
        Self.ui.repository.commitChangeApplyItServer,
        Self.ui.repository.copyCurrentRepositoryUrl,
        Self.ui.repository.currentRepositoryUrl,
        Self.ui.repository.currentUrlNewUrlOnlyWorkingCopyRepositoryConnectionChanges,
        Self.ui.repository.destinationNameAlreadyExists,
        Self.ui.repository.enterValidFileNameWithoutFolderPath,
        Self.ui.repository.enterValidRepositoryUrlIncludingItsScheme,
        Self.ui.repository.filePanelPrompt,
        Self.ui.repository.localFolder,
        Self.ui.repository.localFolderPickerAction,
        Self.ui.repository.localWorkingFolders,
        Self.ui.repository.mayMovedRelocateNewUrlRestoreRemoteOperations,
        Self.ui.repository.newFileName,
        Self.ui.repository.newFileNameMatchesCurrentName,
        Self.ui.repository.newFolderAppliedWhenSave,
        Self.ui.repository.newRepositoryUrl,
        Self.ui.repository.newRepositoryUrlMatchesCurrentUrl,
        Self.ui.repository.notSvnVersionedFile,
        Self.ui.repository.onlyRegularFilesCanRenamedCopiedAssignedRequiredLockProperty,
        Self.ui.repository.openFinder,
        Self.ui.repository.openRepositoryRelocation,
        Self.ui.repository.openSvnLocalWorkingFolderFinder,
        Self.ui.repository.pickNewLocationSvnWorkingFolder,
        Self.ui.repository.pressOUseButtonBottomLeft,
        Self.ui.repository.registerExistingLocalFolder,
        Self.ui.repository.registerExistingSvnWorkingFolderApp,
        Self.ui.repository.relocateAction,
        Self.ui.repository.relocatedRepositoryConnectionLocalChangesPreserved,
        Self.ui.repository.relocatingRepository,
        Self.ui.repository.relocationConfirmationTitle,
        Self.ui.repository.relocationFailedCheckCurrentUrlRelocateCorrectNewUrlIf,
        Self.ui.repository.relocationPreservesAllUncommittedLocalChanges,
        Self.ui.repository.removeApp,
        Self.ui.repository.removeSelectedWorkingFolderAppLocalFilesNotDeleted,
        Self.ui.repository.reviewRelocation,
        Self.ui.repository.workingFolderChanged,
        Self.ui.repository.workingFolderNoLongerExistsRestoreFolderRemoveItList,
    ]

    private static let uiRevisionKeys: [LocalizationKey] = [
        Self.ui.revision.chooseChangedFileAboveDisplayOnlyThatFileDiff,
        Self.ui.revision.chooseViewChangesHistoryDisplayActualDiff,
        Self.ui.revision.commitChanges,
        Self.ui.revision.commitNotFound,
        Self.ui.revision.currentContentsDiscardedReplacedRRecoveryCopySavedFirstResult,
        Self.ui.revision.currentWorkingFileCouldNotVerifiedRecoveryCopySoIt,
        Self.ui.revision.fileCommitHistory,
        Self.ui.revision.filePathPointsOutsideLocalWorkingFolder,
        Self.ui.revision.folderForRestoredFileNotDirectory,
        Self.ui.revision.loadingChanges,
        Self.ui.revision.loadingFileHistory,
        Self.ui.revision.noChangedFiles,
        Self.ui.revision.noFileHistory,
        Self.ui.revision.projectSvnClientDoesNotSupportReadingHistoricalFileRevisions,
        Self.ui.revision.recoveryCopiesMustStoredOutsideLocalWorkingFolder,
        Self.ui.revision.restoreWorkingFile,
        Self.ui.revision.restoreWorkingFileRevision,
        Self.ui.revision.restoredFileDidNotMatchSelectedRevisionByteByteRecovery,
        Self.ui.revision.restoredRNowLocalChangeCommitItUpdateServer,
        Self.ui.revision.restoringRevision,
        Self.ui.revision.saveRevision,
        Self.ui.revision.savedR,
        Self.ui.revision.savingRevision,
        Self.ui.revision.searchAuthorFileMessageRevision,
        Self.ui.revision.selectCommit,
        Self.ui.revision.selectFile,
        Self.ui.revision.selectedSaveLocationNotSafeRegularFileDestination,
        Self.ui.revision.workingFileMustRegularFileNotSymbolicLink,
    ]

    private static let uiSettingsKeys: [LocalizationKey] = [
        Self.ui.settings.alwaysLockOpenWithoutAsking,
        Self.ui.settings.alwaysOpenWithoutLockingAsking,
        Self.ui.settings.askEveryTime,
        Self.ui.settings.chooseLanguageUsedAppInterface,
        Self.ui.settings.chooseTimeZoneUsedCommitDatesTimes,
        Self.ui.settings.commitDisplayTimeZone,
        Self.ui.settings.coordinatedUniversalTimeUtc,
        Self.ui.settings.defaultKoreaStandardTimeKstDoesNotChangeOriginalCommit,
        Self.ui.settings.folderSettings,
        Self.ui.settings.hideMacOfficeTemporaryFiles,
        Self.ui.settings.hideTemporaryFilesChangesPreventThemCommittedVersionedFilesRemain,
        Self.ui.settings.japanStandardTime,
        Self.ui.settings.koreaStandardTime,
        Self.ui.settings.language,
        Self.ui.settings.macSystemTimeZone,
        Self.ui.settings.openAppWideSettingsWindow,
        Self.ui.settings.otherUsersCannotModifyLockedFileUntilCommitItRelease,
        Self.ui.settings.settings,
        Self.ui.settings.ukTime,
        Self.ui.settings.usEasternTime,
        Self.ui.settings.usPacificTime,
        Self.ui.settings.whenOpeningDocuments,
    ]

    private static let uiStatusKeys: [LocalizationKey] = [
        Self.ui.status.added,
        Self.ui.status.deleted,
        Self.ui.status.diskContainingFolderStoresKoreanFilenamesOnlyDecomposedFormFilenames,
        Self.ui.status.filenameWarning,
        Self.ui.status.ignored,
        Self.ui.status.lockedFiles,
        Self.ui.status.modified,
        Self.ui.status.replaced,
        Self.ui.status.unversioned,
    ]

    private static let uiUpdateKeys: [LocalizationKey] = [
        Self.ui.update.addRepositoryTemporaryFileCleanupCommitAfterUpdating,
        Self.ui.update.afterUpdateCandidateContentsVerifiedReviewFinalListBeforeAny,
        Self.ui.update.beforeRetryingCommit,
        Self.ui.update.checkAppStoreLatestVersion,
        Self.ui.update.checkFromAppMenu,
        Self.ui.update.checkNow,
        Self.ui.update.checkingIncomingChanges,
        Self.ui.update.checkingUpdates,
        Self.ui.update.checkoutUpdateInterruptedDoNotRevertLocalChangesContinueUpdating,
        Self.ui.update.cleanedRepositoryTemporaryFile,
        Self.ui.update.commitMessageSelectedItemSavedIfUpdateCreatesNoConflicts,
        Self.ui.update.completeUpdatePreviewCouldNotLoadedCanStillTryUpdate,
        Self.ui.update.continueUpdating,
        Self.ui.update.createdConflictsSoCommitNotRetried,
        Self.ui.update.createdConflictsSoCommitNotRetriedResolvePathsFirst,
        Self.ui.update.downloadLatestServerChangesCurrentLocalWorkingFolder,
        Self.ui.update.goConflictResolution,
        Self.ui.update.incomingChangesThatOverlapLocalEditsMayCreateSvnConflict,
        Self.ui.update.incomplete,
        Self.ui.update.later,
        Self.ui.update.localFileBlockingUpdate,
        Self.ui.update.lockedRepository,
        Self.ui.update.newVersionDialogTitle,
        Self.ui.update.noIncomingChanges,
        Self.ui.update.preview,
        Self.ui.update.previewAvailableStatus,
        Self.ui.update.reUsingLatestVersion,
        Self.ui.update.requiredBeforeCommit,
        Self.ui.update.retryCommit,
        Self.ui.update.runUpdate,
        Self.ui.update.serverChangesInsidePendingDeletionMayNotAppearListRun,
        Self.ui.update.showingFirstCommits,
        Self.ui.update.sidebarAvailableBadge,
        Self.ui.update.someSavedCommitSelectionsDisappearedChangeListAfterUpdateReview,
        Self.ui.update.someTemporaryFilesNotCleaned,
        Self.ui.update.succeededButCleanupCommitFailedScheduledDeletionsRestored,
        Self.ui.update.succeededButCleanupCouldNotStart,
        Self.ui.update.svnRequiresWorkingCopyUpdateConfirmUpdateRetryCommitSaved,
        Self.ui.update.unableCheckAppStoreUpdates,
        Self.ui.update.update,
        Self.ui.update.updating,
        Self.ui.update.versionAvailable,
        Self.ui.update.viewAppStore,
        Self.ui.update.workingCopyUpDateServer,
    ]

    private static let uiKeys: [LocalizationKey] = [
        uiAboutKeys,
        uiAuthenticationKeys,
        uiBrowserKeys,
        uiCertificateKeys,
        uiChangesKeys,
        uiCheckoutKeys,
        uiCleanupKeys,
        uiCommitKeys,
        uiCommonKeys,
        uiConflictKeys,
        uiDemoKeys,
        uiErrorKeys,
        uiFileKeys,
        uiHistoryKeys,
        uiIgnoreKeys,
        uiLockKeys,
        uiRecoveryKeys,
        uiRepositoryKeys,
        uiRevisionKeys,
        uiSettingsKeys,
        uiStatusKeys,
        uiUpdateKeys,
    ].flatMap { $0 }

    static let allCases: [LocalizationKey] = errorKeys + historyKeys + recoveryKeys + repositoryKeys + uiKeys
}

struct LocalizationErrorKeys {
    let deletion = LocalizationErrorDeletionKeys()
    let path = LocalizationErrorPathKeys()
    let recovery = LocalizationErrorRecoveryKeys()
}

struct LocalizationErrorDeletionKeys {
    let chooseMissingItems = LocalizationKey("error.deletion.chooseMissingItems")
    let partial = LocalizationKey("error.deletion.partial")
    let unresolvedMissingPaths = LocalizationKey("error.deletion.unresolvedMissingPaths")
    let validation = LocalizationKey("error.deletion.validation")
}

struct LocalizationErrorPathKeys {
    let aliasRepair = LocalizationKey("error.path.aliasRepair")
    let normalizationCollision = LocalizationKey("error.path.normalizationCollision")
    let unsupportedTarget = LocalizationKey("error.path.unsupportedTarget")
}

struct LocalizationErrorRecoveryKeys {
    let blocked = LocalizationKey("error.recovery.blocked")
    let fileReplacement = LocalizationKey("error.recovery.fileReplacement")
    let validation = LocalizationKey("error.recovery.validation")
}

struct LocalizationHistoryKeys {
    let copy = LocalizationHistoryCopyKeys()
}

struct LocalizationHistoryCopyKeys {
    let copiedFrom = LocalizationKey("history.copy.copiedFrom")
}

struct LocalizationRecoveryKeys {
    let path = LocalizationRecoveryPathKeys()
}

struct LocalizationRecoveryPathKeys {
    let reviewPaths = LocalizationKey("recovery.path.reviewPaths")
}

struct LocalizationRepositoryKeys {
    let pathNormalization = LocalizationRepositoryPathNormalizationKeys()
}

struct LocalizationRepositoryPathNormalizationKeys {
    let action = LocalizationKey("repository.pathNormalization.action")
    let actionHelp = LocalizationKey("repository.pathNormalization.actionHelp")
    let after = LocalizationKey("repository.pathNormalization.after")
    let before = LocalizationKey("repository.pathNormalization.before")
    let codepointsDetail = LocalizationKey("repository.pathNormalization.codepointsDetail")
    let confirmationCommits = LocalizationKey("repository.pathNormalization.confirmationCommits")
    let confirmationDeleteAdd = LocalizationKey("repository.pathNormalization.confirmationDeleteAdd")
    let confirmationDirectory = LocalizationKey("repository.pathNormalization.confirmationDirectory")
    let confirmationRun = LocalizationKey("repository.pathNormalization.confirmationRun")
    let confirmationTeam = LocalizationKey("repository.pathNormalization.confirmationTeam")
    let confirmationTitle = LocalizationKey("repository.pathNormalization.confirmationTitle")
    let defaultCommitMessage = LocalizationKey("repository.pathNormalization.defaultCommitMessage")
    let deselectAll = LocalizationKey("repository.pathNormalization.deselectAll")
    let differentComponent = LocalizationKey("repository.pathNormalization.differentComponent")
    let directoryNote = LocalizationKey("repository.pathNormalization.directoryNote")
    let errorInvalidTargets = LocalizationKey("repository.pathNormalization.errorInvalidTargets")
    let errorLocalChanges = LocalizationKey("repository.pathNormalization.errorLocalChanges")
    let errorLocks = LocalizationKey("repository.pathNormalization.errorLocks")
    let errorPartialFailure = LocalizationKey("repository.pathNormalization.errorPartialFailure")
    let errorUnknown = LocalizationKey("repository.pathNormalization.errorUnknown")
    let formComposed = LocalizationKey("repository.pathNormalization.formComposed")
    let formDecomposed = LocalizationKey("repository.pathNormalization.formDecomposed")
    let noPaths = LocalizationKey("repository.pathNormalization.noPaths")
    let problem = LocalizationKey("repository.pathNormalization.problem")
    let result = LocalizationKey("repository.pathNormalization.result")
    let resultRevisions = LocalizationKey("repository.pathNormalization.resultRevisions")
    let resultSummary = LocalizationKey("repository.pathNormalization.resultSummary")
    let reviewAction = LocalizationKey("repository.pathNormalization.reviewAction")
    let running = LocalizationKey("repository.pathNormalization.running")
    let sameAppearanceNote = LocalizationKey("repository.pathNormalization.sameAppearanceNote")
    let scanAgain = LocalizationKey("repository.pathNormalization.scanAgain")
    let scanning = LocalizationKey("repository.pathNormalization.scanning")
    let scanningDetail = LocalizationKey("repository.pathNormalization.scanningDetail")
    let skipped = LocalizationKey("repository.pathNormalization.skipped")
    let skippedReason = LocalizationKey("repository.pathNormalization.skippedReason")
    let targets = LocalizationKey("repository.pathNormalization.targets")
    let title = LocalizationKey("repository.pathNormalization.title")
    let waiting = LocalizationKey("repository.pathNormalization.waiting")
    let windowsNote = LocalizationKey("repository.pathNormalization.windowsNote")
}

struct LocalizationUIKeys {
    let about = LocalizationUIAboutKeys()
    let authentication = LocalizationUIAuthenticationKeys()
    let browser = LocalizationUIBrowserKeys()
    let certificate = LocalizationUICertificateKeys()
    let changes = LocalizationUIChangesKeys()
    let checkout = LocalizationUICheckoutKeys()
    let cleanup = LocalizationUICleanupKeys()
    let commit = LocalizationUICommitKeys()
    let common = LocalizationUICommonKeys()
    let conflict = LocalizationUIConflictKeys()
    let demo = LocalizationUIDemoKeys()
    let error = LocalizationUIErrorKeys()
    let file = LocalizationUIFileKeys()
    let history = LocalizationUIHistoryKeys()
    let ignore = LocalizationUIIgnoreKeys()
    let lock = LocalizationUILockKeys()
    let recovery = LocalizationUIRecoveryKeys()
    let repository = LocalizationUIRepositoryKeys()
    let revision = LocalizationUIRevisionKeys()
    let settings = LocalizationUISettingsKeys()
    let status = LocalizationUIStatusKeys()
    let update = LocalizationUIUpdateKeys()
}

struct LocalizationUIAboutKeys {
    let needHelp = LocalizationKey("ui.about.needHelp")
    let pleaseSendQuestions = LocalizationKey("ui.about.pleaseSendQuestions")
    let questionsSupport = LocalizationKey("ui.about.questionsSupport")
    let sendEmail = LocalizationKey("ui.about.sendEmail")
    let svnKr = LocalizationKey("ui.about.svnKr")
    let version = LocalizationKey("ui.about.version")
}

struct LocalizationUIAuthenticationKeys {
    let canceledLocalChangesRemainAvailable = LocalizationKey("ui.authentication.canceledLocalChangesRemainAvailable")
    let cancelingDoesNotPreventViewingLocalChangesDiffs = LocalizationKey("ui.authentication.cancelingDoesNotPreventViewingLocalChangesDiffs")
    let changeFolderLocationSvnAccountKeychainPassword = LocalizationKey("ui.authentication.changeFolderLocationSvnAccountKeychainPassword")
    let checkingAccount = LocalizationKey("ui.authentication.checkingAccount")
    let checkoutCompletedButPasswordCouldNotSavedKeychain = LocalizationKey("ui.authentication.checkoutCompletedButPasswordCouldNotSavedKeychain")
    let closeWithoutSavingCredentialChanges = LocalizationKey("ui.authentication.closeWithoutSavingCredentialChanges")
    let configureSvnAccountKeychainPasswordLocalWorkingFolder = LocalizationKey("ui.authentication.configureSvnAccountKeychainPasswordLocalWorkingFolder")
    let credentials = LocalizationKey("ui.authentication.credentials")
    let credentialsSaved = LocalizationKey("ui.authentication.credentialsSaved")
    let deleteSavedPassword = LocalizationKey("ui.authentication.deleteSavedPassword")
    let deleteSvnPasswordStoredKeychainLocalWorkingFolder = LocalizationKey("ui.authentication.deleteSvnPasswordStoredKeychainLocalWorkingFolder")
    let discardChangesClose = LocalizationKey("ui.authentication.discardChangesClose")
    let enterPassword = LocalizationKey("ui.authentication.enterPassword")
    let enterValidCredentials = LocalizationKey("ui.authentication.enterValidCredentials")
    let folderCredentials = LocalizationKey("ui.authentication.folderCredentials")
    let hidePassword = LocalizationKey("ui.authentication.hidePassword")
    let keychainAccessDenied = LocalizationKey("ui.authentication.keychainAccessDenied")
    let keychainAccessDeniedChooseHowAuthenticate = LocalizationKey("ui.authentication.keychainAccessDeniedChooseHowAuthenticate")
    let keychainOperationFailed = LocalizationKey("ui.authentication.keychainOperationFailed")
    let leaveBlankKeepCurrentPassword = LocalizationKey("ui.authentication.leaveBlankKeepCurrentPassword")
    let noPasswordStored = LocalizationKey("ui.authentication.noPasswordStored")
    let password = LocalizationKey("ui.authentication.password")
    let passwordFolderStoredMacosKeychain = LocalizationKey("ui.authentication.passwordFolderStoredMacosKeychain")
    let repositoryAuthenticationFailed = LocalizationKey("ui.authentication.repositoryAuthenticationFailed")
    let requiredCommitSelectedChanges = LocalizationKey("ui.authentication.requiredCommitSelectedChanges")
    let requiredDownloadLatestServerChanges = LocalizationKey("ui.authentication.requiredDownloadLatestServerChanges")
    let requiredLoadLatestServerHistory = LocalizationKey("ui.authentication.requiredLoadLatestServerHistory")
    let saveKeychainUse = LocalizationKey("ui.authentication.saveKeychainUse")
    let saveMacosKeychainOptional = LocalizationKey("ui.authentication.saveMacosKeychainOptional")
    let saveSvnUsernameNewPasswordLocalWorkingFolder = LocalizationKey("ui.authentication.saveSvnUsernameNewPasswordLocalWorkingFolder")
    let saveWorkingFolderLocationSvnUsernameNewPasswordFolder = LocalizationKey("ui.authentication.saveWorkingFolderLocationSvnUsernameNewPasswordFolder")
    let savedPasswordDeleted = LocalizationKey("ui.authentication.savedPasswordDeleted")
    let saving = LocalizationKey("ui.authentication.saving")
    let secureEntryBlocksKoreanInputMethodRevealPasswordEyeButton = LocalizationKey("ui.authentication.secureEntryBlocksKoreanInputMethodRevealPasswordEyeButton")
    let showMacosKeychainAccessPromptAgain = LocalizationKey("ui.authentication.showMacosKeychainAccessPromptAgain")
    let showPassword = LocalizationKey("ui.authentication.showPassword")
    let svnAccountPasswordNotValid = LocalizationKey("ui.authentication.svnAccountPasswordNotValid")
    let svnAuthenticationRequired = LocalizationKey("ui.authentication.svnAuthenticationRequired")
    let svnPassword = LocalizationKey("ui.authentication.svnPassword")
    let svnServerDeniedReadAccessFileCheckProjectCredentialsServer = LocalizationKey("ui.authentication.svnServerDeniedReadAccessFileCheckProjectCredentialsServer")
    let svnUsername = LocalizationKey("ui.authentication.svnUsername")
    let svnUsernameOptional = LocalizationKey("ui.authentication.svnUsernameOptional")
    let tryKeychainAgain = LocalizationKey("ui.authentication.tryKeychainAgain")
    let useSessionOnly = LocalizationKey("ui.authentication.useSessionOnly")
    let username = LocalizationKey("ui.authentication.username")
    let usesExistingSvnCredentialCacheMacosKeychain = LocalizationKey("ui.authentication.usesExistingSvnCredentialCacheMacosKeychain")
}

struct LocalizationUIBrowserKeys {
    let actions = LocalizationKey("ui.browser.actions")
    let browse = LocalizationKey("ui.browser.browse")
    let browseRepository = LocalizationKey("ui.browser.browseRepository")
    let browseSvnRepository = LocalizationKey("ui.browser.browseSvnRepository")
    let checkFoldersFilesBeforeChoosingRepositoryPathCheckOut = LocalizationKey("ui.browser.checkFoldersFilesBeforeChoosingRepositoryPathCheckOut")
    let chooseHowFilesDisplayed = LocalizationKey("ui.browser.chooseHowFilesDisplayed")
    let couldNotConnectRepository = LocalizationKey("ui.browser.couldNotConnectRepository")
    let couldNotLoadRepositoryContents = LocalizationKey("ui.browser.couldNotLoadRepositoryContents")
    let dateModified = LocalizationKey("ui.browser.dateModified")
    let directory = LocalizationKey("ui.browser.directory")
    let directoryEmpty = LocalizationKey("ui.browser.directoryEmpty")
    let enterRepositoryUrlBrowse = LocalizationKey("ui.browser.enterRepositoryUrlBrowse")
    let fileAccessibilityLabel = LocalizationKey("ui.browser.fileAccessibilityLabel")
    let files = LocalizationKey("ui.browser.files")
    let items = LocalizationKey("ui.browser.items")
    let kind = LocalizationKey("ui.browser.kind")
    let loadingFiles = LocalizationKey("ui.browser.loadingFiles")
    let loadingRepositoryContents = LocalizationKey("ui.browser.loadingRepositoryContents")
    let name = LocalizationKey("ui.browser.name")
    let noFiles = LocalizationKey("ui.browser.noFiles")
    let noSearchResults = LocalizationKey("ui.browser.noSearchResults")
    let openSelectedDirectory = LocalizationKey("ui.browser.openSelectedDirectory")
    let parentDirectory = LocalizationKey("ui.browser.parentDirectory")
    let repositoryReturnedNoFilesSubdirectoriesPath = LocalizationKey("ui.browser.repositoryReturnedNoFilesSubdirectoriesPath")
    let repositoryUrl = LocalizationKey("ui.browser.repositoryUrl")
    let revisionOptional = LocalizationKey("ui.browser.revisionOptional")
    let searchFiles = LocalizationKey("ui.browser.searchFiles")
    let size = LocalizationKey("ui.browser.size")
    let splitView = LocalizationKey("ui.browser.splitView")
    let symbolicLink = LocalizationKey("ui.browser.symbolicLink")
    let treeView = LocalizationKey("ui.browser.treeView")
    let useRepositoryPath = LocalizationKey("ui.browser.useRepositoryPath")
    let workingCopy = LocalizationKey("ui.browser.workingCopy")
}

struct LocalizationUICertificateKeys {
    let allowProject = LocalizationKey("ui.certificate.allowProject")
    let allowSelfSignedCertificateNameMismatchErrorsRepository = LocalizationKey("ui.certificate.allowSelfSignedCertificateNameMismatchErrorsRepository")
    let allowUntrustedSslCertificates = LocalizationKey("ui.certificate.allowUntrustedSslCertificates")
    let doNotAllow = LocalizationKey("ui.certificate.doNotAllow")
    let exceptionNotAllowedNoProjectSettingChanged = LocalizationKey("ui.certificate.exceptionNotAllowedNoProjectSettingChanged")
    let exceptionSecurityWarning = LocalizationKey("ui.certificate.exceptionSecurityWarning")
    let expiredNotYetValidCertificatesRequireSeparateConsentAfterSvn = LocalizationKey("ui.certificate.expiredNotYetValidCertificatesRequireSeparateConsentAfterSvn")
    let issuedDifferentHostnameCheckRepositoryUrlCertificateHostnameBeforeAllowing = LocalizationKey("ui.certificate.issuedDifferentHostnameCheckRepositoryUrlCertificateHostnameBeforeAllowing")
    let issuerNotTrustedConfirmIssuerServerAdministratorAllowingItBypasses = LocalizationKey("ui.certificate.issuerNotTrustedConfirmIssuerServerAdministratorAllowingItBypasses")
    let notYetValidCheckServerMacClocksCertificateStartDate = LocalizationKey("ui.certificate.notYetValidCheckServerMacClocksCertificateStartDate")
    let savedCertificateExceptionRetrySvnOperation = LocalizationKey("ui.certificate.savedCertificateExceptionRetrySvnOperation")
    let serverCertificateExpiredRenewingItSafestAllowingItLetsProject = LocalizationKey("ui.certificate.serverCertificateExpiredRenewingItSafestAllowingItLetsProject")
    let serverCertificateProblem = LocalizationKey("ui.certificate.serverCertificateProblem")
    let svnRejectedServerCertificateReviewDetectedProblemBeforeDeciding = LocalizationKey("ui.certificate.svnRejectedServerCertificateReviewDetectedProblemBeforeDeciding")
    let svnReportedCertificateProblemButDidNotIdentifySupportedReason = LocalizationKey("ui.certificate.svnReportedCertificateProblemButDidNotIdentifySupportedReason")
    let useOnlyServersSelfSignedCertificatesCertificateNameMismatches = LocalizationKey("ui.certificate.useOnlyServersSelfSignedCertificatesCertificateNameMismatches")
    let useWhenTargetServerCertificateInvalidButTrustServer = LocalizationKey("ui.certificate.useWhenTargetServerCertificateInvalidButTrustServer")
}

struct LocalizationUIChangesKeys {
    let affected = LocalizationKey("ui.changes.affected")
    let cancelDeletionRestore = LocalizationKey("ui.changes.cancelDeletionRestore")
    let collapseFolder = LocalizationKey("ui.changes.collapseFolder")
    let deletePendingItems = LocalizationKey("ui.changes.deletePendingItems")
    let deleteRepository = LocalizationKey("ui.changes.deleteRepository")
    let expandFolder = LocalizationKey("ui.changes.expandFolder")
    let filesInsideFolderAddedTogether = LocalizationKey("ui.changes.filesInsideFolderAddedTogether")
    let includeCommit = LocalizationKey("ui.changes.includeCommit")
    let includeExcludeFileNextCommit = LocalizationKey("ui.changes.includeExcludeFileNextCommit")
    let localChangesRefreshed = LocalizationKey("ui.changes.localChangesRefreshed")
    let multipleCanonicallyEquivalentServerPathsExistSoAppCannotChoose = LocalizationKey("ui.changes.multipleCanonicallyEquivalentServerPathsExistSoAppCannotChoose")
    let noChanges = LocalizationKey("ui.changes.noChanges")
    let pathPointsDifferentRepositoryLocationVerifyCommitDestination = LocalizationKey("ui.changes.pathPointsDifferentRepositoryLocationVerifyCommitDestination")
    let pendingDeletionStatus = LocalizationKey("ui.changes.pendingDeletionStatus")
    let propertiesModified = LocalizationKey("ui.changes.propertiesModified")
    let resolveDuplicateServerPathsManually = LocalizationKey("ui.changes.resolveDuplicateServerPathsManually")
    let restoreLocalFile = LocalizationKey("ui.changes.restoreLocalFile")
    let restorePendingDeletions = LocalizationKey("ui.changes.restorePendingDeletions")
    let revertConflictLocalChanges = LocalizationKey("ui.changes.revertConflictLocalChanges")
    let selectChangedFileViewItsDiff = LocalizationKey("ui.changes.selectChangedFileViewItsDiff")
    let showIgnoredFiles = LocalizationKey("ui.changes.showIgnoredFiles")
    let showsDiffFile = LocalizationKey("ui.changes.showsDiffFile")
    let switchedPath = LocalizationKey("ui.changes.switchedPath")
    let temporary = LocalizationKey("ui.changes.temporary")
    let thereNoLocallyModifiedFiles = LocalizationKey("ui.changes.thereNoLocallyModifiedFiles")
    let unicodePathConflict = LocalizationKey("ui.changes.unicodePathConflict")
    let unversionedLocalFileBlockingServerFileSameNameMoveRename = LocalizationKey("ui.changes.unversionedLocalFileBlockingServerFileSameNameMoveRename")
}

struct LocalizationUICheckoutKeys {
    let checkOutAdd = LocalizationKey("ui.checkout.checkOutAdd")
    let checkOutNewSvnRepositoryRegisterExistingLocalWorkingFolder = LocalizationKey("ui.checkout.checkOutNewSvnRepositoryRegisterExistingLocalWorkingFolder")
    let checkOutRepositoryUrl = LocalizationKey("ui.checkout.checkOutRepositoryUrl")
    let checkOutRepositoryUrlAddItLocalWorkingFolders = LocalizationKey("ui.checkout.checkOutRepositoryUrlAddItLocalWorkingFolders")
    let checkOutSvnRepositoryLocalFolderAddItApp = LocalizationKey("ui.checkout.checkOutSvnRepositoryLocalFolderAddItApp")
    let checkingOut = LocalizationKey("ui.checkout.checkingOut")
    let chooseLocalCheckoutFolder = LocalizationKey("ui.checkout.chooseLocalCheckoutFolder")
    let filesDownloadedAppearHereAfterCheckoutStarts = LocalizationKey("ui.checkout.filesDownloadedAppearHereAfterCheckoutStarts")
    let keepDownloading = LocalizationKey("ui.checkout.keepDownloading")
    let localFolderPickerHelp = LocalizationKey("ui.checkout.localFolderPickerHelp")
    let localFolderRequiredError = LocalizationKey("ui.checkout.localFolderRequiredError")
    let progressLog = LocalizationKey("ui.checkout.progressLog")
    let runningSvnCheckoutStoppedAlreadyDownloadedFilesStayLocalFolder = LocalizationKey("ui.checkout.runningSvnCheckoutStoppedAlreadyDownloadedFilesStayLocalFolder")
    let stopCheckout = LocalizationKey("ui.checkout.stopCheckout")
    let stopCheckoutProgress = LocalizationKey("ui.checkout.stopCheckoutProgress")
}

struct LocalizationUICleanupKeys {
    let candidateNotRegularFile = LocalizationKey("ui.cleanup.candidateNotRegularFile")
    let cleanUpEquivalentPath = LocalizationKey("ui.cleanup.cleanUpEquivalentPath")
    let cleaningCommitting = LocalizationKey("ui.cleanup.cleaningCommitting")
    let cleaningWorkingCopy = LocalizationKey("ui.cleanup.cleaningWorkingCopy")
    let deleteCommitCleanup = LocalizationKey("ui.cleanup.deleteCommitCleanup")
    let fileContentsCouldNotRead = LocalizationKey("ui.cleanup.fileContentsCouldNotRead")
    let fileDoesNotAppledoubleMagicBytes = LocalizationKey("ui.cleanup.fileDoesNotAppledoubleMagicBytes")
    let fileDoesNotDsStoreBud1Signature = LocalizationKey("ui.cleanup.fileDoesNotDsStoreBud1Signature")
    let fileNotFoundAfterUpdate = LocalizationKey("ui.cleanup.fileNotFoundAfterUpdate")
    let manuallyCleanUpInterruptedLockedSvnWorkingCopy = LocalizationKey("ui.cleanup.manuallyCleanUpInterruptedLockedSvnWorkingCopy")
    let needed = LocalizationKey("ui.cleanup.needed")
    let officeLockFileExceedsByteSafetyLimit = LocalizationKey("ui.cleanup.officeLockFileExceedsByteSafetyLimit")
    let onlyVerifiedCandidatesSelectedReviewEveryPathBeforeDeletingCommitting = LocalizationKey("ui.cleanup.onlyVerifiedCandidatesSelectedReviewEveryPathBeforeDeletingCommitting")
    let operationInterruptedLikeCleanUpWorkingCopyTryAgainCleanup = LocalizationKey("ui.cleanup.operationInterruptedLikeCleanUpWorkingCopyTryAgainCleanup")
    let pathOutsideWorkingCopySafetyBoundary = LocalizationKey("ui.cleanup.pathOutsideWorkingCopySafetyBoundary")
    let repositoryTemporaryFileCleanup = LocalizationKey("ui.cleanup.repositoryTemporaryFileCleanup")
    let runCleanup = LocalizationKey("ui.cleanup.runCleanup")
    let symbolicLinksNeverCleanedAutomatically = LocalizationKey("ui.cleanup.symbolicLinksNeverCleanedAutomatically")
    let workingCopyCleanup = LocalizationKey("ui.cleanup.workingCopyCleanup")
    let workingCopyCleanupCompleted = LocalizationKey("ui.cleanup.workingCopyCleanupCompleted")
    let workingCopyCleanupFailedDoNotRetryCleanupRepeatedlyCopy = LocalizationKey("ui.cleanup.workingCopyCleanupFailedDoNotRetryCleanupRepeatedlyCopy")
}

struct LocalizationUICommitKeys {
    let cancelRepositoryDeletionStateRestoreRepositoryVersionLocally = LocalizationKey("ui.commit.cancelRepositoryDeletionStateRestoreRepositoryVersionLocally")
    let clearAllSelectedCommitTargets = LocalizationKey("ui.commit.clearAllSelectedCommitTargets")
    let clearSelection = LocalizationKey("ui.commit.clearSelection")
    let committing = LocalizationKey("ui.commit.committing")
    let confirm = LocalizationKey("ui.commit.confirm")
    let diffUnavailableUntilFileAddedSvnItAddedAutomaticallyWhen = LocalizationKey("ui.commit.diffUnavailableUntilFileAddedSvnItAddedAutomaticallyWhen")
    let includeRestore = LocalizationKey("ui.commit.includeRestore")
    let item = LocalizationKey("ui.commit.item")
    let itemDeletedServer = LocalizationKey("ui.commit.itemDeletedServer")
    let markDeletion = LocalizationKey("ui.commit.markDeletion")
    let markRepositoryDeletion = LocalizationKey("ui.commit.markRepositoryDeletion")
    let markedItemDeletionCommitDeleteThemRepository = LocalizationKey("ui.commit.markedItemDeletionCommitDeleteThemRepository")
    let message = LocalizationKey("ui.commit.message")
    let messageSavedIncorrectEncodingShownAfterRestorationOtherSvnUsers = LocalizationKey("ui.commit.messageSavedIncorrectEncodingShownAfterRestorationOtherSvnUsers")
    let no = LocalizationKey("ui.commit.no")
    let noCommitMessage = LocalizationKey("ui.commit.noCommitMessage")
    let noFilesDeleted = LocalizationKey("ui.commit.noFilesDeleted")
    let onlyMarksItemsDeletionTheyDeletedSvnRepositoryWhenCommitted = LocalizationKey("ui.commit.onlyMarksItemsDeletionTheyDeletedSvnRepositoryWhenCommitted")
    let outputAppearsHereAfterCommitStarts = LocalizationKey("ui.commit.outputAppearsHereAfterCommitStarts")
    let pendingDeletionCount = LocalizationKey("ui.commit.pendingDeletionCount")
    let progressLog = LocalizationKey("ui.commit.progressLog")
    let recordedEmptyMessage = LocalizationKey("ui.commit.recordedEmptyMessage")
    let restoreSelectedDeletionFileServer = LocalizationKey("ui.commit.restoreSelectedDeletionFileServer")
    let restoreSelectedFilesAction = LocalizationKey("ui.commit.restoreSelectedFilesAction")
    let restoreSelectedFilesConfirmationTitle = LocalizationKey("ui.commit.restoreSelectedFilesConfirmationTitle")
    let restoreSelectionHelp = LocalizationKey("ui.commit.restoreSelectionHelp")
    let restoreServer = LocalizationKey("ui.commit.restoreServer")
    let revert = LocalizationKey("ui.commit.revert")
    let revertLocalChangesAction = LocalizationKey("ui.commit.revertLocalChangesAction")
    let revertLocalChangesConfirmationTitle = LocalizationKey("ui.commit.revertLocalChangesConfirmationTitle")
    let reviewCommit = LocalizationKey("ui.commit.reviewCommit")
    let selectAll = LocalizationKey("ui.commit.selectAll")
    let selectAllCurrentlyChangedFilesCommit = LocalizationKey("ui.commit.selectAllCurrentlyChangedFilesCommit")
    let selected = LocalizationKey("ui.commit.selected")
    let selectedFilesSvnServerEnteredMessage = LocalizationKey("ui.commit.selectedFilesSvnServerEnteredMessage")
    let someFilesDeletedReviewListBelowConfirmThatTheyShould = LocalizationKey("ui.commit.someFilesDeletedReviewListBelowConfirmThatTheyShould")
    let uncommittedChangesDiscardedCannotRestoredSvn = LocalizationKey("ui.commit.uncommittedChangesDiscardedCannotRestoredSvn")
    let versionedItemsBelowSelectedDirectoryAlsoMarkedDeletion = LocalizationKey("ui.commit.versionedItemsBelowSelectedDirectoryAlsoMarkedDeletion")
    let withoutMessage = LocalizationKey("ui.commit.withoutMessage")
}

struct LocalizationUICommonKeys {
    let cancel = LocalizationKey("ui.common.cancel")
    let changes = LocalizationKey("ui.common.changes")
    let close = LocalizationKey("ui.common.close")
    let copyFullPath = LocalizationKey("ui.common.copyFullPath")
    let couldNotOpenFile = LocalizationKey("ui.common.couldNotOpenFile")
    let fileType = LocalizationKey("ui.common.fileType")
    let folder = LocalizationKey("ui.common.folder")
    let noTextDiffAvailableMayNewBinaryFile = LocalizationKey("ui.common.noTextDiffAvailableMayNewBinaryFile")
    let openFile = LocalizationKey("ui.common.openFile")
    let refresh = LocalizationKey("ui.common.refresh")
    let refreshed = LocalizationKey("ui.common.refreshed")
    let remove = LocalizationKey("ui.common.remove")
    let revealFinder = LocalizationKey("ui.common.revealFinder")
    let save = LocalizationKey("ui.common.save")
    let selectedCount = LocalizationKey("ui.common.selectedCount")
    let unknownAuthor = LocalizationKey("ui.common.unknownAuthor")
    let yes = LocalizationKey("ui.common.yes")
}

struct LocalizationUIConflictKeys {
    let afterReviewingBothBackupsKeepContentCurrentlySavedWorkingFile = LocalizationKey("ui.conflict.afterReviewingBothBackupsKeepContentCurrentlySavedWorkingFile")
    let applyServerProperties = LocalizationKey("ui.conflict.applyServerProperties")
    let applyServerVersion = LocalizationKey("ui.conflict.applyServerVersion")
    let bothVersionsCopiedBackupFolderEditingCopiesDoesNotChange = LocalizationKey("ui.conflict.bothVersionsCopiedBackupFolderEditingCopiesDoesNotChange")
    let confirmCurrentLocalPropertiesResolvedValues = LocalizationKey("ui.conflict.confirmCurrentLocalPropertiesResolvedValues")
    let confirmCurrentWorkingCopyState = LocalizationKey("ui.conflict.confirmCurrentWorkingCopyState")
    let confirmManuallyEditedContent = LocalizationKey("ui.conflict.confirmManuallyEditedContent")
    let conflict = LocalizationKey("ui.conflict.conflict")
    let conflictedProperties = LocalizationKey("ui.conflict.conflictedProperties")
    let conflictedPropertyNameCouldNotDetermined = LocalizationKey("ui.conflict.conflictedPropertyNameCouldNotDetermined")
    let currentWorkingFile = LocalizationKey("ui.conflict.currentWorkingFile")
    let discardLocalChangeRestoreServerFile = LocalizationKey("ui.conflict.discardLocalChangeRestoreServerFile")
    let fileAlsoPropertyConflictChoosingVersionBelowResolvesPropertiesSame = LocalizationKey("ui.conflict.fileAlsoPropertyConflictChoosingVersionBelowResolvesPropertiesSame")
    let fileCannotCommittedUntilItMarkedResolved = LocalizationKey("ui.conflict.fileCannotCommittedUntilItMarkedResolved")
    let fileThatNotRepository = LocalizationKey("ui.conflict.fileThatNotRepository")
    let ifDeletedItLocallyDeletionRemainsCommitDeleteItServer = LocalizationKey("ui.conflict.ifDeletedItLocallyDeletionRemainsCommitDeleteItServer")
    let incomingServerPropertyValuesDiscardedWorkingCopy = LocalizationKey("ui.conflict.incomingServerPropertyValuesDiscardedWorkingCopy")
    let keepFileCurrentlySavedWorkingCopyMarkConflictResolvedFile = LocalizationKey("ui.conflict.keepFileCurrentlySavedWorkingCopyMarkConflictResolvedFile")
    let keepFileLaterCommitReplaceRepositoryFileContent = LocalizationKey("ui.conflict.keepFileLaterCommitReplaceRepositoryFileContent")
    let keepMyChange = LocalizationKey("ui.conflict.keepMyChange")
    let keepMyProperties = LocalizationKey("ui.conflict.keepMyProperties")
    let localPropertyValuesDiscarded = LocalizationKey("ui.conflict.localPropertyValuesDiscarded")
    let macosUnicodePathMatchedActualSvnManagedPath = LocalizationKey("ui.conflict.macosUnicodePathMatchedActualSvnManagedPath")
    let modificationDateUnavailable = LocalizationKey("ui.conflict.modificationDateUnavailable")
    let modified = LocalizationKey("ui.conflict.modified")
    let more = LocalizationKey("ui.conflict.more")
    let myFile = LocalizationKey("ui.conflict.myFile")
    let openBackupFolder = LocalizationKey("ui.conflict.openBackupFolder")
    let openMyFile = LocalizationKey("ui.conflict.openMyFile")
    let openResolutionAction = LocalizationKey("ui.conflict.openResolutionAction")
    let openServerFile = LocalizationKey("ui.conflict.openServerFile")
    let overwriteMyVersion = LocalizationKey("ui.conflict.overwriteMyVersion")
    let overwritingVersionRemovesIncomingServerChangesWorkingFileServerFile = LocalizationKey("ui.conflict.overwritingVersionRemovesIncomingServerChangesWorkingFileServerFile")
    let pathCannotCommittedUntilItsPropertyConflictResolved = LocalizationKey("ui.conflict.pathCannotCommittedUntilItsPropertyConflictResolved")
    let propertyConflict = LocalizationKey("ui.conflict.propertyConflict")
    let propertyConflictResolvedReviewPropertiesBeforeCommitting = LocalizationKey("ui.conflict.propertyConflictResolvedReviewPropertiesBeforeCommitting")
    let propertyValuesKeptWell = LocalizationKey("ui.conflict.propertyValuesKeptWell")
    let replaceLocalPropertiesServerValues = LocalizationKey("ui.conflict.replaceLocalPropertiesServerValues")
    let replaceServerFileLocalEditsLeaveWorkingCopyButRemain = LocalizationKey("ui.conflict.replaceServerFileLocalEditsLeaveWorkingCopyButRemain")
    let resolutionHeader = LocalizationKey("ui.conflict.resolutionHeader")
    let resolveConflictedFilesBeforeCommitting = LocalizationKey("ui.conflict.resolveConflictedFilesBeforeCommitting")
    let resolvedBackupsRemovedItemCreated = LocalizationKey("ui.conflict.resolvedBackupsRemovedItemCreated")
    let resolvedReviewFileBeforeCommitting = LocalizationKey("ui.conflict.resolvedReviewFileBeforeCommitting")
    let resolving = LocalizationKey("ui.conflict.resolving")
    let restoreFileServerVersion = LocalizationKey("ui.conflict.restoreFileServerVersion")
    let revertingRemovesItemsBelowWorkingFolderTheyCopiedBackupFolder = LocalizationKey("ui.conflict.revertingRemovesItemsBelowWorkingFolderTheyCopiedBackupFolder")
    let serverFile = LocalizationKey("ui.conflict.serverFile")
    let serverPropertyValuesAppliedWell = LocalizationKey("ui.conflict.serverPropertyValuesAppliedWell")
    let serverRevision = LocalizationKey("ui.conflict.serverRevision")
    let treeConflict = LocalizationKey("ui.conflict.treeConflict")
    let treeConflictConcernsPathStateNotFileContentsNotChoice = LocalizationKey("ui.conflict.treeConflictConcernsPathStateNotFileContentsNotChoice")
    let treeConflictLocalServerTarget = LocalizationKey("ui.conflict.treeConflictLocalServerTarget")
    let uncommittedChange = LocalizationKey("ui.conflict.uncommittedChange")
    let uncommittedLocalChangesDiscarded = LocalizationKey("ui.conflict.uncommittedLocalChangesDiscarded")
    let useMineAction = LocalizationKey("ui.conflict.useMineAction")
    let useMineConfirmationTitle = LocalizationKey("ui.conflict.useMineConfirmationTitle")
    let useServerAction = LocalizationKey("ui.conflict.useServerAction")
    let useServerConfirmationTitle = LocalizationKey("ui.conflict.useServerConfirmationTitle")
    let useWorkingFileAction = LocalizationKey("ui.conflict.useWorkingFileAction")
    let useWorkingFileConfirmationTitle = LocalizationKey("ui.conflict.useWorkingFileConfirmationTitle")
    let whenChooseVersionCurrentWorkingFilePreservedSeparatelyHiddenRecovery = LocalizationKey("ui.conflict.whenChooseVersionCurrentWorkingFilePreservedSeparatelyHiddenRecovery")
}

struct LocalizationUIDemoKeys {
    let browseSampleProject = LocalizationKey("ui.demo.browseSampleProject")
    let closeSampleProjectReturnNormalMode = LocalizationKey("ui.demo.closeSampleProjectReturnNormalMode")
    let exitDemo = LocalizationKey("ui.demo.exitDemo")
    let exploreMainFeaturesSampleDataNoServerConnectionAccount = LocalizationKey("ui.demo.exploreMainFeaturesSampleDataNoServerConnectionAccount")
}

struct LocalizationUIErrorKeys {
    let bundledSvnExecutableCouldNotFoundReinstallApp = LocalizationKey("ui.error.bundledSvnExecutableCouldNotFoundReinstallApp")
    let commitBasedOlderWorkingCopyStateRunUpdateResolveAny = LocalizationKey("ui.error.commitBasedOlderWorkingCopyStateRunUpdateResolveAny")
    let commitCompletedButWorkingCopyValidationFailedDoNotRetry = LocalizationKey("ui.error.commitCompletedButWorkingCopyValidationFailedDoNotRetry")
    let conflictBackupsMustStoredOutsideWorkingCopy = LocalizationKey("ui.error.conflictBackupsMustStoredOutsideWorkingCopy")
    let conflictFilePathPointsOutsideWorkingCopy = LocalizationKey("ui.error.conflictFilePathPointsOutsideWorkingCopy")
    let conflictRemainsAfterSvnCommandReviewBackupsTryAgain = LocalizationKey("ui.error.conflictRemainsAfterSvnCommandReviewBackupsTryAgain")
    let copied = LocalizationKey("ui.error.copied")
    let copyAllDisplayedErrorDetailsClipboard = LocalizationKey("ui.error.copyAllDisplayedErrorDetailsClipboard")
    let copyErrorDetails = LocalizationKey("ui.error.copyErrorDetails")
    let currentWorkingFileCouldNotFound = LocalizationKey("ui.error.currentWorkingFileCouldNotFound")
    let currentWorkingFileMustRegularFileNotSymbolicLink = LocalizationKey("ui.error.currentWorkingFileMustRegularFileNotSymbolicLink")
    let error = LocalizationKey("ui.error.error")
    let failed = LocalizationKey("ui.error.failed")
    let failedRemoveIncompleteConflictBackup = LocalizationKey("ui.error.failedRemoveIncompleteConflictBackup")
    let fileRemainsConflictGoChangesChooseResolveConflictsResolveIt = LocalizationKey("ui.error.fileRemainsConflictGoChangesChooseResolveConflictsResolveIt")
    let fileVersionCouldNotFound = LocalizationKey("ui.error.fileVersionCouldNotFound")
    let fileVersionMustRegularFileNotSymbolicLink = LocalizationKey("ui.error.fileVersionMustRegularFileNotSymbolicLink")
    let lockTokenDoesNotBelongCurrentWorkingCopyReviewOwner = LocalizationKey("ui.error.lockTokenDoesNotBelongCurrentWorkingCopyReviewOwner")
    let recoveryBackupCurrentWorkingFileCouldNotVerified = LocalizationKey("ui.error.recoveryBackupCurrentWorkingFileCouldNotVerified")
    let recoveryDestinationFolderMustEmpty = LocalizationKey("ui.error.recoveryDestinationFolderMustEmpty")
    let selectedFolderNotSvnLocalWorkingFolder = LocalizationKey("ui.error.selectedFolderNotSvnLocalWorkingFolder")
    let selectedVersionFileCouldNotRestoredWorkingFile = LocalizationKey("ui.error.selectedVersionFileCouldNotRestoredWorkingFile")
    let serverFileVersionCouldNotFound = LocalizationKey("ui.error.serverFileVersionCouldNotFound")
    let serverFileVersionMustRegularFileNotSymbolicLink = LocalizationKey("ui.error.serverFileVersionMustRegularFileNotSymbolicLink")
    let svnResponseCouldNotRead = LocalizationKey("ui.error.svnResponseCouldNotRead")
    let unableLoadChanges = LocalizationKey("ui.error.unableLoadChanges")
    let unableOpenFile = LocalizationKey("ui.error.unableOpenFile")
    let unknownError = LocalizationKey("ui.error.unknownError")
    let unsupportedConflictType = LocalizationKey("ui.error.unsupportedConflictType")
    let workingCopyOperationInterruptedRunWorkingCopyCleanupTryOperation = LocalizationKey("ui.error.workingCopyOperationInterruptedRunWorkingCopyCleanupTryOperation")
}

struct LocalizationUIFileKeys {
    let copiedFilePath = LocalizationKey("ui.file.copiedFilePath")
    let noLongerMarkedDeleted = LocalizationKey("ui.file.noLongerMarkedDeleted")
    let restoredButFailed = LocalizationKey("ui.file.restoredButFailed")
    let restoredSelectedDeletionFileServer = LocalizationKey("ui.file.restoredSelectedDeletionFileServer")
    let revertedLocalChanges = LocalizationKey("ui.file.revertedLocalChanges")
}

struct LocalizationUIHistoryKeys {
    let additionalRevisionProperties = LocalizationKey("ui.history.additionalRevisionProperties")
    let blueDotsServerCommitsGreenRingHighestLocalRevisionOrange = LocalizationKey("ui.history.blueDotsServerCommitsGreenRingHighestLocalRevisionOrange")
    let blueDotsServerCommitsGreenRingLocalBaseOrangeBranch = LocalizationKey("ui.history.blueDotsServerCommitsGreenRingLocalBaseOrangeBranch")
    let changedPaths = LocalizationKey("ui.history.changedPaths")
    let commitHistory = LocalizationKey("ui.history.commitHistory")
    let commitTimeUnavailable = LocalizationKey("ui.history.commitTimeUnavailable")
    let contentChanged = LocalizationKey("ui.history.contentChanged")
    let copyHistory = LocalizationKey("ui.history.copyHistory")
    let earlierHistory = LocalizationKey("ui.history.earlierHistory")
    let fileCommitHistory = LocalizationKey("ui.history.fileCommitHistory")
    let highestLocalRevision = LocalizationKey("ui.history.highestLocalRevision")
    let includedLocally = LocalizationKey("ui.history.includedLocally")
    let load50More = LocalizationKey("ui.history.load50More")
    let loading = LocalizationKey("ui.history.loading")
    let loadingCommitHistory = LocalizationKey("ui.history.loadingCommitHistory")
    let localBaseRevision = LocalizationKey("ui.history.localBaseRevision")
    let localBaseRevisionEarlierThanLatest50ServerRecords = LocalizationKey("ui.history.localBaseRevisionEarlierThanLatest50ServerRecords")
    let localChanges = LocalizationKey("ui.history.localChanges")
    let localUpdateBaseFallsBetweenTwoServerCommits = LocalizationKey("ui.history.localUpdateBaseFallsBetweenTwoServerCommits")
    let mixedRevisions = LocalizationKey("ui.history.mixedRevisions")
    let myLocalBase = LocalizationKey("ui.history.myLocalBase")
    let myLocalFolderR = LocalizationKey("ui.history.myLocalFolderR")
    let noCommitHistory = LocalizationKey("ui.history.noCommitHistory")
    let noValue = LocalizationKey("ui.history.noValue")
    let originalMessage = LocalizationKey("ui.history.originalMessage")
    let propertiesChanged = LocalizationKey("ui.history.propertiesChanged")
    let refreshed = LocalizationKey("ui.history.refreshed")
    let reloadLocalChangesLatestServerCommitHistory = LocalizationKey("ui.history.reloadLocalChangesLatestServerCommitHistory")
    let renameHistory = LocalizationKey("ui.history.renameHistory")
    let restored = LocalizationKey("ui.history.restored")
    let serverCommitDetail = LocalizationKey("ui.history.serverCommitDetail")
    let serverCommitLegend = LocalizationKey("ui.history.serverCommitLegend")
    let serverLatest = LocalizationKey("ui.history.serverLatest")
    let serverLatestR = LocalizationKey("ui.history.serverLatestR")
    let uncommittedChanges = LocalizationKey("ui.history.uncommittedChanges")
    let uncommittedChangesBranchLocalBaseRevision = LocalizationKey("ui.history.uncommittedChangesBranchLocalBaseRevision")
    let upDate = LocalizationKey("ui.history.upDate")
    let viewChangesCommit = LocalizationKey("ui.history.viewChangesCommit")
    let viewOriginalMessageBeforeRestoration = LocalizationKey("ui.history.viewOriginalMessageBeforeRestoration")
    let workingCopyContainsMixedRevisionsRMarkerShowsHighestRevision = LocalizationKey("ui.history.workingCopyContainsMixedRevisionsRMarkerShowsHighestRevision")
}

struct LocalizationUIIgnoreKeys {
    let addRule = LocalizationKey("ui.ignore.addRule")
    let addedIgnoreRuleCommitDirectoryPropertyShareItTeam = LocalizationKey("ui.ignore.addedIgnoreRuleCommitDirectoryPropertyShareItTeam")
    let addingRule = LocalizationKey("ui.ignore.addingRule")
    let alreadyVersionedFilesNotHiddenIgnoreRules = LocalizationKey("ui.ignore.alreadyVersionedFilesNotHiddenIgnoreRules")
    let applied = LocalizationKey("ui.ignore.applied")
    let appliedGitRuleSvnIgnorePropertiesCommitPropertyChangesShare = LocalizationKey("ui.ignore.appliedGitRuleSvnIgnorePropertiesCommitPropertyChangesShare")
    let apply = LocalizationKey("ui.ignore.apply")
    let applyGlobalIgnoreRules = LocalizationKey("ui.ignore.applyGlobalIgnoreRules")
    let applySelectedRules = LocalizationKey("ui.ignore.applySelectedRules")
    let applying = LocalizationKey("ui.ignore.applying")
    let available = LocalizationKey("ui.ignore.available")
    let clear = LocalizationKey("ui.ignore.clear")
    let compareGitRules = LocalizationKey("ui.ignore.compareGitRules")
    let directory = LocalizationKey("ui.ignore.directory")
    let duplicateRule = LocalizationKey("ui.ignore.duplicateRule")
    let enterPattern = LocalizationKey("ui.ignore.enterPattern")
    let fileExtension = LocalizationKey("ui.ignore.fileExtension")
    let gitignoreNotModifiedImportOneWaySvnPropertyChangesMust = LocalizationKey("ui.ignore.gitignoreNotModifiedImportOneWaySvnPropertyChangesMust")
    let globalRulesCanAffectManyDirectoriesBelowWorkingCopyApply = LocalizationKey("ui.ignore.globalRulesCanAffectManyDirectoriesBelowWorkingCopyApply")
    let importGitRules = LocalizationKey("ui.ignore.importGitRules")
    let inherited = LocalizationKey("ui.ignore.inherited")
    let inheritedRulesCanOnlyRemovedParentDirectoryThatOwnsProperty = LocalizationKey("ui.ignore.inheritedRulesCanOnlyRemovedParentDirectoryThatOwnsProperty")
    let item = LocalizationKey("ui.ignore.item")
    let lastCompared = LocalizationKey("ui.ignore.lastCompared")
    let manageIgnoreRules = LocalizationKey("ui.ignore.manageIgnoreRules")
    let noGitignore = LocalizationKey("ui.ignore.noGitignore")
    let noGitignoreFileFoundWorkingCopy = LocalizationKey("ui.ignore.noGitignoreFileFoundWorkingCopy")
    let noSvnIgnoreRulesConfigured = LocalizationKey("ui.ignore.noSvnIgnoreRulesConfigured")
    let pattern = LocalizationKey("ui.ignore.pattern")
    let patternMustNotContainSlashOrLineBreak = LocalizationKey("ui.ignore.patternMustNotContainSlashOrLineBreak")
    let propertyKind = LocalizationKey("ui.ignore.propertyKind")
    let removeInheritedRulesParentDirectoryThatOwnsProperty = LocalizationKey("ui.ignore.removeInheritedRulesParentDirectoryThatOwnsProperty")
    let removeRule = LocalizationKey("ui.ignore.removeRule")
    let removedIgnoreRule = LocalizationKey("ui.ignore.removedIgnoreRule")
    let resolveUnicodePathConflictsBeforeComparingGitRulesSoProperty = LocalizationKey("ui.ignore.resolveUnicodePathConflictsBeforeComparingGitRulesSoProperty")
    let review = LocalizationKey("ui.ignore.review")
    let selectAll = LocalizationKey("ui.ignore.selectAll")
    let svnIgnoreRules = LocalizationKey("ui.ignore.svnIgnoreRules")
    let thereNoGitRulesImport = LocalizationKey("ui.ignore.thereNoGitRulesImport")
    let unsupported = LocalizationKey("ui.ignore.unsupported")
}

struct LocalizationUILockKeys {
    let alreadyHoldLocksAllSelectedFiles = LocalizationKey("ui.lock.alreadyHoldLocksAllSelectedFiles")
    let changedRequiredLockPropertyFileCommitItApplyChangeOther = LocalizationKey("ui.lock.changedRequiredLockPropertyFileCommitItApplyChangeOther")
    let countAccessibilityLabel = LocalizationKey("ui.lock.countAccessibilityLabel")
    let currentSvnClientDoesNotSupportForcedMultiFileLocking = LocalizationKey("ui.lock.currentSvnClientDoesNotSupportForcedMultiFileLocking")
    let editingDocumentSvnKr = LocalizationKey("ui.lock.editingDocumentSvnKr")
    let file = LocalizationKey("ui.lock.file")
    let fileBeforeOpening = LocalizationKey("ui.lock.fileBeforeOpening")
    let fileCurrentlyLockedOpeningWithoutLockMayPreventCommittingCause = LocalizationKey("ui.lock.fileCurrentlyLockedOpeningWithoutLockMayPreventCommittingCause")
    let fileLockedSuccessfulCommitAutomaticallyReleasesLock = LocalizationKey("ui.lock.fileLockedSuccessfulCommitAutomaticallyReleasesLock")
    let forceLock = LocalizationKey("ui.lock.forceLock")
    let forceLockingSelectedFileRemovesExistingUsersLocksReviewOwners = LocalizationKey("ui.lock.forceLockingSelectedFileRemovesExistingUsersLocksReviewOwners")
    let forceReleaseLock = LocalizationKey("ui.lock.forceReleaseLock")
    let forceReleaseRepositoryLock = LocalizationKey("ui.lock.forceReleaseRepositoryLock")
    let forceReleasingCanInterruptSomeoneElseWorkPathOwnerLocked = LocalizationKey("ui.lock.forceReleasingCanInterruptSomeoneElseWorkPathOwnerLocked")
    let forceUnlockAccessForbidden = LocalizationKey("ui.lock.forceUnlockAccessForbidden")
    let forceUnlockAuthenticationRequiredOrFailed = LocalizationKey("ui.lock.forceUnlockAuthenticationRequiredOrFailed")
    let forceUnlockFailureCode = LocalizationKey("ui.lock.forceUnlockFailureCode")
    let forceUnlockOwnerOnlyHook = LocalizationKey("ui.lock.forceUnlockOwnerOnlyHook")
    let informationCouldNotCheckedCanOpenFileWithoutLockingIt = LocalizationKey("ui.lock.informationCouldNotCheckedCanOpenFileWithoutLockingIt")
    let loadingRepositoryLocks = LocalizationKey("ui.lock.loadingRepositoryLocks")
    let lockAndOpenAction = LocalizationKey("ui.lock.lockAndOpenAction")
    let lockedByCurrentUser = LocalizationKey("ui.lock.lockedByCurrentUser")
    let lockedByOwner = LocalizationKey("ui.lock.lockedByOwner")
    let lockedFile = LocalizationKey("ui.lock.lockedFile")
    let lockedFileMarkedSvnServerPreventAnotherUserCommittingIt = LocalizationKey("ui.lock.lockedFileMarkedSvnServerPreventAnotherUserCommittingIt")
    let lockingPreventsConcurrentCommitsOtherUsersReducesDocumentConflictsSuccessful = LocalizationKey("ui.lock.lockingPreventsConcurrentCommitsOtherUsersReducesDocumentConflictsSuccessful")
    let noLockedFiles = LocalizationKey("ui.lock.noLockedFiles")
    let notAvailable = LocalizationKey("ui.lock.notAvailable")
    let openWithoutLock = LocalizationKey("ui.lock.openWithoutLock")
    let openWithoutLockingDonTAskAgain = LocalizationKey("ui.lock.openWithoutLockingDonTAskAgain")
    let openedWithoutLockConcurrentCommitAnotherUserMayCauseConflict = LocalizationKey("ui.lock.openedWithoutLockConcurrentCommitAnotherUserMayCauseConflict")
    let openingFileLocked = LocalizationKey("ui.lock.openingFileLocked")
    let releaseAllAction = LocalizationKey("ui.lock.releaseAllAction")
    let releaseAllConfirmationTitle = LocalizationKey("ui.lock.releaseAllConfirmationTitle")
    let releaseFromBrowserAction = LocalizationKey("ui.lock.releaseFromBrowserAction")
    let releaseFromListAction = LocalizationKey("ui.lock.releaseFromListAction")
    let releaseLocks = LocalizationKey("ui.lock.releaseLocks")
    let releaseLocksOwnedCurrentUserOtherUsersAbleModifyFiles = LocalizationKey("ui.lock.releaseLocksOwnedCurrentUserOtherUsersAbleModifyFiles")
    let releaseMyLock = LocalizationKey("ui.lock.releaseMyLock")
    let released = LocalizationKey("ui.lock.released")
    let releasedAllLocks = LocalizationKey("ui.lock.releasedAllLocks")
    let releasedLocksLocksBelowCouldNotReleased = LocalizationKey("ui.lock.releasedLocksLocksBelowCouldNotReleased")
    let removeRequiredLock = LocalizationKey("ui.lock.removeRequiredLock")
    let repositoryLockForceReleased = LocalizationKey("ui.lock.repositoryLockForceReleased")
    let repositoryLocks = LocalizationKey("ui.lock.repositoryLocks")
    let requireLockBeforeEditing = LocalizationKey("ui.lock.requireLockBeforeEditing")
    let requiredBeforeEditing = LocalizationKey("ui.lock.requiredBeforeEditing")
    let reviewForceLock = LocalizationKey("ui.lock.reviewForceLock")
    let selectedFile = LocalizationKey("ui.lock.selectedFile")
    let sheetTitle = LocalizationKey("ui.lock.sheetTitle")
    let someLocksNotReleased = LocalizationKey("ui.lock.someLocksNotReleased")
    let takeAnotherUserLock = LocalizationKey("ui.lock.takeAnotherUserLock")
    let tryNormalUnlockFirstIfWorkingCopyNoMatchingLock = LocalizationKey("ui.lock.tryNormalUnlockFirstIfWorkingCopyNoMatchingLock")
    let viewLockedFilesTheirCountRepository = LocalizationKey("ui.lock.viewLockedFilesTheirCountRepository")
}

struct LocalizationUIRecoveryKeys {
    let allContentsVerifiedInterruptedSvnWorkingCopyFolderBelowDeleted = LocalizationKey("ui.recovery.allContentsVerifiedInterruptedSvnWorkingCopyFolderBelowDeleted")
    let automaticUnicodePathRecovery = LocalizationKey("ui.recovery.automaticUnicodePathRecovery")
    let checkoutCanceledPartiallyDownloadedFilesMayRemain = LocalizationKey("ui.recovery.checkoutCanceledPartiallyDownloadedFilesMayRemain")
    let checkoutInterrupted = LocalizationKey("ui.recovery.checkoutInterrupted")
    let chooseAction = LocalizationKey("ui.recovery.chooseAction")
    let chooseEmptyFolder = LocalizationKey("ui.recovery.chooseEmptyFolder")
    let chooseEmptyRecoveryFolder = LocalizationKey("ui.recovery.chooseEmptyRecoveryFolder")
    let chooseFolder = LocalizationKey("ui.recovery.chooseFolder")
    let cleanWorkingCopyCheckedOutServerOnlyRealLocalChanges = LocalizationKey("ui.recovery.cleanWorkingCopyCheckedOutServerOnlyRealLocalChanges")
    let cleaningContinuing = LocalizationKey("ui.recovery.cleaningContinuing")
    let continueCheckout = LocalizationKey("ui.recovery.continueCheckout")
    let emptiedInterruptedCheckoutFolder = LocalizationKey("ui.recovery.emptiedInterruptedCheckoutFolder")
    let emptyFolderConfirmationAction = LocalizationKey("ui.recovery.emptyFolderConfirmationAction")
    let emptyFolderRequestAction = LocalizationKey("ui.recovery.emptyFolderRequestAction")
    let emptyInterruptedCheckoutFolder = LocalizationKey("ui.recovery.emptyInterruptedCheckoutFolder")
    let falseAliasesExcluded = LocalizationKey("ui.recovery.falseAliasesExcluded")
    let folderAlreadyFilesBeforeCheckoutSoAppNotEmptyIt = LocalizationKey("ui.recovery.folderAlreadyFilesBeforeCheckoutSoAppNotEmptyIt")
    let folderIncompleteSvnWorkingCopyContinueRegisteringItCleaningIt = LocalizationKey("ui.recovery.folderIncompleteSvnWorkingCopyContinueRegisteringItCleaningIt")
    let folderNotEmptiedBecauseItCouldNotVerifiedSafelyInterrupted = LocalizationKey("ui.recovery.folderNotEmptiedBecauseItCouldNotVerifiedSafelyInterrupted")
    let interruptedCheckoutFolderNoLongerValidSvnWorkingCopySo = LocalizationKey("ui.recovery.interruptedCheckoutFolderNoLongerValidSvnWorkingCopySo")
    let localWorkingFolderAlreadyRegistered = LocalizationKey("ui.recovery.localWorkingFolderAlreadyRegistered")
    let locallyMissing = LocalizationKey("ui.recovery.locallyMissing")
    let locallyMissingActionRequired = LocalizationKey("ui.recovery.locallyMissingActionRequired")
    let new = LocalizationKey("ui.recovery.new")
    let newWorkingFolder = LocalizationKey("ui.recovery.newWorkingFolder")
    let newWorkingFolderRecoveryAction = LocalizationKey("ui.recovery.newWorkingFolderRecoveryAction")
    let newWorkingFolderRecoveryHelp = LocalizationKey("ui.recovery.newWorkingFolderRecoveryHelp")
    let pathRecoveryCompletedOriginalWorkingFolderPreserved = LocalizationKey("ui.recovery.pathRecoveryCompletedOriginalWorkingFolderPreserved")
    let preparingNewWorkingFolderRecovery = LocalizationKey("ui.recovery.preparingNewWorkingFolderRecovery")
    let preview = LocalizationKey("ui.recovery.preview")
    let recoverNewWorkingFolder = LocalizationKey("ui.recovery.recoverNewWorkingFolder")
    let recoveryFolderMustBeOutsideCurrentWorkingFolder = LocalizationKey("ui.recovery.recoveryFolderMustBeOutsideCurrentWorkingFolder")
    let successBothOriginalRecoveredCopiesRemainSidebar = LocalizationKey("ui.recovery.successBothOriginalRecoveredCopiesRemainSidebar")
}

struct LocalizationUIRepositoryKeys {
    let addLocalWorkingFolder = LocalizationKey("ui.repository.addLocalWorkingFolder")
    let addSvnRepository = LocalizationKey("ui.repository.addSvnRepository")
    let cancelAddingRepositoryCloseWindow = LocalizationKey("ui.repository.cancelAddingRepositoryCloseWindow")
    let change = LocalizationKey("ui.repository.change")
    let changeRepositoryLocation = LocalizationKey("ui.repository.changeRepositoryLocation")
    let chooseSvnLocalWorkingFolders = LocalizationKey("ui.repository.chooseSvnLocalWorkingFolders")
    let commitChangeApplyItServer = LocalizationKey("ui.repository.commitChangeApplyItServer")
    let copyCurrentRepositoryUrl = LocalizationKey("ui.repository.copyCurrentRepositoryUrl")
    let currentRepositoryUrl = LocalizationKey("ui.repository.currentRepositoryUrl")
    let currentUrlNewUrlOnlyWorkingCopyRepositoryConnectionChanges = LocalizationKey("ui.repository.currentUrlNewUrlOnlyWorkingCopyRepositoryConnectionChanges")
    let destinationNameAlreadyExists = LocalizationKey("ui.repository.destinationNameAlreadyExists")
    let enterValidFileNameWithoutFolderPath = LocalizationKey("ui.repository.enterValidFileNameWithoutFolderPath")
    let enterValidRepositoryUrlIncludingItsScheme = LocalizationKey("ui.repository.enterValidRepositoryUrlIncludingItsScheme")
    let filePanelPrompt = LocalizationKey("ui.repository.filePanelPrompt")
    let localFolder = LocalizationKey("ui.repository.localFolder")
    let localFolderPickerAction = LocalizationKey("ui.repository.localFolderPickerAction")
    let localWorkingFolders = LocalizationKey("ui.repository.localWorkingFolders")
    let mayMovedRelocateNewUrlRestoreRemoteOperations = LocalizationKey("ui.repository.mayMovedRelocateNewUrlRestoreRemoteOperations")
    let newFileName = LocalizationKey("ui.repository.newFileName")
    let newFileNameMatchesCurrentName = LocalizationKey("ui.repository.newFileNameMatchesCurrentName")
    let newFolderAppliedWhenSave = LocalizationKey("ui.repository.newFolderAppliedWhenSave")
    let newRepositoryUrl = LocalizationKey("ui.repository.newRepositoryUrl")
    let newRepositoryUrlMatchesCurrentUrl = LocalizationKey("ui.repository.newRepositoryUrlMatchesCurrentUrl")
    let notSvnVersionedFile = LocalizationKey("ui.repository.notSvnVersionedFile")
    let onlyRegularFilesCanRenamedCopiedAssignedRequiredLockProperty = LocalizationKey("ui.repository.onlyRegularFilesCanRenamedCopiedAssignedRequiredLockProperty")
    let openFinder = LocalizationKey("ui.repository.openFinder")
    let openRepositoryRelocation = LocalizationKey("ui.repository.openRepositoryRelocation")
    let openSvnLocalWorkingFolderFinder = LocalizationKey("ui.repository.openSvnLocalWorkingFolderFinder")
    let pickNewLocationSvnWorkingFolder = LocalizationKey("ui.repository.pickNewLocationSvnWorkingFolder")
    let pressOUseButtonBottomLeft = LocalizationKey("ui.repository.pressOUseButtonBottomLeft")
    let registerExistingLocalFolder = LocalizationKey("ui.repository.registerExistingLocalFolder")
    let registerExistingSvnWorkingFolderApp = LocalizationKey("ui.repository.registerExistingSvnWorkingFolderApp")
    let relocateAction = LocalizationKey("ui.repository.relocateAction")
    let relocatedRepositoryConnectionLocalChangesPreserved = LocalizationKey("ui.repository.relocatedRepositoryConnectionLocalChangesPreserved")
    let relocatingRepository = LocalizationKey("ui.repository.relocatingRepository")
    let relocationConfirmationTitle = LocalizationKey("ui.repository.relocationConfirmationTitle")
    let relocationFailedCheckCurrentUrlRelocateCorrectNewUrlIf = LocalizationKey("ui.repository.relocationFailedCheckCurrentUrlRelocateCorrectNewUrlIf")
    let relocationPreservesAllUncommittedLocalChanges = LocalizationKey("ui.repository.relocationPreservesAllUncommittedLocalChanges")
    let removeApp = LocalizationKey("ui.repository.removeApp")
    let removeSelectedWorkingFolderAppLocalFilesNotDeleted = LocalizationKey("ui.repository.removeSelectedWorkingFolderAppLocalFilesNotDeleted")
    let reviewRelocation = LocalizationKey("ui.repository.reviewRelocation")
    let workingFolderChanged = LocalizationKey("ui.repository.workingFolderChanged")
    let workingFolderNoLongerExistsRestoreFolderRemoveItList = LocalizationKey("ui.repository.workingFolderNoLongerExistsRestoreFolderRemoveItList")
}

struct LocalizationUIRevisionKeys {
    let chooseChangedFileAboveDisplayOnlyThatFileDiff = LocalizationKey("ui.revision.chooseChangedFileAboveDisplayOnlyThatFileDiff")
    let chooseViewChangesHistoryDisplayActualDiff = LocalizationKey("ui.revision.chooseViewChangesHistoryDisplayActualDiff")
    let commitChanges = LocalizationKey("ui.revision.commitChanges")
    let commitNotFound = LocalizationKey("ui.revision.commitNotFound")
    let currentContentsDiscardedReplacedRRecoveryCopySavedFirstResult = LocalizationKey("ui.revision.currentContentsDiscardedReplacedRRecoveryCopySavedFirstResult")
    let currentWorkingFileCouldNotVerifiedRecoveryCopySoIt = LocalizationKey("ui.revision.currentWorkingFileCouldNotVerifiedRecoveryCopySoIt")
    let fileCommitHistory = LocalizationKey("ui.revision.fileCommitHistory")
    let filePathPointsOutsideLocalWorkingFolder = LocalizationKey("ui.revision.filePathPointsOutsideLocalWorkingFolder")
    let folderForRestoredFileNotDirectory = LocalizationKey("ui.revision.folderForRestoredFileNotDirectory")
    let loadingChanges = LocalizationKey("ui.revision.loadingChanges")
    let loadingFileHistory = LocalizationKey("ui.revision.loadingFileHistory")
    let noChangedFiles = LocalizationKey("ui.revision.noChangedFiles")
    let noFileHistory = LocalizationKey("ui.revision.noFileHistory")
    let projectSvnClientDoesNotSupportReadingHistoricalFileRevisions = LocalizationKey("ui.revision.projectSvnClientDoesNotSupportReadingHistoricalFileRevisions")
    let recoveryCopiesMustStoredOutsideLocalWorkingFolder = LocalizationKey("ui.revision.recoveryCopiesMustStoredOutsideLocalWorkingFolder")
    let restoreWorkingFile = LocalizationKey("ui.revision.restoreWorkingFile")
    let restoreWorkingFileRevision = LocalizationKey("ui.revision.restoreWorkingFileRevision")
    let restoredFileDidNotMatchSelectedRevisionByteByteRecovery = LocalizationKey("ui.revision.restoredFileDidNotMatchSelectedRevisionByteByteRecovery")
    let restoredRNowLocalChangeCommitItUpdateServer = LocalizationKey("ui.revision.restoredRNowLocalChangeCommitItUpdateServer")
    let restoringRevision = LocalizationKey("ui.revision.restoringRevision")
    let saveRevision = LocalizationKey("ui.revision.saveRevision")
    let savedR = LocalizationKey("ui.revision.savedR")
    let savingRevision = LocalizationKey("ui.revision.savingRevision")
    let searchAuthorFileMessageRevision = LocalizationKey("ui.revision.searchAuthorFileMessageRevision")
    let selectCommit = LocalizationKey("ui.revision.selectCommit")
    let selectFile = LocalizationKey("ui.revision.selectFile")
    let selectedSaveLocationNotSafeRegularFileDestination = LocalizationKey("ui.revision.selectedSaveLocationNotSafeRegularFileDestination")
    let workingFileMustRegularFileNotSymbolicLink = LocalizationKey("ui.revision.workingFileMustRegularFileNotSymbolicLink")
}

struct LocalizationUISettingsKeys {
    let alwaysLockOpenWithoutAsking = LocalizationKey("ui.settings.alwaysLockOpenWithoutAsking")
    let alwaysOpenWithoutLockingAsking = LocalizationKey("ui.settings.alwaysOpenWithoutLockingAsking")
    let askEveryTime = LocalizationKey("ui.settings.askEveryTime")
    let chooseLanguageUsedAppInterface = LocalizationKey("ui.settings.chooseLanguageUsedAppInterface")
    let chooseTimeZoneUsedCommitDatesTimes = LocalizationKey("ui.settings.chooseTimeZoneUsedCommitDatesTimes")
    let commitDisplayTimeZone = LocalizationKey("ui.settings.commitDisplayTimeZone")
    let coordinatedUniversalTimeUtc = LocalizationKey("ui.settings.coordinatedUniversalTimeUtc")
    let defaultKoreaStandardTimeKstDoesNotChangeOriginalCommit = LocalizationKey("ui.settings.defaultKoreaStandardTimeKstDoesNotChangeOriginalCommit")
    let folderSettings = LocalizationKey("ui.settings.folderSettings")
    let hideMacOfficeTemporaryFiles = LocalizationKey("ui.settings.hideMacOfficeTemporaryFiles")
    let hideTemporaryFilesChangesPreventThemCommittedVersionedFilesRemain = LocalizationKey("ui.settings.hideTemporaryFilesChangesPreventThemCommittedVersionedFilesRemain")
    let japanStandardTime = LocalizationKey("ui.settings.japanStandardTime")
    let koreaStandardTime = LocalizationKey("ui.settings.koreaStandardTime")
    let language = LocalizationKey("ui.settings.language")
    let macSystemTimeZone = LocalizationKey("ui.settings.macSystemTimeZone")
    let openAppWideSettingsWindow = LocalizationKey("ui.settings.openAppWideSettingsWindow")
    let otherUsersCannotModifyLockedFileUntilCommitItRelease = LocalizationKey("ui.settings.otherUsersCannotModifyLockedFileUntilCommitItRelease")
    let settings = LocalizationKey("ui.settings.settings")
    let ukTime = LocalizationKey("ui.settings.ukTime")
    let usEasternTime = LocalizationKey("ui.settings.usEasternTime")
    let usPacificTime = LocalizationKey("ui.settings.usPacificTime")
    let whenOpeningDocuments = LocalizationKey("ui.settings.whenOpeningDocuments")
}

struct LocalizationUIStatusKeys {
    let added = LocalizationKey("ui.status.added")
    let deleted = LocalizationKey("ui.status.deleted")
    let diskContainingFolderStoresKoreanFilenamesOnlyDecomposedFormFilenames = LocalizationKey("ui.status.diskContainingFolderStoresKoreanFilenamesOnlyDecomposedFormFilenames")
    let filenameWarning = LocalizationKey("ui.status.filenameWarning")
    let ignored = LocalizationKey("ui.status.ignored")
    let lockedFiles = LocalizationKey("ui.status.lockedFiles")
    let modified = LocalizationKey("ui.status.modified")
    let replaced = LocalizationKey("ui.status.replaced")
    let unversioned = LocalizationKey("ui.status.unversioned")
}

struct LocalizationUIUpdateKeys {
    let addRepositoryTemporaryFileCleanupCommitAfterUpdating = LocalizationKey("ui.update.addRepositoryTemporaryFileCleanupCommitAfterUpdating")
    let afterUpdateCandidateContentsVerifiedReviewFinalListBeforeAny = LocalizationKey("ui.update.afterUpdateCandidateContentsVerifiedReviewFinalListBeforeAny")
    let beforeRetryingCommit = LocalizationKey("ui.update.beforeRetryingCommit")
    let checkAppStoreLatestVersion = LocalizationKey("ui.update.checkAppStoreLatestVersion")
    let checkFromAppMenu = LocalizationKey("ui.update.checkFromAppMenu")
    let checkNow = LocalizationKey("ui.update.checkNow")
    let checkingIncomingChanges = LocalizationKey("ui.update.checkingIncomingChanges")
    let checkingUpdates = LocalizationKey("ui.update.checkingUpdates")
    let checkoutUpdateInterruptedDoNotRevertLocalChangesContinueUpdating = LocalizationKey("ui.update.checkoutUpdateInterruptedDoNotRevertLocalChangesContinueUpdating")
    let cleanedRepositoryTemporaryFile = LocalizationKey("ui.update.cleanedRepositoryTemporaryFile")
    let commitMessageSelectedItemSavedIfUpdateCreatesNoConflicts = LocalizationKey("ui.update.commitMessageSelectedItemSavedIfUpdateCreatesNoConflicts")
    let completeUpdatePreviewCouldNotLoadedCanStillTryUpdate = LocalizationKey("ui.update.completeUpdatePreviewCouldNotLoadedCanStillTryUpdate")
    let continueUpdating = LocalizationKey("ui.update.continueUpdating")
    let createdConflictsSoCommitNotRetried = LocalizationKey("ui.update.createdConflictsSoCommitNotRetried")
    let createdConflictsSoCommitNotRetriedResolvePathsFirst = LocalizationKey("ui.update.createdConflictsSoCommitNotRetriedResolvePathsFirst")
    let downloadLatestServerChangesCurrentLocalWorkingFolder = LocalizationKey("ui.update.downloadLatestServerChangesCurrentLocalWorkingFolder")
    let goConflictResolution = LocalizationKey("ui.update.goConflictResolution")
    let incomingChangesThatOverlapLocalEditsMayCreateSvnConflict = LocalizationKey("ui.update.incomingChangesThatOverlapLocalEditsMayCreateSvnConflict")
    let incomplete = LocalizationKey("ui.update.incomplete")
    let later = LocalizationKey("ui.update.later")
    let localFileBlockingUpdate = LocalizationKey("ui.update.localFileBlockingUpdate")
    let lockedRepository = LocalizationKey("ui.update.lockedRepository")
    let newVersionDialogTitle = LocalizationKey("ui.update.newVersionDialogTitle")
    let noIncomingChanges = LocalizationKey("ui.update.noIncomingChanges")
    let preview = LocalizationKey("ui.update.preview")
    let previewAvailableStatus = LocalizationKey("ui.update.previewAvailableStatus")
    let reUsingLatestVersion = LocalizationKey("ui.update.reUsingLatestVersion")
    let requiredBeforeCommit = LocalizationKey("ui.update.requiredBeforeCommit")
    let retryCommit = LocalizationKey("ui.update.retryCommit")
    let runUpdate = LocalizationKey("ui.update.runUpdate")
    let serverChangesInsidePendingDeletionMayNotAppearListRun = LocalizationKey("ui.update.serverChangesInsidePendingDeletionMayNotAppearListRun")
    let showingFirstCommits = LocalizationKey("ui.update.showingFirstCommits")
    let sidebarAvailableBadge = LocalizationKey("ui.update.sidebarAvailableBadge")
    let someSavedCommitSelectionsDisappearedChangeListAfterUpdateReview = LocalizationKey("ui.update.someSavedCommitSelectionsDisappearedChangeListAfterUpdateReview")
    let someTemporaryFilesNotCleaned = LocalizationKey("ui.update.someTemporaryFilesNotCleaned")
    let succeededButCleanupCommitFailedScheduledDeletionsRestored = LocalizationKey("ui.update.succeededButCleanupCommitFailedScheduledDeletionsRestored")
    let succeededButCleanupCouldNotStart = LocalizationKey("ui.update.succeededButCleanupCouldNotStart")
    let svnRequiresWorkingCopyUpdateConfirmUpdateRetryCommitSaved = LocalizationKey("ui.update.svnRequiresWorkingCopyUpdateConfirmUpdateRetryCommitSaved")
    let unableCheckAppStoreUpdates = LocalizationKey("ui.update.unableCheckAppStoreUpdates")
    let update = LocalizationKey("ui.update.update")
    let updating = LocalizationKey("ui.update.updating")
    let versionAvailable = LocalizationKey("ui.update.versionAvailable")
    let viewAppStore = LocalizationKey("ui.update.viewAppStore")
    let workingCopyUpDateServer = LocalizationKey("ui.update.workingCopyUpDateServer")
}
