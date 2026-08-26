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

    static let allCases: [LocalizationKey] = """
        error.deletion.chooseMissingItems
        error.deletion.partial
        error.deletion.unresolvedMissingPaths
        error.deletion.validation
        error.path.aliasRepair
        error.path.normalizationCollision
        error.path.unsupportedTarget
        error.recovery.blocked
        error.recovery.fileReplacement
        error.recovery.validation
        history.copy.copiedFrom
        recovery.path.reviewPaths
        repository.pathNormalization.action
        repository.pathNormalization.actionHelp
        repository.pathNormalization.after
        repository.pathNormalization.before
        repository.pathNormalization.codepointsDetail
        repository.pathNormalization.confirmationCommits
        repository.pathNormalization.confirmationDeleteAdd
        repository.pathNormalization.confirmationDirectory
        repository.pathNormalization.confirmationRun
        repository.pathNormalization.confirmationTeam
        repository.pathNormalization.confirmationTitle
        repository.pathNormalization.defaultCommitMessage
        repository.pathNormalization.deselectAll
        repository.pathNormalization.differentComponent
        repository.pathNormalization.directoryNote
        repository.pathNormalization.errorInvalidTargets
        repository.pathNormalization.errorLocalChanges
        repository.pathNormalization.errorLocks
        repository.pathNormalization.errorPartialFailure
        repository.pathNormalization.errorUnknown
        repository.pathNormalization.formComposed
        repository.pathNormalization.formDecomposed
        repository.pathNormalization.noPaths
        repository.pathNormalization.problem
        repository.pathNormalization.result
        repository.pathNormalization.resultRevisions
        repository.pathNormalization.resultSummary
        repository.pathNormalization.reviewAction
        repository.pathNormalization.running
        repository.pathNormalization.sameAppearanceNote
        repository.pathNormalization.scanAgain
        repository.pathNormalization.scanning
        repository.pathNormalization.scanningDetail
        repository.pathNormalization.skipped
        repository.pathNormalization.skippedReason
        repository.pathNormalization.targets
        repository.pathNormalization.title
        repository.pathNormalization.waiting
        repository.pathNormalization.windowsNote
        ui.about.needHelp
        ui.about.pleaseSendQuestions
        ui.about.questionsSupport
        ui.about.sendEmail
        ui.about.svnKr
        ui.about.version
        ui.authentication.canceledLocalChangesRemainAvailable
        ui.authentication.cancelingDoesNotPreventViewingLocalChangesDiffs
        ui.authentication.changeFolderLocationSvnAccountKeychainPassword
        ui.authentication.checkingAccount
        ui.authentication.checkoutCompletedButPasswordCouldNotSavedKeychain
        ui.authentication.closeWithoutSavingCredentialChanges
        ui.authentication.configureSvnAccountKeychainPasswordLocalWorkingFolder
        ui.authentication.credentials
        ui.authentication.credentialsSaved
        ui.authentication.deleteSavedPassword
        ui.authentication.deleteSvnPasswordStoredKeychainLocalWorkingFolder
        ui.authentication.discardChangesClose
        ui.authentication.enterPassword
        ui.authentication.enterValidCredentials
        ui.authentication.folderCredentials
        ui.authentication.hidePassword
        ui.authentication.keychainAccessDenied
        ui.authentication.keychainAccessDeniedChooseHowAuthenticate
        ui.authentication.keychainOperationFailed
        ui.authentication.leaveBlankKeepCurrentPassword
        ui.authentication.noPasswordStored
        ui.authentication.password
        ui.authentication.passwordFolderStoredMacosKeychain
        ui.authentication.repositoryAuthenticationFailed
        ui.authentication.requiredCommitSelectedChanges
        ui.authentication.requiredDownloadLatestServerChanges
        ui.authentication.requiredLoadLatestServerHistory
        ui.authentication.saveKeychainUse
        ui.authentication.saveMacosKeychainOptional
        ui.authentication.saveSvnUsernameNewPasswordLocalWorkingFolder
        ui.authentication.saveWorkingFolderLocationSvnUsernameNewPasswordFolder
        ui.authentication.savedPasswordDeleted
        ui.authentication.saving
        ui.authentication.secureEntryBlocksKoreanInputMethodRevealPasswordEyeButton
        ui.authentication.showMacosKeychainAccessPromptAgain
        ui.authentication.showPassword
        ui.authentication.svnAccountPasswordNotValid
        ui.authentication.svnAuthenticationRequired
        ui.authentication.svnPassword
        ui.authentication.svnServerDeniedReadAccessFileCheckProjectCredentialsServer
        ui.authentication.svnUsername
        ui.authentication.svnUsernameOptional
        ui.authentication.tryKeychainAgain
        ui.authentication.useSessionOnly
        ui.authentication.username
        ui.authentication.usesExistingSvnCredentialCacheMacosKeychain
        ui.browser.actions
        ui.browser.browse
        ui.browser.browseRepository
        ui.browser.browseSvnRepository
        ui.browser.checkFoldersFilesBeforeChoosingRepositoryPathCheckOut
        ui.browser.chooseHowFilesDisplayed
        ui.browser.couldNotConnectRepository
        ui.browser.couldNotLoadRepositoryContents
        ui.browser.dateModified
        ui.browser.directory
        ui.browser.directoryEmpty
        ui.browser.enterRepositoryUrlBrowse
        ui.browser.fileAccessibilityLabel
        ui.browser.files
        ui.browser.items
        ui.browser.kind
        ui.browser.loadingFiles
        ui.browser.loadingRepositoryContents
        ui.browser.name
        ui.browser.noFiles
        ui.browser.noSearchResults
        ui.browser.openSelectedDirectory
        ui.browser.parentDirectory
        ui.browser.repositoryReturnedNoFilesSubdirectoriesPath
        ui.browser.repositoryUrl
        ui.browser.revisionOptional
        ui.browser.searchFiles
        ui.browser.size
        ui.browser.splitView
        ui.browser.symbolicLink
        ui.browser.treeView
        ui.browser.useRepositoryPath
        ui.browser.workingCopy
        ui.certificate.allowProject
        ui.certificate.allowSelfSignedCertificateNameMismatchErrorsRepository
        ui.certificate.allowUntrustedSslCertificates
        ui.certificate.doNotAllow
        ui.certificate.exceptionNotAllowedNoProjectSettingChanged
        ui.certificate.exceptionSecurityWarning
        ui.certificate.expiredNotYetValidCertificatesRequireSeparateConsentAfterSvn
        ui.certificate.issuedDifferentHostnameCheckRepositoryUrlCertificateHostnameBeforeAllowing
        ui.certificate.issuerNotTrustedConfirmIssuerServerAdministratorAllowingItBypasses
        ui.certificate.notYetValidCheckServerMacClocksCertificateStartDate
        ui.certificate.savedCertificateExceptionRetrySvnOperation
        ui.certificate.serverCertificateExpiredRenewingItSafestAllowingItLetsProject
        ui.certificate.serverCertificateProblem
        ui.certificate.svnRejectedServerCertificateReviewDetectedProblemBeforeDeciding
        ui.certificate.svnReportedCertificateProblemButDidNotIdentifySupportedReason
        ui.certificate.useOnlyServersSelfSignedCertificatesCertificateNameMismatches
        ui.certificate.useWhenTargetServerCertificateInvalidButTrustServer
        ui.changes.affected
        ui.changes.cancelDeletionRestore
        ui.changes.deletePendingItems
        ui.changes.deleteRepository
        ui.changes.filesInsideFolderAddedTogether
        ui.changes.includeCommit
        ui.changes.includeExcludeFileNextCommit
        ui.changes.localChangesRefreshed
        ui.changes.multipleCanonicallyEquivalentServerPathsExistSoAppCannotChoose
        ui.changes.noChanges
        ui.changes.pathPointsDifferentRepositoryLocationVerifyCommitDestination
        ui.changes.pendingDeletionStatus
        ui.changes.propertiesModified
        ui.changes.resolveDuplicateServerPathsManually
        ui.changes.restoreLocalFile
        ui.changes.restorePendingDeletions
        ui.changes.revertConflictLocalChanges
        ui.changes.selectChangedFileViewItsDiff
        ui.changes.showIgnoredFiles
        ui.changes.showsDiffFile
        ui.changes.switchedPath
        ui.changes.temporary
        ui.changes.thereNoLocallyModifiedFiles
        ui.changes.unicodePathConflict
        ui.changes.unversionedLocalFileBlockingServerFileSameNameMoveRename
        ui.checkout.checkOutAdd
        ui.checkout.checkOutNewSvnRepositoryRegisterExistingLocalWorkingFolder
        ui.checkout.checkOutRepositoryUrl
        ui.checkout.checkOutRepositoryUrlAddItLocalWorkingFolders
        ui.checkout.checkOutSvnRepositoryLocalFolderAddItApp
        ui.checkout.checkingOut
        ui.checkout.chooseLocalCheckoutFolder
        ui.checkout.filesDownloadedAppearHereAfterCheckoutStarts
        ui.checkout.keepDownloading
        ui.checkout.localFolderPickerHelp
        ui.checkout.localFolderRequiredError
        ui.checkout.progressLog
        ui.checkout.runningSvnCheckoutStoppedAlreadyDownloadedFilesStayLocalFolder
        ui.checkout.stopCheckout
        ui.checkout.stopCheckoutProgress
        ui.cleanup.candidateNotRegularFile
        ui.cleanup.cleanUpEquivalentPath
        ui.cleanup.cleaningCommitting
        ui.cleanup.cleaningWorkingCopy
        ui.cleanup.deleteCommitCleanup
        ui.cleanup.fileContentsCouldNotRead
        ui.cleanup.fileDoesNotAppledoubleMagicBytes
        ui.cleanup.fileDoesNotDsStoreBud1Signature
        ui.cleanup.fileNotFoundAfterUpdate
        ui.cleanup.manuallyCleanUpInterruptedLockedSvnWorkingCopy
        ui.cleanup.needed
        ui.cleanup.officeLockFileExceedsByteSafetyLimit
        ui.cleanup.onlyVerifiedCandidatesSelectedReviewEveryPathBeforeDeletingCommitting
        ui.cleanup.operationInterruptedLikeCleanUpWorkingCopyTryAgainCleanup
        ui.cleanup.pathOutsideWorkingCopySafetyBoundary
        ui.cleanup.repositoryTemporaryFileCleanup
        ui.cleanup.runCleanup
        ui.cleanup.symbolicLinksNeverCleanedAutomatically
        ui.cleanup.workingCopyCleanup
        ui.cleanup.workingCopyCleanupCompleted
        ui.cleanup.workingCopyCleanupFailedDoNotRetryCleanupRepeatedlyCopy
        ui.commit.cancelRepositoryDeletionStateRestoreRepositoryVersionLocally
        ui.commit.clearAllSelectedCommitTargets
        ui.commit.clearSelection
        ui.commit.committing
        ui.commit.confirm
        ui.commit.diffUnavailableUntilFileAddedSvnItAddedAutomaticallyWhen
        ui.commit.includeRestore
        ui.commit.item
        ui.commit.itemDeletedServer
        ui.commit.markDeletion
        ui.commit.markRepositoryDeletion
        ui.commit.markedItemDeletionCommitDeleteThemRepository
        ui.commit.message
        ui.commit.messageSavedIncorrectEncodingShownAfterRestorationOtherSvnUsers
        ui.commit.no
        ui.commit.noCommitMessage
        ui.commit.noFilesDeleted
        ui.commit.onlyMarksItemsDeletionTheyDeletedSvnRepositoryWhenCommitted
        ui.commit.pendingDeletionCount
        ui.commit.recordedEmptyMessage
        ui.commit.restoreSelectedDeletionFileServer
        ui.commit.restoreSelectedFilesAction
        ui.commit.restoreSelectedFilesConfirmationTitle
        ui.commit.restoreServer
        ui.commit.revert
        ui.commit.revertLocalChangesAction
        ui.commit.revertLocalChangesConfirmationTitle
        ui.commit.reviewCommit
        ui.commit.selectAll
        ui.commit.selectAllCurrentlyChangedFilesCommit
        ui.commit.selected
        ui.commit.selectedFilesSvnServerEnteredMessage
        ui.commit.someFilesDeletedReviewListBelowConfirmThatTheyShould
        ui.commit.uncommittedChangesDiscardedCannotRestoredSvn
        ui.commit.versionedItemsBelowSelectedDirectoryAlsoMarkedDeletion
        ui.commit.withoutMessage
        ui.common.cancel
        ui.common.changes
        ui.common.close
        ui.common.copyFullPath
        ui.common.couldNotOpenFile
        ui.common.fileType
        ui.common.folder
        ui.common.noTextDiffAvailableMayNewBinaryFile
        ui.common.openFile
        ui.common.refresh
        ui.common.refreshed
        ui.common.remove
        ui.common.revealFinder
        ui.common.save
        ui.common.selectedCount
        ui.common.unknownAuthor
        ui.common.yes
        ui.conflict.afterReviewingBothBackupsKeepContentCurrentlySavedWorkingFile
        ui.conflict.applyServerProperties
        ui.conflict.applyServerVersion
        ui.conflict.bothVersionsCopiedBackupFolderEditingCopiesDoesNotChange
        ui.conflict.confirmCurrentLocalPropertiesResolvedValues
        ui.conflict.confirmCurrentWorkingCopyState
        ui.conflict.confirmManuallyEditedContent
        ui.conflict.conflict
        ui.conflict.conflictedProperties
        ui.conflict.conflictedPropertyNameCouldNotDetermined
        ui.conflict.currentWorkingFile
        ui.conflict.discardLocalChangeRestoreServerFile
        ui.conflict.fileAlsoPropertyConflictChoosingVersionBelowResolvesPropertiesSame
        ui.conflict.fileCannotCommittedUntilItMarkedResolved
        ui.conflict.fileThatNotRepository
        ui.conflict.ifDeletedItLocallyDeletionRemainsCommitDeleteItServer
        ui.conflict.incomingServerPropertyValuesDiscardedWorkingCopy
        ui.conflict.keepFileCurrentlySavedWorkingCopyMarkConflictResolvedFile
        ui.conflict.keepFileLaterCommitReplaceRepositoryFileContent
        ui.conflict.keepMyChange
        ui.conflict.keepMyProperties
        ui.conflict.localPropertyValuesDiscarded
        ui.conflict.macosUnicodePathMatchedActualSvnManagedPath
        ui.conflict.modificationDateUnavailable
        ui.conflict.modified
        ui.conflict.more
        ui.conflict.myFile
        ui.conflict.openBackupFolder
        ui.conflict.openMyFile
        ui.conflict.openResolutionAction
        ui.conflict.openServerFile
        ui.conflict.overwriteMyVersion
        ui.conflict.overwritingVersionRemovesIncomingServerChangesWorkingFileServerFile
        ui.conflict.pathCannotCommittedUntilItsPropertyConflictResolved
        ui.conflict.propertyConflict
        ui.conflict.propertyConflictResolvedReviewPropertiesBeforeCommitting
        ui.conflict.propertyValuesKeptWell
        ui.conflict.replaceLocalPropertiesServerValues
        ui.conflict.replaceServerFileLocalEditsLeaveWorkingCopyButRemain
        ui.conflict.resolutionHeader
        ui.conflict.resolveConflictedFilesBeforeCommitting
        ui.conflict.resolvedBackupsRemovedItemCreated
        ui.conflict.resolvedReviewFileBeforeCommitting
        ui.conflict.resolving
        ui.conflict.restoreFileServerVersion
        ui.conflict.revertingRemovesItemsBelowWorkingFolderTheyCopiedBackupFolder
        ui.conflict.serverFile
        ui.conflict.serverPropertyValuesAppliedWell
        ui.conflict.serverRevision
        ui.conflict.treeConflict
        ui.conflict.treeConflictConcernsPathStateNotFileContentsNotChoice
        ui.conflict.treeConflictLocalServerTarget
        ui.conflict.uncommittedChange
        ui.conflict.uncommittedLocalChangesDiscarded
        ui.conflict.useMineAction
        ui.conflict.useMineConfirmationTitle
        ui.conflict.useServerAction
        ui.conflict.useServerConfirmationTitle
        ui.conflict.useWorkingFileAction
        ui.conflict.useWorkingFileConfirmationTitle
        ui.conflict.whenChooseVersionCurrentWorkingFilePreservedSeparatelyHiddenRecovery
        ui.demo.browseSampleProject
        ui.demo.closeSampleProjectReturnNormalMode
        ui.demo.exitDemo
        ui.demo.exploreMainFeaturesSampleDataNoServerConnectionAccount
        ui.error.bundledSvnExecutableCouldNotFoundReinstallApp
        ui.error.commitBasedOlderWorkingCopyStateRunUpdateResolveAny
        ui.error.commitCompletedButWorkingCopyValidationFailedDoNotRetry
        ui.error.conflictBackupsMustStoredOutsideWorkingCopy
        ui.error.conflictFilePathPointsOutsideWorkingCopy
        ui.error.conflictRemainsAfterSvnCommandReviewBackupsTryAgain
        ui.error.copied
        ui.error.copyAllDisplayedErrorDetailsClipboard
        ui.error.copyErrorDetails
        ui.error.currentWorkingFileCouldNotFound
        ui.error.currentWorkingFileMustRegularFileNotSymbolicLink
        ui.error.error
        ui.error.failed
        ui.error.failedRemoveIncompleteConflictBackup
        ui.error.fileRemainsConflictGoChangesChooseResolveConflictsResolveIt
        ui.error.fileVersionCouldNotFound
        ui.error.fileVersionMustRegularFileNotSymbolicLink
        ui.error.lockTokenDoesNotBelongCurrentWorkingCopyReviewOwner
        ui.error.recoveryBackupCurrentWorkingFileCouldNotVerified
        ui.error.recoveryDestinationFolderMustEmpty
        ui.error.selectedFolderNotSvnLocalWorkingFolder
        ui.error.selectedVersionFileCouldNotRestoredWorkingFile
        ui.error.serverFileVersionCouldNotFound
        ui.error.serverFileVersionMustRegularFileNotSymbolicLink
        ui.error.svnResponseCouldNotRead
        ui.error.unableLoadChanges
        ui.error.unableOpenFile
        ui.error.unknownError
        ui.error.unsupportedConflictType
        ui.error.workingCopyOperationInterruptedRunWorkingCopyCleanupTryOperation
        ui.file.copiedFilePath
        ui.file.noLongerMarkedDeleted
        ui.file.restoredButFailed
        ui.file.restoredSelectedDeletionFileServer
        ui.file.revertedLocalChanges
        ui.history.additionalRevisionProperties
        ui.history.blueDotsServerCommitsGreenRingHighestLocalRevisionOrange
        ui.history.blueDotsServerCommitsGreenRingLocalBaseOrangeBranch
        ui.history.changedPaths
        ui.history.commitHistory
        ui.history.commitTimeUnavailable
        ui.history.contentChanged
        ui.history.copyHistory
        ui.history.earlierHistory
        ui.history.fileCommitHistory
        ui.history.highestLocalRevision
        ui.history.includedLocally
        ui.history.load50More
        ui.history.loading
        ui.history.loadingCommitHistory
        ui.history.localBaseRevision
        ui.history.localBaseRevisionEarlierThanLatest50ServerRecords
        ui.history.localChanges
        ui.history.localUpdateBaseFallsBetweenTwoServerCommits
        ui.history.mixedRevisions
        ui.history.myLocalBase
        ui.history.myLocalFolderR
        ui.history.noCommitHistory
        ui.history.noValue
        ui.history.originalMessage
        ui.history.propertiesChanged
        ui.history.refreshed
        ui.history.reloadLocalChangesLatestServerCommitHistory
        ui.history.renameHistory
        ui.history.restored
        ui.history.serverCommitDetail
        ui.history.serverCommitLegend
        ui.history.serverLatest
        ui.history.serverLatestR
        ui.history.uncommittedChanges
        ui.history.uncommittedChangesBranchLocalBaseRevision
        ui.history.upDate
        ui.history.viewChangesCommit
        ui.history.viewOriginalMessageBeforeRestoration
        ui.history.workingCopyContainsMixedRevisionsRMarkerShowsHighestRevision
        ui.ignore.addedIgnoreRuleCommitDirectoryPropertyShareItTeam
        ui.ignore.alreadyVersionedFilesNotHiddenIgnoreRules
        ui.ignore.applied
        ui.ignore.appliedGitRuleSvnIgnorePropertiesCommitPropertyChangesShare
        ui.ignore.apply
        ui.ignore.applyGlobalIgnoreRules
        ui.ignore.applySelectedRules
        ui.ignore.applying
        ui.ignore.available
        ui.ignore.clear
        ui.ignore.compareGitRules
        ui.ignore.fileExtension
        ui.ignore.gitignoreNotModifiedImportOneWaySvnPropertyChangesMust
        ui.ignore.globalRulesCanAffectManyDirectoriesBelowWorkingCopyApply
        ui.ignore.importGitRules
        ui.ignore.inherited
        ui.ignore.inheritedRulesCanOnlyRemovedParentDirectoryThatOwnsProperty
        ui.ignore.item
        ui.ignore.lastCompared
        ui.ignore.manageIgnoreRules
        ui.ignore.noGitignore
        ui.ignore.noGitignoreFileFoundWorkingCopy
        ui.ignore.noSvnIgnoreRulesConfigured
        ui.ignore.removeInheritedRulesParentDirectoryThatOwnsProperty
        ui.ignore.removeRule
        ui.ignore.removedIgnoreRule
        ui.ignore.resolveUnicodePathConflictsBeforeComparingGitRulesSoProperty
        ui.ignore.review
        ui.ignore.selectAll
        ui.ignore.svnIgnoreRules
        ui.ignore.thereNoGitRulesImport
        ui.ignore.unsupported
        ui.lock.alreadyHoldLocksAllSelectedFiles
        ui.lock.changedRequiredLockPropertyFileCommitItApplyChangeOther
        ui.lock.countAccessibilityLabel
        ui.lock.currentSvnClientDoesNotSupportForcedMultiFileLocking
        ui.lock.editingDocumentSvnKr
        ui.lock.file
        ui.lock.fileBeforeOpening
        ui.lock.fileCurrentlyLockedOpeningWithoutLockMayPreventCommittingCause
        ui.lock.fileLockedSuccessfulCommitAutomaticallyReleasesLock
        ui.lock.forceLock
        ui.lock.forceLockingSelectedFileRemovesExistingUsersLocksReviewOwners
        ui.lock.forceReleaseLock
        ui.lock.forceReleaseRepositoryLock
        ui.lock.forceReleasingCanInterruptSomeoneElseWorkPathOwnerLocked
        ui.lock.informationCouldNotCheckedCanOpenFileWithoutLockingIt
        ui.lock.loadingRepositoryLocks
        ui.lock.lockAndOpenAction
        ui.lock.lockedByCurrentUser
        ui.lock.lockedByOwner
        ui.lock.lockedFile
        ui.lock.lockedFileMarkedSvnServerPreventAnotherUserCommittingIt
        ui.lock.lockingPreventsConcurrentCommitsOtherUsersReducesDocumentConflictsSuccessful
        ui.lock.noLockedFiles
        ui.lock.notAvailable
        ui.lock.openWithoutLock
        ui.lock.openWithoutLockingDonTAskAgain
        ui.lock.openedWithoutLockConcurrentCommitAnotherUserMayCauseConflict
        ui.lock.openingFileLocked
        ui.lock.releaseAllAction
        ui.lock.releaseAllConfirmationTitle
        ui.lock.releaseFromBrowserAction
        ui.lock.releaseFromListAction
        ui.lock.releaseLocks
        ui.lock.releaseLocksOwnedCurrentUserOtherUsersAbleModifyFiles
        ui.lock.releaseMyLock
        ui.lock.released
        ui.lock.releasedAllLocks
        ui.lock.releasedLocksLocksBelowCouldNotReleased
        ui.lock.removeRequiredLock
        ui.lock.repositoryLockForceReleased
        ui.lock.repositoryLocks
        ui.lock.requireLockBeforeEditing
        ui.lock.requiredBeforeEditing
        ui.lock.reviewForceLock
        ui.lock.selectedFile
        ui.lock.sheetTitle
        ui.lock.someLocksNotReleased
        ui.lock.takeAnotherUserLock
        ui.lock.tryNormalUnlockFirstIfWorkingCopyNoMatchingLock
        ui.lock.viewLockedFilesTheirCountRepository
        ui.recovery.allContentsVerifiedInterruptedSvnWorkingCopyFolderBelowDeleted
        ui.recovery.automaticUnicodePathRecovery
        ui.recovery.checkoutCanceledPartiallyDownloadedFilesMayRemain
        ui.recovery.checkoutInterrupted
        ui.recovery.chooseAction
        ui.recovery.chooseEmptyFolder
        ui.recovery.chooseEmptyRecoveryFolder
        ui.recovery.chooseFolder
        ui.recovery.cleanWorkingCopyCheckedOutServerOnlyRealLocalChanges
        ui.recovery.cleaningContinuing
        ui.recovery.continueCheckout
        ui.recovery.emptiedInterruptedCheckoutFolder
        ui.recovery.emptyFolderConfirmationAction
        ui.recovery.emptyFolderRequestAction
        ui.recovery.emptyInterruptedCheckoutFolder
        ui.recovery.falseAliasesExcluded
        ui.recovery.folderAlreadyFilesBeforeCheckoutSoAppNotEmptyIt
        ui.recovery.folderIncompleteSvnWorkingCopyContinueRegisteringItCleaningIt
        ui.recovery.folderNotEmptiedBecauseItCouldNotVerifiedSafelyInterrupted
        ui.recovery.interruptedCheckoutFolderNoLongerValidSvnWorkingCopySo
        ui.recovery.localWorkingFolderAlreadyRegistered
        ui.recovery.locallyMissing
        ui.recovery.locallyMissingActionRequired
        ui.recovery.new
        ui.recovery.newWorkingFolder
        ui.recovery.pathRecoveryCompletedOriginalWorkingFolderPreserved
        ui.recovery.preview
        ui.recovery.recoverNewWorkingFolder
        ui.recovery.successBothOriginalRecoveredCopiesRemainSidebar
        ui.repository.addLocalWorkingFolder
        ui.repository.addSvnRepository
        ui.repository.cancelAddingRepositoryCloseWindow
        ui.repository.change
        ui.repository.changeRepositoryLocation
        ui.repository.chooseSvnLocalWorkingFolders
        ui.repository.commitChangeApplyItServer
        ui.repository.copyCurrentRepositoryUrl
        ui.repository.currentRepositoryUrl
        ui.repository.currentUrlNewUrlOnlyWorkingCopyRepositoryConnectionChanges
        ui.repository.destinationNameAlreadyExists
        ui.repository.enterValidFileNameWithoutFolderPath
        ui.repository.enterValidRepositoryUrlIncludingItsScheme
        ui.repository.filePanelPrompt
        ui.repository.localFolder
        ui.repository.localFolderPickerAction
        ui.repository.localWorkingFolders
        ui.repository.mayMovedRelocateNewUrlRestoreRemoteOperations
        ui.repository.newFileName
        ui.repository.newFileNameMatchesCurrentName
        ui.repository.newFolderAppliedWhenSave
        ui.repository.newRepositoryUrl
        ui.repository.newRepositoryUrlMatchesCurrentUrl
        ui.repository.notSvnVersionedFile
        ui.repository.onlyRegularFilesCanRenamedCopiedAssignedRequiredLockProperty
        ui.repository.openFinder
        ui.repository.openRepositoryRelocation
        ui.repository.openSvnLocalWorkingFolderFinder
        ui.repository.pickNewLocationSvnWorkingFolder
        ui.repository.pressOUseButtonBottomLeft
        ui.repository.registerExistingLocalFolder
        ui.repository.registerExistingSvnWorkingFolderApp
        ui.repository.relocateAction
        ui.repository.relocatedRepositoryConnectionLocalChangesPreserved
        ui.repository.relocatingRepository
        ui.repository.relocationConfirmationTitle
        ui.repository.relocationFailedCheckCurrentUrlRelocateCorrectNewUrlIf
        ui.repository.relocationPreservesAllUncommittedLocalChanges
        ui.repository.removeApp
        ui.repository.removeSelectedWorkingFolderAppLocalFilesNotDeleted
        ui.repository.reviewRelocation
        ui.repository.workingFolderChanged
        ui.repository.workingFolderNoLongerExistsRestoreFolderRemoveItList
        ui.revision.chooseChangedFileAboveDisplayOnlyThatFileDiff
        ui.revision.chooseViewChangesHistoryDisplayActualDiff
        ui.revision.commitChanges
        ui.revision.commitNotFound
        ui.revision.currentContentsDiscardedReplacedRRecoveryCopySavedFirstResult
        ui.revision.currentWorkingFileCouldNotVerifiedRecoveryCopySoIt
        ui.revision.fileCommitHistory
        ui.revision.filePathPointsOutsideLocalWorkingFolder
        ui.revision.folderForRestoredFileNotDirectory
        ui.revision.loadingChanges
        ui.revision.loadingFileHistory
        ui.revision.noChangedFiles
        ui.revision.noFileHistory
        ui.revision.projectSvnClientDoesNotSupportReadingHistoricalFileRevisions
        ui.revision.recoveryCopiesMustStoredOutsideLocalWorkingFolder
        ui.revision.restoreWorkingFile
        ui.revision.restoreWorkingFileRevision
        ui.revision.restoredFileDidNotMatchSelectedRevisionByteByteRecovery
        ui.revision.restoredRNowLocalChangeCommitItUpdateServer
        ui.revision.restoringRevision
        ui.revision.saveRevision
        ui.revision.savedR
        ui.revision.savingRevision
        ui.revision.searchAuthorFileMessageRevision
        ui.revision.selectCommit
        ui.revision.selectFile
        ui.revision.selectedSaveLocationNotSafeRegularFileDestination
        ui.revision.workingFileMustRegularFileNotSymbolicLink
        ui.settings.alwaysLockOpenWithoutAsking
        ui.settings.alwaysOpenWithoutLockingAsking
        ui.settings.askEveryTime
        ui.settings.chooseLanguageUsedAppInterface
        ui.settings.chooseTimeZoneUsedCommitDatesTimes
        ui.settings.commitDisplayTimeZone
        ui.settings.coordinatedUniversalTimeUtc
        ui.settings.defaultKoreaStandardTimeKstDoesNotChangeOriginalCommit
        ui.settings.folderSettings
        ui.settings.hideMacOfficeTemporaryFiles
        ui.settings.hideTemporaryFilesChangesPreventThemCommittedVersionedFilesRemain
        ui.settings.japanStandardTime
        ui.settings.koreaStandardTime
        ui.settings.language
        ui.settings.macSystemTimeZone
        ui.settings.openAppWideSettingsWindow
        ui.settings.otherUsersCannotModifyLockedFileUntilCommitItRelease
        ui.settings.settings
        ui.settings.ukTime
        ui.settings.usEasternTime
        ui.settings.usPacificTime
        ui.settings.whenOpeningDocuments
        ui.status.added
        ui.status.deleted
        ui.status.diskContainingFolderStoresKoreanFilenamesOnlyDecomposedFormFilenames
        ui.status.filenameWarning
        ui.status.ignored
        ui.status.lockedFiles
        ui.status.modified
        ui.status.replaced
        ui.status.unversioned
        ui.update.addRepositoryTemporaryFileCleanupCommitAfterUpdating
        ui.update.afterUpdateCandidateContentsVerifiedReviewFinalListBeforeAny
        ui.update.beforeRetryingCommit
        ui.update.checkAppStoreLatestVersion
        ui.update.checkFromAppMenu
        ui.update.checkNow
        ui.update.checkingIncomingChanges
        ui.update.checkingUpdates
        ui.update.checkoutUpdateInterruptedDoNotRevertLocalChangesContinueUpdating
        ui.update.cleanedRepositoryTemporaryFile
        ui.update.commitMessageSelectedItemSavedIfUpdateCreatesNoConflicts
        ui.update.completeUpdatePreviewCouldNotLoadedCanStillTryUpdate
        ui.update.continueUpdating
        ui.update.createdConflictsSoCommitNotRetried
        ui.update.createdConflictsSoCommitNotRetriedResolvePathsFirst
        ui.update.downloadLatestServerChangesCurrentLocalWorkingFolder
        ui.update.goConflictResolution
        ui.update.incomingChangesThatOverlapLocalEditsMayCreateSvnConflict
        ui.update.incomplete
        ui.update.later
        ui.update.localFileBlockingUpdate
        ui.update.lockedRepository
        ui.update.newVersionDialogTitle
        ui.update.noIncomingChanges
        ui.update.preview
        ui.update.previewAvailableStatus
        ui.update.reUsingLatestVersion
        ui.update.requiredBeforeCommit
        ui.update.retryCommit
        ui.update.runUpdate
        ui.update.serverChangesInsidePendingDeletionMayNotAppearListRun
        ui.update.showingFirstCommits
        ui.update.sidebarAvailableBadge
        ui.update.someSavedCommitSelectionsDisappearedChangeListAfterUpdateReview
        ui.update.someTemporaryFilesNotCleaned
        ui.update.succeededButCleanupCommitFailedScheduledDeletionsRestored
        ui.update.succeededButCleanupCouldNotStart
        ui.update.svnRequiresWorkingCopyUpdateConfirmUpdateRetryCommitSaved
        ui.update.unableCheckAppStoreUpdates
        ui.update.update
        ui.update.updating
        ui.update.versionAvailable
        ui.update.viewAppStore
        ui.update.workingCopyUpDateServer
        """
        .split(separator: "\n")
        .map { LocalizationKey(String($0)) }
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
    let deletePendingItems = LocalizationKey("ui.changes.deletePendingItems")
    let deleteRepository = LocalizationKey("ui.changes.deleteRepository")
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
    let pendingDeletionCount = LocalizationKey("ui.commit.pendingDeletionCount")
    let recordedEmptyMessage = LocalizationKey("ui.commit.recordedEmptyMessage")
    let restoreSelectedDeletionFileServer = LocalizationKey("ui.commit.restoreSelectedDeletionFileServer")
    let restoreSelectedFilesAction = LocalizationKey("ui.commit.restoreSelectedFilesAction")
    let restoreSelectedFilesConfirmationTitle = LocalizationKey("ui.commit.restoreSelectedFilesConfirmationTitle")
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
    let addedIgnoreRuleCommitDirectoryPropertyShareItTeam = LocalizationKey("ui.ignore.addedIgnoreRuleCommitDirectoryPropertyShareItTeam")
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
    let pathRecoveryCompletedOriginalWorkingFolderPreserved = LocalizationKey("ui.recovery.pathRecoveryCompletedOriginalWorkingFolderPreserved")
    let preview = LocalizationKey("ui.recovery.preview")
    let recoverNewWorkingFolder = LocalizationKey("ui.recovery.recoverNewWorkingFolder")
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
