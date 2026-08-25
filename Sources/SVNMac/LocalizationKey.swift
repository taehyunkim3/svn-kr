struct LocalizationKey: Hashable, Sendable {
    let rawValue: String

    fileprivate init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static let error = LocalizationErrorKeys()
    static let history = LocalizationHistoryKeys()
    static let recovery = LocalizationRecoveryKeys()
    static let repository = LocalizationRepositoryKeys()
    static let ui = LocalizationUiKeys()

    static let allCases: [LocalizationKey] = [
        .error.chooseMissingItems,
        .error.deletionPartial,
        .error.deletionValidation,
        .error.fileReplacementRecovery,
        .error.pathAliasRepair,
        .error.pathNormalizationCollision,
        .error.recoveryBlocked,
        .error.recoveryValidation,
        .error.unresolvedMissingPaths,
        .error.unsupportedTargetPath,
        .history.copiedFrom,
        .recovery.reviewPaths,
        .repository.pathNormalizationAction,
        .repository.pathNormalizationActionHelp,
        .repository.pathNormalizationAfter,
        .repository.pathNormalizationBefore,
        .repository.pathNormalizationCodepointsDetail,
        .repository.pathNormalizationConfirmationCommits,
        .repository.pathNormalizationConfirmationDeleteAdd,
        .repository.pathNormalizationConfirmationDirectory,
        .repository.pathNormalizationConfirmationRun,
        .repository.pathNormalizationConfirmationTeam,
        .repository.pathNormalizationConfirmationTitle,
        .repository.pathNormalizationDefaultCommitMessage,
        .repository.pathNormalizationDeselectAll,
        .repository.pathNormalizationDifferentComponent,
        .repository.pathNormalizationDirectoryNote,
        .repository.pathNormalizationErrorInvalidTargets,
        .repository.pathNormalizationErrorLocalChanges,
        .repository.pathNormalizationErrorLocks,
        .repository.pathNormalizationErrorPartialFailure,
        .repository.pathNormalizationErrorUnknown,
        .repository.pathNormalizationFormComposed,
        .repository.pathNormalizationFormDecomposed,
        .repository.pathNormalizationNoPaths,
        .repository.pathNormalizationProblem,
        .repository.pathNormalizationResult,
        .repository.pathNormalizationResultRevisions,
        .repository.pathNormalizationResultSummary,
        .repository.pathNormalizationReviewAction,
        .repository.pathNormalizationRunning,
        .repository.pathNormalizationSameAppearanceNote,
        .repository.pathNormalizationScanAgain,
        .repository.pathNormalizationScanning,
        .repository.pathNormalizationScanningDetail,
        .repository.pathNormalizationSkipped,
        .repository.pathNormalizationSkippedReason,
        .repository.pathNormalizationTargets,
        .repository.pathNormalizationTitle,
        .repository.pathNormalizationWaiting,
        .repository.pathNormalizationWindowsNote,
        .ui.a.cleanWorkingCopyIsCheckedOutFromTheSer,
        .ui.a.conflictFilePathPointsOutsideTheWorking,
        .ui.a.lockedFileIsMarkedOnTheSvnServerToPre,
        .ui.a.passwordForThisFolderIsStoredInMacosKe,
        .ui.about.svnKr,
        .ui.add.aLocalWorkingFolder,
        .ui.add.repositoryTemporaryFileCleanupCommit,
        .ui.add.svnRepository,
        .ui.added.label,
        .ui.added.ignoreRuleCommitTheDirectoryProperty,
        .ui.additional.revisionProperties,
        .ui.affected.label,
        .ui.after.reviewingBothBackupsKeepTheContentCu,
        .ui.after.updateVerifyCandidatesThenReviewAndC,
        .ui.all.selectedFilesAlreadyLockedByYou,
        .ui.allow.certificateFailureForProject,
        .ui.allow.selfSignedAndCertificateNameMismatch,
        .ui.allow.untrustedSslCertificates,
        .ui.already.versionedFilesAreNotHiddenByIgnore,
        .ui.always.lockAndOpenDocuments,
        .ui.always.openDocumentsWithoutLocking,
        .ui.an.updateIsAvailable,
        .ui.and.moreItemsCount,
        .ui.applied.label,
        .ui.applied.gitRuleSToSvnIgnorePropertiesComm,
        .ui.apply.label,
        .ui.apply.globalIgnoreRules,
        .ui.apply.selectedRules,
        .ui.apply.serverProperties,
        .ui.apply.serverVersion,
        .ui.applying.label,
        .ui.ask.everyTimeBeforeOpeningDocuments,
        .ui.authentication.isRequiredToCommitTheSelecte,
        .ui.authentication.isRequiredToDownloadTheLates,
        .ui.authentication.isRequiredToLoadTheLatestSe,
        .ui.authentication.usesTheExistingSvnCredential,
        .ui.authentication.wasCanceledLocalChangesRemain,
        .ui.automatic.unicodePathRecovery,
        .ui.available.label,
        .ui.blue.dotsAreServerCommitsTheGreenRingIsYBase,
        .ui.blue.dotsAreServerCommitsTheGreenRingIsYHighestRevision,
        .ui.both.versionsWereCopiedToABackupFolderEdi,
        .ui.browse.label,
        .ui.browse.repository,
        .ui.browse.repositoryBeforeCheckout,
        .ui.browse.sampleProject,
        .ui.browse.svnRepository,
        .ui.bulk.unlockCompleted,
        .ui.bulk.unlockConfirmationDetails,
        .ui.bulk.unlockConfirmationTitle,
        .ui.bulk.unlockPartialFailureDetails,
        .ui.bulk.unlockPartialFailureTitle,
        .ui.cancel.label,
        .ui.cancel.addingTheRepositoryAndCloseThisWind,
        .ui.cancel.deletionAndRestore,
        .ui.cancel.theRepositoryDeletionStateForAndRes,
        .ui.canceled.checkoutFolderEmptied,
        .ui.canceled.checkoutFolderNotEmptied,
        .ui.canceling.doesNotPreventViewingLocalChanges,
        .ui.certificate.exceptionNotAllowed,
        .ui.certificate.exceptionSavedForProject,
        .ui.certificate.exceptionSecurityWarning,
        .ui.certificate.expiredGuidance,
        .ui.certificate.nameMismatchGuidance,
        .ui.certificate.notYetValidGuidance,
        .ui.certificate.unclassifiedGuidance,
        .ui.certificate.unknownCaGuidance,
        .ui.change.label,
        .ui.change.repositoryLocation,
        .ui.change.thisFolderSLocationSvnAccountAndK,
        .ui.changed.paths,
        .ui.changes.label,
        .ui.check.forUpdatesAction,
        .ui.check.forUpdatesSecondary,
        .ui.check.outANewSvnRepositoryOrRegisterAnEx,
        .ui.check.outARepositoryUrlAndAddItToYourLo,
        .ui.check.outAndAdd,
        .ui.check.outRepositoryUrl,
        .ui.check.outTheSvnRepositoryIntoTheLocalFold,
        .ui.check.theAppStoreForTheLatestVersion,
        .ui.checking.forUpdates,
        .ui.checking.incomingChanges,
        .ui.checking.out,
        .ui.checking.theAccount,
        .ui.checkout.completedButThePasswordCouldNotBe,
        .ui.checkout.folderWasNotEmptyCannotDelete,
        .ui.checkout.progressLog,
        .ui.checkout.recoveryValidationFailed,
        .ui.checkout.wasInterrupted,
        .ui.choose.labelPrimary,
        .ui.choose.labelAction,
        .ui.choose.aChangedFileAboveToDisplayOnlyThat,
        .ui.choose.aLocalFolderForTheCheckout,
        .ui.choose.action,
        .ui.choose.anEmptyFolder,
        .ui.choose.anEmptyRecoveryFolder,
        .ui.choose.fileBrowserViewMode,
        .ui.choose.folder,
        .ui.choose.localCheckoutFolder,
        .ui.choose.svnLocalWorkingFolders,
        .ui.choose.theLanguageUsedInTheAppInterface,
        .ui.choose.theLocalFolderForTheCheckout,
        .ui.choose.theTimeZoneUsedForCommitDatesAndT,
        .ui.choose.viewChangesInTheHistoryToDisplayTh,
        .ui.clean.upEquivalentPath,
        .ui.cleaned.repositoryTemporaryFiles,
        .ui.cleaning.andCommitting,
        .ui.cleaning.andContinuingCheckout,
        .ui.cleaning.workingCopy,
        .ui.cleanup.commitFailedUpdateSucceeded,
        .ui.cleanup.couldNotStartUpdateSucceeded,
        .ui.cleanup.interruptedWorkingCopyManually,
        .ui.cleanup.needed,
        .ui.cleanup.reasonFileMissing,
        .ui.cleanup.reasonInvalidAppledoubleSignature,
        .ui.cleanup.reasonInvalidDsStoreSignature,
        .ui.cleanup.reasonLockedBy,
        .ui.cleanup.reasonNotRegularFile,
        .ui.cleanup.reasonOfficeLockTooLarge,
        .ui.cleanup.reasonSymbolicLink,
        .ui.cleanup.reasonUnreadable,
        .ui.cleanup.reasonUnsafePath,
        .ui.cleanup.someItemsFailed,
        .ui.clear.label,
        .ui.clear.allSelectedCommitTargets,
        .ui.clear.selection,
        .ui.close.label,
        .ui.close.theSampleProjectAndReturnToNormalMo,
        .ui.close.withoutSavingCredentialChanges,
        .ui.commit.changes,
        .ui.commit.deletionRestorePartial,
        .ui.commit.history,
        .ui.commit.historyTimeZone,
        .ui.commit.inputSavedUpdateThenRetry,
        .ui.commit.message,
        .ui.commit.notFound,
        .ui.commit.requiresUpdateBeforeRetry,
        .ui.commit.selected,
        .ui.commit.theSelectedFilesToTheSvnServerWith,
        .ui.commit.timeUnavailable,
        .ui.commit.withoutAMessage,
        .ui.committing.label,
        .ui.compare.gitRules,
        .ui.configure.theSvnAccountAndKeychainPassword,
        .ui.confirm.commit,
        .ui.confirm.currentWorkingCopyState,
        .ui.confirm.manuallyEditedContent,
        .ui.confirm.repositoryRelocation,
        .ui.conflict.label,
        .ui.conflict.backupsMustBeStoredOutsideTheWork,
        .ui.conflicted.properties,
        .ui.conflicted.propertyNameUnavailable,
        .ui.content.andPropertyConflictTogether,
        .ui.content.changed,
        .ui.localizationContinue.checkout,
        .ui.localizationContinue.incompleteByUpdating,
        .ui.localizationContinue.update,
        .ui.coordinated.universalTimeUtc,
        .ui.copied.label,
        .ui.copied.theFilePath,
        .ui.copy.allDisplayedErrorDetailsToTheClipboar,
        .ui.copy.currentRepositoryUrl,
        .ui.copy.errorDetails,
        .ui.copy.fullPath,
        .ui.copy.withHistory,
        .ui.could.notOpenTheFile,
        .ui.credentials.label,
        .ui.credentials.savedFor,
        .ui.current.repositoryUrl,
        .ui.current.workingFile,
        .ui.delete.andCommitCleanup,
        .ui.delete.fromRepository,
        .ui.delete.missingItems,
        .ui.delete.savedPassword,
        .ui.delete.theSvnPasswordStoredInKeychainForT,
        .ui.deleted.label,
        .ui.destination.alreadyExists,
        .ui.destination.matchesSource,
        .ui.diff.isUnavailableUntilThisFileIsAddedTo,
        .ui.directory.label,
        .ui.discard.changesAndClose,
        .ui.discard.localChangeAndRestoreServerFile,
        .ui.localizationDo.notAllowCertificateException,
        .ui.document.openingMethod,
        .ui.download.theLatestServerChangesIntoTheCurr,
        .ui.earlier.history,
        .ui.editing.documentInSvnKr,
        .ui.empty.canceledCheckoutFolderConfirmation,
        .ui.empty.checkoutFolder,
        .ui.empty.folderDestructive,
        .ui.enter.password,
        .ui.enter.repositoryUrlToBrowse,
        .ui.enter.validCredentials,
        .ui.error.label,
        .ui.exit.demo,
        .ui.expired.andNotYetValidRequireSeparateConsent,
        .ui.explicit.lockCompleted,
        .ui.explore.theMainFeaturesWithSampleDataAndN,
        .ui.failed.label,
        .ui.failed.toRemoveAnIncompleteConflictBackup,
        .ui.localizationFalse.aliasesExcluded,
        .ui.file.labelFile,
        .ui.file.labelFile2,
        .ui.file.actionCommitRequired,
        .ui.file.browserActions,
        .ui.file.browserItemsCount,
        .ui.file.browserKindColumn,
        .ui.file.browserModifiedColumn,
        .ui.file.browserNameColumn,
        .ui.file.browserSizeColumn,
        .ui.file.browserSplitView,
        .ui.file.browserTreeView,
        .ui.file.browserWorkingCopyRoot,
        .ui.file.commitHistoryFileCommitHistory,
        .ui.file.commitHistoryFileCommitHistory2,
        .ui.file.remainsInConflictResolveBeforeRetry,
        .ui.filename.warning,
        .ui.files.label,
        .ui.files.beingDownloadedWillAppearHereAfterCh,
        .ui.files.insideThisFolderWillBeAddedTogether,
        .ui.files.notInRepositoryCount,
        .ui.folder.credentials,
        .ui.folder.label,
        .ui.folder.settings,
        .ui.force.lockClientUnavailable,
        .ui.force.lockConfirmationAction,
        .ui.force.lockConfirmationDetails,
        .ui.force.lockConfirmationTitle,
        .ui.force.releaseLock,
        .ui.force.releaseRepositoryLock,
        .ui.force.unlockDetailsOwnerTimeCommentOriginal,
        .ui.gitignore.isNotModifiedImportIsOneWayAnd,
        .ui.global.rulesCanAffectManyDirectoriesBelowT,
        .ui.go.resolveUpdateConflicts,
        .ui.hide.macOfficeTemporaryFiles,
        .ui.hide.password,
        .ui.hide.temporaryFilesFromChangesAndCommitTarg,
        .ui.highest.localRevision,
        .ui.history.refreshed,
        .ui.ignore.thisExtension,
        .ui.ignore.thisItem,
        .ui.ignored.label,
        .ui.localizationImport.gitRules,
        .ui.include.inCommit,
        .ui.include.inRestore,
        .ui.include.orExcludeThisFileFromTheNextCommi,
        .ui.included.locally,
        .ui.incoming.changesThatOverlapLocalEditsMayCr,
        .ui.incomplete.checkoutRecoveryOptions,
        .ui.incomplete.updateRequired,
        .ui.inherited.from,
        .ui.inherited.rulesCanOnlyBeRemovedFromThePar,
        .ui.invalid.fileName,
        .ui.invalid.repositoryUrl,
        .ui.item.s,
        .ui.japan.standardTimeJstUtc9,
        .ui.keep.downloading,
        .ui.keep.localPropertiesAsResolvedValues,
        .ui.keep.myChange,
        .ui.keep.myProperties,
        .ui.keep.theFileCurrentlySavedInTheWorkingCop,
        .ui.keep.yourFileALaterCommitWillReplaceTheR,
        .ui.keychain.accessWasDenied,
        .ui.keychain.accessWasDeniedChooseHowToAuthent,
        .ui.keychain.operationFailed,
        .ui.korea.standardTimeKstUtc9,
        .ui.language.label,
        .ui.last.compared,
        .ui.later.label,
        .ui.leave.blankToKeepTheCurrentPassword,
        .ui.load.localization50more,
        .ui.loading.label,
        .ui.loading.changes,
        .ui.loading.commitHistory,
        .ui.loading.fileHistory,
        .ui.loading.files,
        .ui.loading.repositoryContents,
        .ui.loading.repositoryLocks,
        .ui.local.changes,
        .ui.local.changesArePreserved,
        .ui.local.changesRefreshed,
        .ui.local.changesWillBeDiscarded,
        .ui.local.deletionWillRemainAndACommitWillDe,
        .ui.local.folder,
        .ui.local.propertyValuesWillBeDiscarded,
        .ui.local.workingFolders,
        .ui.locally.missingActionRequired,
        .ui.locally.missing,
        .ui.lock.andOpen,
        .ui.lock.belongsToAnotherWorkingCopyForceUnlock,
        .ui.lock.fileExplicitly,
        .ui.lock.informationCouldNotBeCheckedYouCanOp,
        .ui.lock.selectedFiles,
        .ui.lock.thisFileBeforeOpening,
        .ui.locked.by,
        .ui.locked.byYou,
        .ui.locked.files,
        .ui.locked.filesBlockOtherUsersUntilCommitOrUnl,
        .ui.locking.preventsConcurrentCommitsByOtherUse,
        .ui.locks.labelFormatted,
        .ui.locks.labelSecondary,
        .ui.mac.systemTimeZone,
        .ui.manage.ignoreRules,
        .ui.mark.forDeletion,
        .ui.mark.forRepositoryDeletion,
        .ui.marked.itemSForDeletionCommitToDeleteThem,
        .ui.mixed.revisions,
        .ui.modification.dateUnavailable,
        .ui.modified.labelPrimary,
        .ui.modified.labelFormatted,
        .ui.move.orRenameTheLocalFileThenUpdate,
        .ui.multiple.canonicallyEquivalentServerPathsExi,
        .ui.my.file,
        .ui.my.localBase,
        .ui.my.localFolderR,
        .ui.my.propertiesAlsoKept,
        .ui.need.help,
        .ui.needs.lockCommitRequired,
        .ui.needs.lockDisable,
        .ui.needs.lockEnable,
        .ui.needs.lockEnabled,
        .ui.new.label,
        .ui.new.fileName,
        .ui.new.repositoryUrl,
        .ui.new.workingFolder,
        .ui.no.label,
        .ui.no.changedFiles,
        .ui.no.changes,
        .ui.no.commitHistory,
        .ui.no.commitMessage,
        .ui.no.fileHistory,
        .ui.no.files,
        .ui.no.gitignore,
        .ui.no.gitignoreFileWasFoundInTheWorkingCopy,
        .ui.no.incomingChanges,
        .ui.no.itemsInRepositoryDirectory,
        .ui.no.lockedFiles,
        .ui.no.passwordIsStored,
        .ui.no.searchResults,
        .ui.no.serverDeletionsRemaining,
        .ui.no.svnIgnoreRulesAreConfigured,
        .ui.no.textDiffIsAvailableThisMayBeANewOrB,
        .ui.no.value,
        .ui.not.available,
        .ui.obstructed.localFile,
        .ui.on.successBothTheOriginalAndRecoveredCopie,
        .ui.only.verifiedWorkingCopyWillBeDeletedPath,
        .ui.localizationOpen.backupFolder,
        .ui.localizationOpen.file,
        .ui.localizationOpen.inFinder,
        .ui.localizationOpen.myFile,
        .ui.localizationOpen.repositoryRelocation,
        .ui.localizationOpen.selectedDirectory,
        .ui.localizationOpen.serverFile,
        .ui.localizationOpen.theAppWideSettingsWindow,
        .ui.localizationOpen.thisSvnLocalWorkingFolderInFinder,
        .ui.localizationOpen.withoutLockAndDoNotAskAgain,
        .ui.localizationOpen.withoutLock,
        .ui.opened.withoutALockAConcurrentCommitByAno,
        .ui.opening.aFileLockedByYou,
        .ui.operation.wasInterruptedCleanupPrompt,
        .ui.original.message,
        .ui.overwrite.withMine,
        .ui.parent.directory,
        .ui.password.label,
        .ui.path.recoveryCompletedTheOriginalWorkingFol,
        .ui.pending.deletionPrimary,
        .ui.pending.deletionFormatted,
        .ui.pick.theNewLocationOfThisSvnWorkingFolder,
        .ui.please.sendQuestionsTo,
        .ui.press.oOrUseTheButtonAtTheBottomLeft,
        .ui.preview.failedUpdateStillAvailable,
        .ui.properties.changed,
        .ui.property.conflict,
        .ui.property.conflictBlocksCommitUntilResolved,
        .ui.property.conflictResolvedReviewBeforeCommit,
        .ui.property.modified,
        .ui.questions.support,
        .ui.recover.toNewWorkingFolder,
        .ui.recovery.preview,
        .ui.refresh.label,
        .ui.refreshed.label,
        .ui.register.anExistingSvnWorkingFolderInTheA,
        .ui.register.existingLocalFolder,
        .ui.release.allMyLocks,
        .ui.release.lock,
        .ui.release.lockNormally,
        .ui.release.locksCount,
        .ui.release.myLock,
        .ui.reload.localChangesAndTheLatestServerCommi,
        .ui.relocate.repository,
        .ui.relocating.repository,
        .ui.remove.label,
        .ui.remove.inheritedRulesFromTheParentDirectory,
        .ui.remove.theSelectedWorkingFolderFromTheApp,
        .ui.remove.thisRule,
        .ui.remove.workingFolderFromAppConfirmation,
        .ui.removed.ignoreRule,
        .ui.rename.withHistory,
        .ui.replace.localPropertiesWithServerValues,
        .ui.replace.withTheServerFileYourLocalEditsLe,
        .ui.replaced.label,
        .ui.repository.authenticationFailed,
        .ui.repository.connectionFailed,
        .ui.repository.contentsFailed,
        .ui.repository.directoryEmpty,
        .ui.repository.locks,
        .ui.repository.mayHaveMoved,
        .ui.repository.relocated,
        .ui.repository.relocationFailedRecovery,
        .ui.repository.relocationSummary,
        .ui.repository.temporaryFileCleanup,
        .ui.repository.url,
        .ui.repository.urlUnchanged,
        .ui.resolve.conflictAction,
        .ui.resolve.conflictSecondary,
        .ui.resolve.conflictedFilesBeforeCommitting,
        .ui.resolve.duplicateServerPathsManually,
        .ui.resolve.unicodePathConflictsBeforeComparing,
        .ui.resolving.label,
        .ui.restore.fileFromServerVersion,
        .ui.restore.localFile,
        .ui.restore.selectedFilesAction,
        .ui.restore.selectedFilesConfirmation,
        .ui.restore.selectedFilesCount,
        .ui.restore.selectedPendingDeletions,
        .ui.restore.selectedServerFiles,
        .ui.restore.serverVersionRemovesTheseItems,
        .ui.restore.targetNotDeleted,
        .ui.restore.workingFileConfirmation,
        .ui.restore.workingFileToRevision,
        .ui.restore.workingFileWarning,
        .ui.restored.label,
        .ui.restored.revisionCommitRequired,
        .ui.restored.selectedServerFiles,
        .ui.restoring.revision,
        .ui.reveal.inFinder,
        .ui.revert.conflictDiscardsLocalChangesAndConflict,
        .ui.revert.label,
        .ui.revert.localChangesQuestion,
        .ui.revert.localChangesAction,
        .ui.reverted.localChanges,
        .ui.review.label,
        .ui.review.commit,
        .ui.review.forceLock,
        .ui.review.repositoryRelocation,
        .ui.review.updateThenRetryCommit,
        .ui.review.verifiedFilesBeforeDeletingAndCommitt,
        .ui.revision.historyClientUnavailable,
        .ui.revision.optional,
        .ui.revision.restoreBackupInsideWorkingCopy,
        .ui.revision.restoreBackupVerificationFailed,
        .ui.revision.restoreMissingWorkingFile,
        .ui.revision.restorePathOutsideWorkingCopy,
        .ui.revision.restoreReplacementVerificationFailed,
        .ui.revision.restoreUnsafeWorkingFile,
        .ui.revision.saveInvalidDestination,
        .ui.run.update,
        .ui.run.workingCopyCleanup,
        .ui.save.label,
        .ui.save.inKeychainAndUse,
        .ui.save.inMacosKeychainOptional,
        .ui.save.theSvnUsernameAndNewPasswordForThis,
        .ui.save.theWorkingFolderLocationSvnUsernameAn,
        .ui.save.thisRevisionAs,
        .ui.saved.commitSelectionNoLongerAvailable,
        .ui.saved.historicalRevision,
        .ui.saving.label,
        .ui.saving.revision,
        .ui.search.authorFileMessageOrRevision,
        .ui.search.files,
        .ui.secure.entryBlocksTheKoreanInputMethodReve,
        .ui.select.aChangedFileToViewItsDiff,
        .ui.select.aCommit,
        .ui.select.aFile,
        .ui.select.allSelectAll,
        .ui.select.allCurrentlyChangedFilesForCommit,
        .ui.select.allSelectAll2,
        .ui.selected.label,
        .ui.send.email,
        .ui.server.certificateProblem,
        .ui.server.certificateProblemDetected,
        .ui.server.changesInsideAPendingDeletionMayNot,
        .ui.server.commit,
        .ui.server.deletionCount,
        .ui.server.deletionWarning,
        .ui.server.file,
        .ui.server.latest,
        .ui.server.latestR,
        .ui.server.propertiesAlsoApplied,
        .ui.server.propertyValuesWillBeDiscarded,
        .ui.server.revision,
        .ui.server.versionChangesWillBeDiscarded,
        .ui.settings.label,
        .ui.show.ignoredFiles,
        .ui.show.password,
        .ui.show.theMacosKeychainAccessPromptAgain,
        .ui.showing.firstCommitsOfTotal,
        .ui.shows.theDiffForThisFile,
        .ui.source.isNotFile,
        .ui.source.isNotVersioned,
        .ui.stop.checkout,
        .ui.stop.theCheckoutInProgress,
        .ui.svn.authenticationRequired,
        .ui.svn.ignoreRules,
        .ui.svn.password,
        .ui.svn.username,
        .ui.svn.usernameOptional,
        .ui.switched.path,
        .ui.switched.pathCommitWarning,
        .ui.symbolic.link,
        .ui.temporary.label,
        .ui.the.bundledSvnExecutableCouldNotBeFoundRe,
        .ui.the.checkoutWasCanceledPartiallyDownloadedF,
        .ui.the.commitCompletedButWorkingCopyValidation,
        .ui.the.commitIsBasedOnAnOlderWorkingCopySta,
        .ui.the.commitWillBeRecordedWithAnEmptyMessag,
        .ui.the.conflictRemainsAfterTheSvnCommandRevie,
        .ui.the.conflictWasResolvedReviewTheFileBefore,
        .ui.the.currentWorkingFileCouldNotBeFound,
        .ui.the.currentWorkingFileMustBeARegularFile,
        .ui.the.defaultIsKoreaStandardTimeKstThisDoes,
        .ui.the.fileIsLockedASuccessfulCommitAutomatic,
        .ui.the.lockWasForceReleased,
        .ui.the.lockWasReleased,
        .ui.the.macosUnicodePathWasMatchedToTheActual,
        .ui.the.newFolderIsAppliedWhenYouSave,
        .ui.the.recoveryBackupOfTheCurrentWorkingFile,
        .ui.the.recoveryDestinationFolderMustBeEmpty,
        .ui.the.runningSvnCheckoutWillBeStoppedAlready,
        .ui.the.savedPasswordWasDeleted,
        .ui.the.selectedFolderIsNotAnSvnLocalWorking,
        .ui.the.selectedVersionOfYourFileCouldNotBeR,
        .ui.the.serverFileVersionCouldNotBeFound,
        .ui.the.serverFileVersionMustBeARegularFileN,
        .ui.the.svnAccountOrPasswordIsNotValid,
        .ui.the.svnResponseCouldNotBeRead,
        .ui.the.svnServerDeniedReadAccessToThisFileC,
        .ui.the.workingCopyContainsMixedRevisionsRThis,
        .ui.the.workingCopyIsUpToDateWithTheServer,
        .ui.the.workingFolderNoLongerExistsRestoreThe,
        .ui.the.workingFolderWasChangedTo,
        .ui.there.areNoGitRulesToImport,
        .ui.there.areNoLocallyModifiedFiles,
        .ui.this.commitMessageWasSavedWithIncorrectEnc,
        .ui.this.diskStoresKoreanFilenamesInDecomposed,
        .ui.this.fileCannotBeCommittedUntilItIsMarked,
        .ui.this.fileIsCurrentlyLockedByOpeningWithout,
        .ui.this.isAServerCommit,
        .ui.this.isYourLocalBaseRevision,
        .ui.this.localWorkingFolderIsAlreadyRegistered,
        .ui.this.onlyMarksTheItemsForDeletionTheyAre,
        .ui.tree.conflict,
        .ui.tree.conflictIsNotAChoiceBetweenTwoFiles,
        .ui.tree.conflictResolvedWithSubtreeBackup,
        .ui.localizationTry.keychainAgain,
        .ui.localizationTry.normalUnlockBeforeForceUnlock,
        .ui.uk.time,
        .ui.unable.toCheckTheAppStoreForUpdates,
        .ui.unable.toLoadChanges,
        .ui.unable.toOpenFile,
        .ui.uncommitted.changes,
        .ui.uncommitted.changesBranchFromYourLocalBase,
        .ui.uncommitted.changesCount,
        .ui.uncommitted.changesInWillBeDiscardedAndCan,
        .ui.unicode.pathConflict,
        .ui.unknown.author,
        .ui.unknown.error,
        .ui.unsupported.label,
        .ui.unsupported.conflictType,
        .ui.unversioned.label,
        .ui.up.toDate,
        .ui.update.label,
        .ui.update.andRetryCommit,
        .ui.update.conflictsBlockedCommitRetry,
        .ui.update.createdConflictsCommitNotRetried,
        .ui.update.preview,
        .ui.update.requiredPrimary,
        .ui.update.requiredBeforeCommitRetry,
        .ui.update.requiredSecondary,
        .ui.updating.label,
        .ui.us.easternTime,
        .ui.us.pacificTime,
        .ui.use.currentWorkingFilePrimary,
        .ui.use.currentWorkingFileQuestion,
        .ui.use.myFilePrimary,
        .ui.use.myFileQuestion,
        .ui.use.onlyForServersWithSelfSignedCertificat,
        .ui.use.repositoryPath,
        .ui.use.serverFilePrimary,
        .ui.use.serverFileQuestion,
        .ui.use.thisSessionOnly,
        .ui.use.thisWhenTheTargetServerSCertificateIs,
        .ui.username.label,
        .ui.version.label,
        .ui.version.isAvailable,
        .ui.versioned.itemsBelowTheSelectedDirectoryWil,
        .ui.view.changesInThisCommit,
        .ui.view.inAppStore,
        .ui.view.theLockedFilesAndTheirCountInThisRe,
        .ui.view.theOriginalMessageBeforeRestoration,
        .ui.when.youChooseAVersionTheCurrentWorkingFi,
        .ui.working.copyCleanup,
        .ui.working.copyCleanupCompleted,
        .ui.working.copyCleanupFailedContactSupport,
        .ui.working.copyOperationInterruptedRunCleanup,
        .ui.yes.label,
        .ui.you.reUsingTheLatestVersion,
        .ui.your.fileVersionCouldNotBeFound,
        .ui.your.fileVersionMustBeARegularFileNotAS,
        .ui.your.localBaseRevisionIsEarlierThanTheLat,
        .ui.your.localUpdateBaseFallsBetweenTwoServer,
    ]
}

struct LocalizationErrorKeys {
    let chooseMissingItems = LocalizationKey("error.choose.missing.items")
    let deletionPartial = LocalizationKey("error.deletion.partial")
    let deletionValidation = LocalizationKey("error.deletion.validation")
    let fileReplacementRecovery = LocalizationKey("error.file.replacement.recovery")
    let pathAliasRepair = LocalizationKey("error.path.alias.repair")
    let pathNormalizationCollision = LocalizationKey("error.path.normalization.collision")
    let recoveryBlocked = LocalizationKey("error.recovery.blocked")
    let recoveryValidation = LocalizationKey("error.recovery.validation")
    let unresolvedMissingPaths = LocalizationKey("error.unresolved.missing.paths")
    let unsupportedTargetPath = LocalizationKey("error.unsupported.target.path")
}

struct LocalizationHistoryKeys {
    let copiedFrom = LocalizationKey("history.copied.from")
}

struct LocalizationRecoveryKeys {
    let reviewPaths = LocalizationKey("recovery.review.paths")
}

struct LocalizationRepositoryKeys {
    let pathNormalizationAction = LocalizationKey("repository.path.normalization.action")
    let pathNormalizationActionHelp = LocalizationKey("repository.path.normalization.action.help")
    let pathNormalizationAfter = LocalizationKey("repository.path.normalization.after")
    let pathNormalizationBefore = LocalizationKey("repository.path.normalization.before")
    let pathNormalizationCodepointsDetail = LocalizationKey("repository.path.normalization.codepoints.detail")
    let pathNormalizationConfirmationCommits = LocalizationKey("repository.path.normalization.confirmation.commits")
    let pathNormalizationConfirmationDeleteAdd = LocalizationKey("repository.path.normalization.confirmation.delete.add")
    let pathNormalizationConfirmationDirectory = LocalizationKey("repository.path.normalization.confirmation.directory")
    let pathNormalizationConfirmationRun = LocalizationKey("repository.path.normalization.confirmation.run")
    let pathNormalizationConfirmationTeam = LocalizationKey("repository.path.normalization.confirmation.team")
    let pathNormalizationConfirmationTitle = LocalizationKey("repository.path.normalization.confirmation.title")
    let pathNormalizationDefaultCommitMessage = LocalizationKey("repository.path.normalization.default.commit.message")
    let pathNormalizationDeselectAll = LocalizationKey("repository.path.normalization.deselect.all")
    let pathNormalizationDifferentComponent = LocalizationKey("repository.path.normalization.different.component")
    let pathNormalizationDirectoryNote = LocalizationKey("repository.path.normalization.directory.note")
    let pathNormalizationErrorInvalidTargets = LocalizationKey("repository.path.normalization.error.invalid.targets")
    let pathNormalizationErrorLocalChanges = LocalizationKey("repository.path.normalization.error.local.changes")
    let pathNormalizationErrorLocks = LocalizationKey("repository.path.normalization.error.locks")
    let pathNormalizationErrorPartialFailure = LocalizationKey("repository.path.normalization.error.partial.failure")
    let pathNormalizationErrorUnknown = LocalizationKey("repository.path.normalization.error.unknown")
    let pathNormalizationFormComposed = LocalizationKey("repository.path.normalization.form.composed")
    let pathNormalizationFormDecomposed = LocalizationKey("repository.path.normalization.form.decomposed")
    let pathNormalizationNoPaths = LocalizationKey("repository.path.normalization.no.paths")
    let pathNormalizationProblem = LocalizationKey("repository.path.normalization.problem")
    let pathNormalizationResult = LocalizationKey("repository.path.normalization.result")
    let pathNormalizationResultRevisions = LocalizationKey("repository.path.normalization.result.revisions")
    let pathNormalizationResultSummary = LocalizationKey("repository.path.normalization.result.summary")
    let pathNormalizationReviewAction = LocalizationKey("repository.path.normalization.review.action")
    let pathNormalizationRunning = LocalizationKey("repository.path.normalization.running")
    let pathNormalizationSameAppearanceNote = LocalizationKey("repository.path.normalization.same.appearance.note")
    let pathNormalizationScanAgain = LocalizationKey("repository.path.normalization.scan.again")
    let pathNormalizationScanning = LocalizationKey("repository.path.normalization.scanning")
    let pathNormalizationScanningDetail = LocalizationKey("repository.path.normalization.scanning.detail")
    let pathNormalizationSkipped = LocalizationKey("repository.path.normalization.skipped")
    let pathNormalizationSkippedReason = LocalizationKey("repository.path.normalization.skipped.reason")
    let pathNormalizationTargets = LocalizationKey("repository.path.normalization.targets")
    let pathNormalizationTitle = LocalizationKey("repository.path.normalization.title")
    let pathNormalizationWaiting = LocalizationKey("repository.path.normalization.waiting")
    let pathNormalizationWindowsNote = LocalizationKey("repository.path.normalization.windows.note")
}

struct LocalizationUiKeys {
    let a = LocalizationUIAKeys()
    let about = LocalizationUIAboutKeys()
    let add = LocalizationUIAddKeys()
    let added = LocalizationUIAddedKeys()
    let additional = LocalizationUIAdditionalKeys()
    let affected = LocalizationUIAffectedKeys()
    let after = LocalizationUIAfterKeys()
    let all = LocalizationUIAllKeys()
    let allow = LocalizationUIAllowKeys()
    let already = LocalizationUIAlreadyKeys()
    let always = LocalizationUIAlwaysKeys()
    let an = LocalizationUIAnKeys()
    let and = LocalizationUIAndKeys()
    let applied = LocalizationUIAppliedKeys()
    let apply = LocalizationUIApplyKeys()
    let applying = LocalizationUIApplyingKeys()
    let ask = LocalizationUIAskKeys()
    let authentication = LocalizationUIAuthenticationKeys()
    let automatic = LocalizationUIAutomaticKeys()
    let available = LocalizationUIAvailableKeys()
    let blue = LocalizationUIBlueKeys()
    let both = LocalizationUIBothKeys()
    let browse = LocalizationUIBrowseKeys()
    let bulk = LocalizationUIBulkKeys()
    let cancel = LocalizationUICancelKeys()
    let canceled = LocalizationUICanceledKeys()
    let canceling = LocalizationUICancelingKeys()
    let certificate = LocalizationUICertificateKeys()
    let change = LocalizationUIChangeKeys()
    let changed = LocalizationUIChangedKeys()
    let changes = LocalizationUIChangesKeys()
    let check = LocalizationUICheckKeys()
    let checking = LocalizationUICheckingKeys()
    let checkout = LocalizationUICheckoutKeys()
    let choose = LocalizationUIChooseKeys()
    let clean = LocalizationUICleanKeys()
    let cleaned = LocalizationUICleanedKeys()
    let cleaning = LocalizationUICleaningKeys()
    let cleanup = LocalizationUICleanupKeys()
    let clear = LocalizationUIClearKeys()
    let close = LocalizationUICloseKeys()
    let commit = LocalizationUICommitKeys()
    let committing = LocalizationUICommittingKeys()
    let compare = LocalizationUICompareKeys()
    let configure = LocalizationUIConfigureKeys()
    let confirm = LocalizationUIConfirmKeys()
    let conflict = LocalizationUIConflictKeys()
    let conflicted = LocalizationUIConflictedKeys()
    let content = LocalizationUIContentKeys()
    let coordinated = LocalizationUICoordinatedKeys()
    let copied = LocalizationUICopiedKeys()
    let copy = LocalizationUICopyKeys()
    let could = LocalizationUICouldKeys()
    let credentials = LocalizationUICredentialsKeys()
    let current = LocalizationUICurrentKeys()
    let delete = LocalizationUIDeleteKeys()
    let deleted = LocalizationUIDeletedKeys()
    let destination = LocalizationUIDestinationKeys()
    let diff = LocalizationUIDiffKeys()
    let directory = LocalizationUIDirectoryKeys()
    let discard = LocalizationUIDiscardKeys()
    let document = LocalizationUIDocumentKeys()
    let download = LocalizationUIDownloadKeys()
    let earlier = LocalizationUIEarlierKeys()
    let editing = LocalizationUIEditingKeys()
    let empty = LocalizationUIEmptyKeys()
    let enter = LocalizationUIEnterKeys()
    let error = LocalizationUIErrorKeys()
    let exit = LocalizationUIExitKeys()
    let expired = LocalizationUIExpiredKeys()
    let explicit = LocalizationUIExplicitKeys()
    let explore = LocalizationUIExploreKeys()
    let failed = LocalizationUIFailedKeys()
    let file = LocalizationUIFileKeys()
    let filename = LocalizationUIFilenameKeys()
    let files = LocalizationUIFilesKeys()
    let folder = LocalizationUIFolderKeys()
    let force = LocalizationUIForceKeys()
    let gitignore = LocalizationUIGitignoreKeys()
    let global = LocalizationUIGlobalKeys()
    let go = LocalizationUIGoKeys()
    let hide = LocalizationUIHideKeys()
    let highest = LocalizationUIHighestKeys()
    let history = LocalizationUIHistoryKeys()
    let ignore = LocalizationUIIgnoreKeys()
    let ignored = LocalizationUIIgnoredKeys()
    let include = LocalizationUIIncludeKeys()
    let included = LocalizationUIIncludedKeys()
    let incoming = LocalizationUIIncomingKeys()
    let incomplete = LocalizationUIIncompleteKeys()
    let inherited = LocalizationUIInheritedKeys()
    let invalid = LocalizationUIInvalidKeys()
    let item = LocalizationUIItemKeys()
    let japan = LocalizationUIJapanKeys()
    let keep = LocalizationUIKeepKeys()
    let keychain = LocalizationUIKeychainKeys()
    let korea = LocalizationUIKoreaKeys()
    let language = LocalizationUILanguageKeys()
    let last = LocalizationUILastKeys()
    let later = LocalizationUILaterKeys()
    let leave = LocalizationUILeaveKeys()
    let load = LocalizationUILoadKeys()
    let loading = LocalizationUILoadingKeys()
    let local = LocalizationUILocalKeys()
    let localizationContinue = LocalizationUILocalizationcontinueKeys()
    let localizationDo = LocalizationUILocalizationdoKeys()
    let localizationFalse = LocalizationUILocalizationfalseKeys()
    let localizationImport = LocalizationUILocalizationimportKeys()
    let localizationOpen = LocalizationUILocalizationopenKeys()
    let localizationTry = LocalizationUILocalizationtryKeys()
    let locally = LocalizationUILocallyKeys()
    let lock = LocalizationUILockKeys()
    let locked = LocalizationUILockedKeys()
    let locking = LocalizationUILockingKeys()
    let locks = LocalizationUILocksKeys()
    let mac = LocalizationUIMacKeys()
    let manage = LocalizationUIManageKeys()
    let mark = LocalizationUIMarkKeys()
    let marked = LocalizationUIMarkedKeys()
    let mixed = LocalizationUIMixedKeys()
    let modification = LocalizationUIModificationKeys()
    let modified = LocalizationUIModifiedKeys()
    let move = LocalizationUIMoveKeys()
    let multiple = LocalizationUIMultipleKeys()
    let my = LocalizationUIMyKeys()
    let need = LocalizationUINeedKeys()
    let needs = LocalizationUINeedsKeys()
    let new = LocalizationUINewKeys()
    let no = LocalizationUINoKeys()
    let not = LocalizationUINotKeys()
    let obstructed = LocalizationUIObstructedKeys()
    let on = LocalizationUIOnKeys()
    let only = LocalizationUIOnlyKeys()
    let opened = LocalizationUIOpenedKeys()
    let opening = LocalizationUIOpeningKeys()
    let operation = LocalizationUIOperationKeys()
    let original = LocalizationUIOriginalKeys()
    let overwrite = LocalizationUIOverwriteKeys()
    let parent = LocalizationUIParentKeys()
    let password = LocalizationUIPasswordKeys()
    let path = LocalizationUIPathKeys()
    let pending = LocalizationUIPendingKeys()
    let pick = LocalizationUIPickKeys()
    let please = LocalizationUIPleaseKeys()
    let press = LocalizationUIPressKeys()
    let preview = LocalizationUIPreviewKeys()
    let properties = LocalizationUIPropertiesKeys()
    let property = LocalizationUIPropertyKeys()
    let questions = LocalizationUIQuestionsKeys()
    let recover = LocalizationUIRecoverKeys()
    let recovery = LocalizationUIRecoveryKeys()
    let refresh = LocalizationUIRefreshKeys()
    let refreshed = LocalizationUIRefreshedKeys()
    let register = LocalizationUIRegisterKeys()
    let release = LocalizationUIReleaseKeys()
    let reload = LocalizationUIReloadKeys()
    let relocate = LocalizationUIRelocateKeys()
    let relocating = LocalizationUIRelocatingKeys()
    let remove = LocalizationUIRemoveKeys()
    let removed = LocalizationUIRemovedKeys()
    let rename = LocalizationUIRenameKeys()
    let replace = LocalizationUIReplaceKeys()
    let replaced = LocalizationUIReplacedKeys()
    let repository = LocalizationUIRepositoryKeys()
    let resolve = LocalizationUIResolveKeys()
    let resolving = LocalizationUIResolvingKeys()
    let restore = LocalizationUIRestoreKeys()
    let restored = LocalizationUIRestoredKeys()
    let restoring = LocalizationUIRestoringKeys()
    let reveal = LocalizationUIRevealKeys()
    let revert = LocalizationUIRevertKeys()
    let reverted = LocalizationUIRevertedKeys()
    let review = LocalizationUIReviewKeys()
    let revision = LocalizationUIRevisionKeys()
    let run = LocalizationUIRunKeys()
    let save = LocalizationUISaveKeys()
    let saved = LocalizationUISavedKeys()
    let saving = LocalizationUISavingKeys()
    let search = LocalizationUISearchKeys()
    let secure = LocalizationUISecureKeys()
    let select = LocalizationUISelectKeys()
    let selected = LocalizationUISelectedKeys()
    let send = LocalizationUISendKeys()
    let server = LocalizationUIServerKeys()
    let settings = LocalizationUISettingsKeys()
    let show = LocalizationUIShowKeys()
    let showing = LocalizationUIShowingKeys()
    let shows = LocalizationUIShowsKeys()
    let source = LocalizationUISourceKeys()
    let stop = LocalizationUIStopKeys()
    let svn = LocalizationUISvnKeys()
    let switched = LocalizationUISwitchedKeys()
    let symbolic = LocalizationUISymbolicKeys()
    let temporary = LocalizationUITemporaryKeys()
    let the = LocalizationUITheKeys()
    let there = LocalizationUIThereKeys()
    let this = LocalizationUIThisKeys()
    let tree = LocalizationUITreeKeys()
    let uk = LocalizationUIUkKeys()
    let unable = LocalizationUIUnableKeys()
    let uncommitted = LocalizationUIUncommittedKeys()
    let unicode = LocalizationUIUnicodeKeys()
    let unknown = LocalizationUIUnknownKeys()
    let unsupported = LocalizationUIUnsupportedKeys()
    let unversioned = LocalizationUIUnversionedKeys()
    let up = LocalizationUIUpKeys()
    let update = LocalizationUIUpdateKeys()
    let updating = LocalizationUIUpdatingKeys()
    let us = LocalizationUIUsKeys()
    let use = LocalizationUIUseKeys()
    let username = LocalizationUIUsernameKeys()
    let version = LocalizationUIVersionKeys()
    let versioned = LocalizationUIVersionedKeys()
    let view = LocalizationUIViewKeys()
    let when = LocalizationUIWhenKeys()
    let working = LocalizationUIWorkingKeys()
    let yes = LocalizationUIYesKeys()
    let you = LocalizationUIYouKeys()
    let your = LocalizationUIYourKeys()
}

struct LocalizationUIAKeys {
    let cleanWorkingCopyIsCheckedOutFromTheSer = LocalizationKey("ui.a.clean.working.copy.is.checked.out.from.the.ser.a49ce026")
    let conflictFilePathPointsOutsideTheWorking = LocalizationKey("ui.a.conflict.file.path.points.outside.the.working..137a7ed6")
    let lockedFileIsMarkedOnTheSvnServerToPre = LocalizationKey("ui.a.locked.file.is.marked.on.the.svn.server.to.pre.d248a309")
    let passwordForThisFolderIsStoredInMacosKe = LocalizationKey("ui.a.password.for.this.folder.is.stored.in.macos.ke.676ba875")
}

struct LocalizationUIAboutKeys {
    let svnKr = LocalizationKey("ui.about.svn.kr.ddc63e52")
}

struct LocalizationUIAddKeys {
    let aLocalWorkingFolder = LocalizationKey("ui.add.a.local.working.folder.816116ca")
    let repositoryTemporaryFileCleanupCommit = LocalizationKey("ui.add.repository.temporary.file.cleanup.commit.a19da94a")
    let svnRepository = LocalizationKey("ui.add.svn.repository.8b9639fa")
}

struct LocalizationUIAddedKeys {
    let ignoreRuleCommitTheDirectoryProperty = LocalizationKey("ui.added.ignore.rule.commit.the.directory.property..42754ee1")
    let label = LocalizationKey("ui.added.0dce7328")
}

struct LocalizationUIAdditionalKeys {
    let revisionProperties = LocalizationKey("ui.additional.revision.properties.ab3e5f0b")
}

struct LocalizationUIAffectedKeys {
    let label = LocalizationKey("ui.affected.dbd64ef9")
}

struct LocalizationUIAfterKeys {
    let reviewingBothBackupsKeepTheContentCu = LocalizationKey("ui.after.reviewing.both.backups.keep.the.content.cu.94842c30")
    let updateVerifyCandidatesThenReviewAndC = LocalizationKey("ui.after.update.verify.candidates.then.review.and.c.89b37719")
}

struct LocalizationUIAllKeys {
    let selectedFilesAlreadyLockedByYou = LocalizationKey("ui.all.selected.files.already.locked.by.you.6a91cd42")
}

struct LocalizationUIAllowKeys {
    let certificateFailureForProject = LocalizationKey("ui.allow.certificate.failure.for.project.0d91bc52")
    let selfSignedAndCertificateNameMismatch = LocalizationKey("ui.allow.self.signed.and.certificate.name.mismatch..0bfb9514")
    let untrustedSslCertificates = LocalizationKey("ui.allow.untrusted.ssl.certificates.78b94750")
}

struct LocalizationUIAlreadyKeys {
    let versionedFilesAreNotHiddenByIgnore = LocalizationKey("ui.already.versioned.files.are.not.hidden.by.ignore.ed1d7db7")
}

struct LocalizationUIAlwaysKeys {
    let lockAndOpenDocuments = LocalizationKey("ui.always.lock.and.open.documents.2f9a7c11")
    let openDocumentsWithoutLocking = LocalizationKey("ui.always.open.documents.without.locking.8b6e42d0")
}

struct LocalizationUIAnKeys {
    let updateIsAvailable = LocalizationKey("ui.an.update.is.available.f3c3a4e9")
}

struct LocalizationUIAndKeys {
    let moreItemsCount = LocalizationKey("ui.and.more.items.count.a5d20f16")
}

struct LocalizationUIAppliedKeys {
    let gitRuleSToSvnIgnorePropertiesComm = LocalizationKey("ui.applied.git.rule.s.to.svn.ignore.properties.comm.2cfe91aa")
    let label = LocalizationKey("ui.applied.faddeb33")
}

struct LocalizationUIApplyKeys {
    let globalIgnoreRules = LocalizationKey("ui.apply.global.ignore.rules.1ece4ab2")
    let label = LocalizationKey("ui.apply.aa6f48d5")
    let selectedRules = LocalizationKey("ui.apply.selected.rules.f6bb01fa")
    let serverProperties = LocalizationKey("ui.apply.server.properties.51ad840e")
    let serverVersion = LocalizationKey("ui.apply.server.version.61c5a01e")
}

struct LocalizationUIApplyingKeys {
    let label = LocalizationKey("ui.applying.8c4d1e05")
}

struct LocalizationUIAskKeys {
    let everyTimeBeforeOpeningDocuments = LocalizationKey("ui.ask.every.time.before.opening.documents.31c4d8a2")
}

struct LocalizationUIAuthenticationKeys {
    let isRequiredToCommitTheSelecte = LocalizationKey("ui.authentication.is.required.to.commit.the.selecte.4837ef80")
    let isRequiredToDownloadTheLates = LocalizationKey("ui.authentication.is.required.to.download.the.lates.83127c9a")
    let isRequiredToLoadTheLatestSe = LocalizationKey("ui.authentication.is.required.to.load.the.latest.se.2b552fac")
    let usesTheExistingSvnCredential = LocalizationKey("ui.authentication.uses.the.existing.svn.credential..b6c6fe66")
    let wasCanceledLocalChangesRemain = LocalizationKey("ui.authentication.was.canceled.local.changes.remain.c4984bab")
}

struct LocalizationUIAutomaticKeys {
    let unicodePathRecovery = LocalizationKey("ui.automatic.unicode.path.recovery.e71b00a0")
}

struct LocalizationUIAvailableKeys {
    let label = LocalizationKey("ui.available.cb60f347")
}

struct LocalizationUIBlueKeys {
    let dotsAreServerCommitsTheGreenRingIsYBase = LocalizationKey("ui.blue.dots.are.server.commits.the.green.ring.is.y.486b468b")
    let dotsAreServerCommitsTheGreenRingIsYHighestRevision = LocalizationKey("ui.blue.dots.are.server.commits.the.green.ring.is.y.fb1c8ff5")
}

struct LocalizationUIBothKeys {
    let versionsWereCopiedToABackupFolderEdi = LocalizationKey("ui.both.versions.were.copied.to.a.backup.folder.edi.259e47d5")
}

struct LocalizationUIBrowseKeys {
    let label = LocalizationKey("ui.browse.5f8b6e21")
    let repository = LocalizationKey("ui.browse.repository.6f2a9c41")
    let repositoryBeforeCheckout = LocalizationKey("ui.browse.repository.before.checkout.7c2e1b84")
    let sampleProject = LocalizationKey("ui.browse.sample.project.9ad211da")
    let svnRepository = LocalizationKey("ui.browse.svn.repository.4a9d3c10")
}

struct LocalizationUIBulkKeys {
    let unlockCompleted = LocalizationKey("ui.bulk.unlock.completed.4b7e0ad3")
    let unlockConfirmationDetails = LocalizationKey("ui.bulk.unlock.confirmation.details.8c20fd61")
    let unlockConfirmationTitle = LocalizationKey("ui.bulk.unlock.confirmation.title.a4e70c92")
    let unlockPartialFailureDetails = LocalizationKey("ui.bulk.unlock.partial.failure.details.71a6c5e8")
    let unlockPartialFailureTitle = LocalizationKey("ui.bulk.unlock.partial.failure.title.3be91d76")
}

struct LocalizationUICancelKeys {
    let addingTheRepositoryAndCloseThisWind = LocalizationKey("ui.cancel.adding.the.repository.and.close.this.wind.113063d1")
    let deletionAndRestore = LocalizationKey("ui.cancel.deletion.and.restore.ce07fc64")
    let label = LocalizationKey("ui.cancel.a2ce2c22")
    let theRepositoryDeletionStateForAndRes = LocalizationKey("ui.cancel.the.repository.deletion.state.for.and.res.fe2dce5e")
}

struct LocalizationUICanceledKeys {
    let checkoutFolderEmptied = LocalizationKey("ui.canceled.checkout.folder.emptied.b08f7c21")
    let checkoutFolderNotEmptied = LocalizationKey("ui.canceled.checkout.folder.not.emptied.9ea1354b")
}

struct LocalizationUICancelingKeys {
    let doesNotPreventViewingLocalChanges = LocalizationKey("ui.canceling.does.not.prevent.viewing.local.changes.cf7ece9c")
}

struct LocalizationUICertificateKeys {
    let exceptionNotAllowed = LocalizationKey("ui.certificate.exception.not.allowed.d47c92a1")
    let exceptionSavedForProject = LocalizationKey("ui.certificate.exception.saved.for.project.16e0ad73")
    let exceptionSecurityWarning = LocalizationKey("ui.certificate.exception.security.warning.b82d4a16")
    let expiredGuidance = LocalizationKey("ui.certificate.expired.guidance.a83d5e91")
    let nameMismatchGuidance = LocalizationKey("ui.certificate.name.mismatch.guidance.74c11a2b")
    let notYetValidGuidance = LocalizationKey("ui.certificate.not.yet.valid.guidance.5fb1c4d8")
    let unclassifiedGuidance = LocalizationKey("ui.certificate.unclassified.guidance.c1974a30")
    let unknownCaGuidance = LocalizationKey("ui.certificate.unknown.ca.guidance.39a72e10")
}

struct LocalizationUIChangeKeys {
    let label = LocalizationKey("ui.change.7c3aa7d1")
    let repositoryLocation = LocalizationKey("ui.change.repository.location.8b21c7e4")
    let thisFolderSLocationSvnAccountAndK = LocalizationKey("ui.change.this.folder.s.location.svn.account.and.k.5b3e9d20")
}

struct LocalizationUIChangedKeys {
    let paths = LocalizationKey("ui.changed.paths.89badc04")
}

struct LocalizationUIChangesKeys {
    let label = LocalizationKey("ui.changes.0e19f519")
}

struct LocalizationUICheckKeys {
    let forUpdatesAction = LocalizationKey("ui.check.for.updates.6ba78913")
    let forUpdatesSecondary = LocalizationKey("ui.check.for.updates.d0ccb7fe")
    let outANewSvnRepositoryOrRegisterAnEx = LocalizationKey("ui.check.out.a.new.svn.repository.or.register.an.ex.2b1e2b00")
    let outARepositoryUrlAndAddItToYourLo = LocalizationKey("ui.check.out.a.repository.url.and.add.it.to.your.lo.63f0d7ea")
    let outAndAdd = LocalizationKey("ui.check.out.and.add.ec5e3d09")
    let outRepositoryUrl = LocalizationKey("ui.check.out.repository.url.6cbf366d")
    let outTheSvnRepositoryIntoTheLocalFold = LocalizationKey("ui.check.out.the.svn.repository.into.the.local.fold.4323a8e0")
    let theAppStoreForTheLatestVersion = LocalizationKey("ui.check.the.app.store.for.the.latest.version.969078c0")
}

struct LocalizationUICheckingKeys {
    let forUpdates = LocalizationKey("ui.checking.for.updates.967c32b4")
    let incomingChanges = LocalizationKey("ui.checking.incoming.changes.a7a217e2")
    let out = LocalizationKey("ui.checking.out.3944eb2e")
    let theAccount = LocalizationKey("ui.checking.the.account.c47f1a90")
}

struct LocalizationUICheckoutKeys {
    let completedButThePasswordCouldNotBe = LocalizationKey("ui.checkout.completed.but.the.password.could.not.be.ed5274e5")
    let folderWasNotEmptyCannotDelete = LocalizationKey("ui.checkout.folder.was.not.empty.cannot.delete.0e6d49b2")
    let progressLog = LocalizationKey("ui.checkout.progress.log.ba2c92de")
    let recoveryValidationFailed = LocalizationKey("ui.checkout.recovery.validation.failed.5fd4218c")
    let wasInterrupted = LocalizationKey("ui.checkout.was.interrupted.9d8a23c0")
}

struct LocalizationUIChooseKeys {
    let aChangedFileAboveToDisplayOnlyThat = LocalizationKey("ui.choose.a.changed.file.above.to.display.only.that.7d44100e")
    let aLocalFolderForTheCheckout = LocalizationKey("ui.choose.a.local.folder.for.the.checkout.de1fb4ce")
    let action = LocalizationKey("ui.choose.action.60c39cbd")
    let anEmptyFolder = LocalizationKey("ui.choose.an.empty.folder.8f9acb6e")
    let anEmptyRecoveryFolder = LocalizationKey("ui.choose.an.empty.recovery.folder.c2b4a175")
    let fileBrowserViewMode = LocalizationKey("ui.choose.file.browser.view.mode.2c78a451")
    let folder = LocalizationKey("ui.choose.folder.54647179")
    let labelAction = LocalizationKey("ui.choose.71d0de8d")
    let labelPrimary = LocalizationKey("ui.choose.0a13aec8")
    let localCheckoutFolder = LocalizationKey("ui.choose.local.checkout.folder.c649aa9f")
    let svnLocalWorkingFolders = LocalizationKey("ui.choose.svn.local.working.folders.6d104bc9")
    let theLanguageUsedInTheAppInterface = LocalizationKey("ui.choose.the.language.used.in.the.app.interface.16c2f863")
    let theLocalFolderForTheCheckout = LocalizationKey("ui.choose.the.local.folder.for.the.checkout.31ee0035")
    let theTimeZoneUsedForCommitDatesAndT = LocalizationKey("ui.choose.the.time.zone.used.for.commit.dates.and.t.ded46b04")
    let viewChangesInTheHistoryToDisplayTh = LocalizationKey("ui.choose.view.changes.in.the.history.to.display.th.cc60739e")
}

struct LocalizationUICleanKeys {
    let upEquivalentPath = LocalizationKey("ui.clean.up.equivalent.path.11fce14e")
}

struct LocalizationUICleanedKeys {
    let repositoryTemporaryFiles = LocalizationKey("ui.cleaned.repository.temporary.files.75d9479a")
}

struct LocalizationUICleaningKeys {
    let andCommitting = LocalizationKey("ui.cleaning.and.committing.6578bec9")
    let andContinuingCheckout = LocalizationKey("ui.cleaning.and.continuing.checkout.18fa2d6b")
    let workingCopy = LocalizationKey("ui.cleaning.working.copy.2a9ed647")
}

struct LocalizationUICleanupKeys {
    let commitFailedUpdateSucceeded = LocalizationKey("ui.cleanup.commit.failed.update.succeeded.f59c27fb")
    let couldNotStartUpdateSucceeded = LocalizationKey("ui.cleanup.could.not.start.update.succeeded.bfae6b76")
    let interruptedWorkingCopyManually = LocalizationKey("ui.cleanup.interrupted.working.copy.manually.46d93c1e")
    let needed = LocalizationKey("ui.cleanup.needed.3c5f4e64")
    let reasonFileMissing = LocalizationKey("ui.cleanup.reason.file.missing.64ae4838")
    let reasonInvalidAppledoubleSignature = LocalizationKey("ui.cleanup.reason.invalid.appledouble.signature.96cdf550")
    let reasonInvalidDsStoreSignature = LocalizationKey("ui.cleanup.reason.invalid.ds.store.signature.2832697d")
    let reasonLockedBy = LocalizationKey("ui.cleanup.reason.locked.by.5ee975b0")
    let reasonNotRegularFile = LocalizationKey("ui.cleanup.reason.not.regular.file.98aa0f60")
    let reasonOfficeLockTooLarge = LocalizationKey("ui.cleanup.reason.office.lock.too.large.38b4ef17")
    let reasonSymbolicLink = LocalizationKey("ui.cleanup.reason.symbolic.link.95821786")
    let reasonUnreadable = LocalizationKey("ui.cleanup.reason.unreadable.85df36fb")
    let reasonUnsafePath = LocalizationKey("ui.cleanup.reason.unsafe.path.5dce44a1")
    let someItemsFailed = LocalizationKey("ui.cleanup.some.items.failed.2bdf30af")
}

struct LocalizationUIClearKeys {
    let allSelectedCommitTargets = LocalizationKey("ui.clear.all.selected.commit.targets.605665f6")
    let label = LocalizationKey("ui.clear.8cfe548b")
    let selection = LocalizationKey("ui.clear.selection.6520660b")
}

struct LocalizationUICloseKeys {
    let label = LocalizationKey("ui.close.3ea43db3")
    let theSampleProjectAndReturnToNormalMo = LocalizationKey("ui.close.the.sample.project.and.return.to.normal.mo.6d61e364")
    let withoutSavingCredentialChanges = LocalizationKey("ui.close.without.saving.credential.changes.97c00986")
}

struct LocalizationUICommitKeys {
    let changes = LocalizationKey("ui.commit.changes.79414e6d")
    let deletionRestorePartial = LocalizationKey("ui.commit.deletion.restore.partial.5a8c2f64")
    let history = LocalizationKey("ui.commit.history.07e0f8de")
    let historyTimeZone = LocalizationKey("ui.commit.history.time.zone.9e3260bf")
    let inputSavedUpdateThenRetry = LocalizationKey("ui.commit.input.saved.update.then.retry.5e2a8d90")
    let message = LocalizationKey("ui.commit.message.c5139167")
    let notFound = LocalizationKey("ui.commit.not.found.0f4a8385")
    let requiresUpdateBeforeRetry = LocalizationKey("ui.commit.requires.update.before.retry.91b7e3c5")
    let selected = LocalizationKey("ui.commit.selected.29bc2086")
    let theSelectedFilesToTheSvnServerWith = LocalizationKey("ui.commit.the.selected.files.to.the.svn.server.with.8046c0f8")
    let timeUnavailable = LocalizationKey("ui.commit.time.unavailable.59140fc5")
    let withoutAMessage = LocalizationKey("ui.commit.without.a.message.6f0f2d41")
}

struct LocalizationUICommittingKeys {
    let label = LocalizationKey("ui.committing.0e8ec0f4")
}

struct LocalizationUICompareKeys {
    let gitRules = LocalizationKey("ui.compare.git.rules.2220d6b1")
}

struct LocalizationUIConfigureKeys {
    let theSvnAccountAndKeychainPassword = LocalizationKey("ui.configure.the.svn.account.and.keychain.password..daa54ac3")
}

struct LocalizationUIConfirmKeys {
    let commit = LocalizationKey("ui.confirm.commit.7c2e5a90")
    let currentWorkingCopyState = LocalizationKey("ui.confirm.current.working.copy.state.1c63f80b")
    let manuallyEditedContent = LocalizationKey("ui.confirm.manually.edited.content.97e30ac4")
    let repositoryRelocation = LocalizationKey("ui.confirm.repository.relocation.0c9d6e73")
}

struct LocalizationUIConflictKeys {
    let backupsMustBeStoredOutsideTheWork = LocalizationKey("ui.conflict.backups.must.be.stored.outside.the.work.b1ccd27c")
    let label = LocalizationKey("ui.conflict.37edb628")
}

struct LocalizationUIConflictedKeys {
    let properties = LocalizationKey("ui.conflicted.properties.849bf370")
    let propertyNameUnavailable = LocalizationKey("ui.conflicted.property.name.unavailable.0cc5d784")
}

struct LocalizationUIContentKeys {
    let andPropertyConflictTogether = LocalizationKey("ui.content.and.property.conflict.together.6f0b83e5")
    let changed = LocalizationKey("ui.content.changed.cb88d56c")
}

struct LocalizationUICoordinatedKeys {
    let universalTimeUtc = LocalizationKey("ui.coordinated.universal.time.utc.0b7fc6d7")
}

struct LocalizationUICopiedKeys {
    let label = LocalizationKey("ui.copied.13a93949")
    let theFilePath = LocalizationKey("ui.copied.the.file.path.5029ec9d")
}

struct LocalizationUICopyKeys {
    let allDisplayedErrorDetailsToTheClipboar = LocalizationKey("ui.copy.all.displayed.error.details.to.the.clipboar.717f18da")
    let currentRepositoryUrl = LocalizationKey("ui.copy.current.repository.url.82c5d1f0")
    let errorDetails = LocalizationKey("ui.copy.error.details.7de3d319")
    let fullPath = LocalizationKey("ui.copy.full.path.823e26e7")
    let withHistory = LocalizationKey("ui.copy.with.history.5f0d3b82")
}

struct LocalizationUICouldKeys {
    let notOpenTheFile = LocalizationKey("ui.could.not.open.the.file.263874fa")
}

struct LocalizationUICredentialsKeys {
    let label = LocalizationKey("ui.credentials.97a976d9")
    let savedFor = LocalizationKey("ui.credentials.saved.for.409bff39")
}

struct LocalizationUICurrentKeys {
    let repositoryUrl = LocalizationKey("ui.current.repository.url.1a6f43d2")
    let workingFile = LocalizationKey("ui.current.working.file.669bd1d9")
}

struct LocalizationUIDeleteKeys {
    let andCommitCleanup = LocalizationKey("ui.delete.and.commit.cleanup.146a3cd1")
    let fromRepository = LocalizationKey("ui.delete.from.repository.deb8c2a7")
    let missingItems = LocalizationKey("ui.delete.missing.items.ab0ea8fc")
    let savedPassword = LocalizationKey("ui.delete.saved.password.a38fa5cf")
    let theSvnPasswordStoredInKeychainForT = LocalizationKey("ui.delete.the.svn.password.stored.in.keychain.for.t.e0944666")
}

struct LocalizationUIDeletedKeys {
    let label = LocalizationKey("ui.deleted.6826dd28")
}

struct LocalizationUIDestinationKeys {
    let alreadyExists = LocalizationKey("ui.destination.already.exists.5c0e71b4")
    let matchesSource = LocalizationKey("ui.destination.matches.source.2d9a64f1")
}

struct LocalizationUIDiffKeys {
    let isUnavailableUntilThisFileIsAddedTo = LocalizationKey("ui.diff.is.unavailable.until.this.file.is.added.to..402fbfa5")
}

struct LocalizationUIDirectoryKeys {
    let label = LocalizationKey("ui.directory.9e3f2a70")
}

struct LocalizationUIDiscardKeys {
    let changesAndClose = LocalizationKey("ui.discard.changes.and.close.4e12b8a7")
    let localChangeAndRestoreServerFile = LocalizationKey("ui.discard.local.change.and.restore.server.file.728e0bf1")
}

struct LocalizationUIDocumentKeys {
    let openingMethod = LocalizationKey("ui.document.opening.method.9d73be41")
}

struct LocalizationUIDownloadKeys {
    let theLatestServerChangesIntoTheCurr = LocalizationKey("ui.download.the.latest.server.changes.into.the.curr.17974067")
}

struct LocalizationUIEarlierKeys {
    let history = LocalizationKey("ui.earlier.history.da5e45b0")
}

struct LocalizationUIEditingKeys {
    let documentInSvnKr = LocalizationKey("ui.editing.document.in.svn.kr.5e6ac9cc")
}

struct LocalizationUIEmptyKeys {
    let canceledCheckoutFolderConfirmation = LocalizationKey("ui.empty.canceled.checkout.folder.confirmation.6e12c9ad")
    let checkoutFolder = LocalizationKey("ui.empty.checkout.folder.7a1c8e53")
    let folderDestructive = LocalizationKey("ui.empty.folder.destructive.30d295e8")
}

struct LocalizationUIEnterKeys {
    let password = LocalizationKey("ui.enter.password.48ff7123")
    let repositoryUrlToBrowse = LocalizationKey("ui.enter.repository.url.to.browse.3f6a9d20")
    let validCredentials = LocalizationKey("ui.enter.valid.credentials.9a70c5b2")
}

struct LocalizationUIErrorKeys {
    let label = LocalizationKey("ui.error.a08d7e0d")
}

struct LocalizationUIExitKeys {
    let demo = LocalizationKey("ui.exit.demo.3a329c52")
}

struct LocalizationUIExpiredKeys {
    let andNotYetValidRequireSeparateConsent = LocalizationKey("ui.expired.and.not.yet.valid.require.separate.consent.93ab71e4")
}

struct LocalizationUIExplicitKeys {
    let lockCompleted = LocalizationKey("ui.explicit.lock.completed.1c4f8e72")
}

struct LocalizationUIExploreKeys {
    let theMainFeaturesWithSampleDataAndN = LocalizationKey("ui.explore.the.main.features.with.sample.data.and.n.fd16edf5")
}

struct LocalizationUIFailedKeys {
    let label = LocalizationKey("ui.failed.cb475070")
    let toRemoveAnIncompleteConflictBackup = LocalizationKey("ui.failed.to.remove.an.incomplete.conflict.backup.65753038")
}

struct LocalizationUIFileKeys {
    let actionCommitRequired = LocalizationKey("ui.file.action.commit.required.6c2b9e14")
    let browserActions = LocalizationKey("ui.file.browser.actions.14f5c2a1")
    let browserItemsCount = LocalizationKey("ui.file.browser.items.count.86dc65fe")
    let browserKindColumn = LocalizationKey("ui.file.browser.kind.column.b51d25fc")
    let browserModifiedColumn = LocalizationKey("ui.file.browser.modified.column.84d3d7f2")
    let browserNameColumn = LocalizationKey("ui.file.browser.name.column.0d7638cb")
    let browserSizeColumn = LocalizationKey("ui.file.browser.size.column.a6810d75")
    let browserSplitView = LocalizationKey("ui.file.browser.split.view.6f8e13d2")
    let browserTreeView = LocalizationKey("ui.file.browser.tree.view.4a29bf3c")
    let browserWorkingCopyRoot = LocalizationKey("ui.file.browser.working.copy.root.731fa805")
    let commitHistoryFileCommitHistory = LocalizationKey("ui.file.commit.history.342bfaac")
    let commitHistoryFileCommitHistory2 = LocalizationKey("ui.file.commit.history.ab024244")
    let labelFile = LocalizationKey("ui.file.6d4b8c21")
    let labelFile2 = LocalizationKey("ui.file.811b7680")
    let remainsInConflictResolveBeforeRetry = LocalizationKey("ui.file.remains.in.conflict.resolve.before.retry.4d17ac82")
}

struct LocalizationUIFilenameKeys {
    let warning = LocalizationKey("ui.filename.warning.52af346c")
}

struct LocalizationUIFilesKeys {
    let beingDownloadedWillAppearHereAfterCh = LocalizationKey("ui.files.being.downloaded.will.appear.here.after.ch.9dfb3816")
    let insideThisFolderWillBeAddedTogether = LocalizationKey("ui.files.inside.this.folder.will.be.added.together.637444b8")
    let label = LocalizationKey("ui.files.6075adef")
    let notInRepositoryCount = LocalizationKey("ui.files.not.in.repository.count.2b7fa508")
}

struct LocalizationUIFolderKeys {
    let credentials = LocalizationKey("ui.folder.credentials.b4bd68eb")
    let label = LocalizationKey("ui.folder.e6474408")
    let settings = LocalizationKey("ui.folder.settings.6f2a0d43")
}

struct LocalizationUIForceKeys {
    let lockClientUnavailable = LocalizationKey("ui.force.lock.client.unavailable.72be3a10")
    let lockConfirmationAction = LocalizationKey("ui.force.lock.confirmation.action.9d6a31f0")
    let lockConfirmationDetails = LocalizationKey("ui.force.lock.confirmation.details.27fb4d91")
    let lockConfirmationTitle = LocalizationKey("ui.force.lock.confirmation.title.e83c5a14")
    let releaseLock = LocalizationKey("ui.force.release.lock.a4ef2d91")
    let releaseRepositoryLock = LocalizationKey("ui.force.release.repository.lock.31d7f2c4")
    let unlockDetailsOwnerTimeCommentOriginal = LocalizationKey("ui.force.unlock.details.owner.time.comment.original.93c28fb0")
}

struct LocalizationUIGitignoreKeys {
    let isNotModifiedImportIsOneWayAnd = LocalizationKey("ui.gitignore.is.not.modified.import.is.one.way.and..544de7a7")
}

struct LocalizationUIGlobalKeys {
    let rulesCanAffectManyDirectoriesBelowT = LocalizationKey("ui.global.rules.can.affect.many.directories.below.t.164333fd")
}

struct LocalizationUIGoKeys {
    let resolveUpdateConflicts = LocalizationKey("ui.go.resolve.update.conflicts.2d9e4b71")
}

struct LocalizationUIHideKeys {
    let macOfficeTemporaryFiles = LocalizationKey("ui.hide.mac.office.temporary.files.875f35d1")
    let password = LocalizationKey("ui.hide.password.4c8a1f60")
    let temporaryFilesFromChangesAndCommitTarg = LocalizationKey("ui.hide.temporary.files.from.changes.and.commit.targ.48a925d4")
}

struct LocalizationUIHighestKeys {
    let localRevision = LocalizationKey("ui.highest.local.revision.d334c9c1")
}

struct LocalizationUIHistoryKeys {
    let refreshed = LocalizationKey("ui.history.refreshed.5c159ee8")
}

struct LocalizationUIIgnoreKeys {
    let thisExtension = LocalizationKey("ui.ignore.this.extension.687c5df7")
    let thisItem = LocalizationKey("ui.ignore.this.item.67c56906")
}

struct LocalizationUIIgnoredKeys {
    let label = LocalizationKey("ui.ignored.b45ee0ef")
}

struct LocalizationUIIncludeKeys {
    let inCommit = LocalizationKey("ui.include.in.commit.2aaaa224")
    let inRestore = LocalizationKey("ui.include.in.restore.4d9c1e72")
    let orExcludeThisFileFromTheNextCommi = LocalizationKey("ui.include.or.exclude.this.file.from.the.next.commi.273bb38e")
}

struct LocalizationUIIncludedKeys {
    let locally = LocalizationKey("ui.included.locally.241cf38b")
}

struct LocalizationUIIncomingKeys {
    let changesThatOverlapLocalEditsMayCr = LocalizationKey("ui.incoming.changes.that.overlap.local.edits.may.cr.a2bc4e0e")
}

struct LocalizationUIIncompleteKeys {
    let checkoutRecoveryOptions = LocalizationKey("ui.incomplete.checkout.recovery.options.f31ea907")
    let updateRequired = LocalizationKey("ui.incomplete.update.required.c5e83d20")
}

struct LocalizationUIInheritedKeys {
    let from = LocalizationKey("ui.inherited.from.1feb128b")
    let rulesCanOnlyBeRemovedFromThePar = LocalizationKey("ui.inherited.rules.can.only.be.removed.from.the.par.276c450b")
}

struct LocalizationUIInvalidKeys {
    let fileName = LocalizationKey("ui.invalid.file.name.7b2d10e9")
    let repositoryUrl = LocalizationKey("ui.invalid.repository.url.8e4c1a70")
}

struct LocalizationUIItemKeys {
    let s = LocalizationKey("ui.item.s.7cb28e2a")
}

struct LocalizationUIJapanKeys {
    let standardTimeJstUtc9 = LocalizationKey("ui.japan.standard.time.jst.utc.9.04744dfc")
}

struct LocalizationUIKeepKeys {
    let downloading = LocalizationKey("ui.keep.downloading.3c1de80f")
    let localPropertiesAsResolvedValues = LocalizationKey("ui.keep.local.properties.as.resolved.values.4a0d2c6f")
    let myChange = LocalizationKey("ui.keep.my.change.14f3a8c6")
    let myProperties = LocalizationKey("ui.keep.my.properties.68b12ae4")
    let theFileCurrentlySavedInTheWorkingCop = LocalizationKey("ui.keep.the.file.currently.saved.in.the.working.cop.aa08fa30")
    let yourFileALaterCommitWillReplaceTheR = LocalizationKey("ui.keep.your.file.a.later.commit.will.replace.the.r.f576fdeb")
}

struct LocalizationUIKeychainKeys {
    let accessWasDenied = LocalizationKey("ui.keychain.access.was.denied.c1358e6f")
    let accessWasDeniedChooseHowToAuthent = LocalizationKey("ui.keychain.access.was.denied.choose.how.to.authent.0d8d881a")
    let operationFailed = LocalizationKey("ui.keychain.operation.failed.e456386b")
}

struct LocalizationUIKoreaKeys {
    let standardTimeKstUtc9 = LocalizationKey("ui.korea.standard.time.kst.utc.9.74d019be")
}

struct LocalizationUILanguageKeys {
    let label = LocalizationKey("ui.language.8e5b78fb")
}

struct LocalizationUILastKeys {
    let compared = LocalizationKey("ui.last.compared.cbf0bf20")
}

struct LocalizationUILaterKeys {
    let label = LocalizationKey("ui.later.7dd25de4")
}

struct LocalizationUILeaveKeys {
    let blankToKeepTheCurrentPassword = LocalizationKey("ui.leave.blank.to.keep.the.current.password.5f89ccfa")
}

struct LocalizationUILoadKeys {
    let localization50more = LocalizationKey("ui.load.50.more.043526e4")
}

struct LocalizationUILoadingKeys {
    let changes = LocalizationKey("ui.loading.changes.82ffc858")
    let commitHistory = LocalizationKey("ui.loading.commit.history.c445b02a")
    let fileHistory = LocalizationKey("ui.loading.file.history.c6c155f3")
    let files = LocalizationKey("ui.loading.files.a3268fef")
    let label = LocalizationKey("ui.loading.b0a3fd42")
    let repositoryContents = LocalizationKey("ui.loading.repository.contents.5e1c7a84")
    let repositoryLocks = LocalizationKey("ui.loading.repository.locks.3dd2dfdb")
}

struct LocalizationUILocalKeys {
    let changes = LocalizationKey("ui.local.changes.60d75f36")
    let changesArePreserved = LocalizationKey("ui.local.changes.are.preserved.7e12c6a9")
    let changesRefreshed = LocalizationKey("ui.local.changes.refreshed.617acbc6")
    let changesWillBeDiscarded = LocalizationKey("ui.local.changes.will.be.discarded.5e8127cf")
    let deletionWillRemainAndACommitWillDe = LocalizationKey("ui.local.deletion.will.remain.and.a.commit.will.de.837b94a0")
    let folder = LocalizationKey("ui.local.folder.63f176e1")
    let propertyValuesWillBeDiscarded = LocalizationKey("ui.local.property.values.will.be.discarded.f98a7c20")
    let workingFolders = LocalizationKey("ui.local.working.folders.341c44b5")
}

struct LocalizationUILocalizationcontinueKeys {
    let checkout = LocalizationKey("ui.continue.checkout.84b37ce1")
    let incompleteByUpdating = LocalizationKey("ui.continue.incomplete.by.updating.b64e2a19")
    let update = LocalizationKey("ui.continue.update.2ce71b84")
}

struct LocalizationUILocalizationdoKeys {
    let notAllowCertificateException = LocalizationKey("ui.do.not.allow.certificate.exception.f4c01a6e")
}

struct LocalizationUILocalizationfalseKeys {
    let aliasesExcluded = LocalizationKey("ui.false.aliases.excluded.85d448dd")
}

struct LocalizationUILocalizationimportKeys {
    let gitRules = LocalizationKey("ui.import.git.rules.bbf8aa32")
}

struct LocalizationUILocalizationopenKeys {
    let backupFolder = LocalizationKey("ui.open.backup.folder.d8faa2d5")
    let file = LocalizationKey("ui.open.file.ea89b4b3")
    let inFinder = LocalizationKey("ui.open.in.finder.35aa9225")
    let myFile = LocalizationKey("ui.open.my.file.537a87cb")
    let repositoryRelocation = LocalizationKey("ui.open.repository.relocation.9c5e17a3")
    let selectedDirectory = LocalizationKey("ui.open.selected.directory.2c7e5a91")
    let serverFile = LocalizationKey("ui.open.server.file.252d515b")
    let theAppWideSettingsWindow = LocalizationKey("ui.open.the.app.wide.settings.window.6b0d5a17")
    let thisSvnLocalWorkingFolderInFinder = LocalizationKey("ui.open.this.svn.local.working.folder.in.finder.9befff0f")
    let withoutLock = LocalizationKey("ui.open.without.lock.e650efbf")
    let withoutLockAndDoNotAskAgain = LocalizationKey("ui.open.without.lock.and.do.not.ask.again.4c6f8a20")
}

struct LocalizationUILocalizationtryKeys {
    let keychainAgain = LocalizationKey("ui.try.keychain.again.a762f607")
    let normalUnlockBeforeForceUnlock = LocalizationKey("ui.try.normal.unlock.before.force.unlock.8a21f763")
}

struct LocalizationUILocallyKeys {
    let missing = LocalizationKey("ui.locally.missing.c4011027")
    let missingActionRequired = LocalizationKey("ui.locally.missing.action.required.50c49ccb")
}

struct LocalizationUILockKeys {
    let andOpen = LocalizationKey("ui.lock.and.open.c64beb29")
    let belongsToAnotherWorkingCopyForceUnlock = LocalizationKey("ui.lock.belongs.to.another.working.copy.force.unlock.27e93bd0")
    let fileExplicitly = LocalizationKey("ui.lock.file.explicitly.45d18c7b")
    let informationCouldNotBeCheckedYouCanOp = LocalizationKey("ui.lock.information.could.not.be.checked.you.can.op.b80b917b")
    let selectedFiles = LocalizationKey("ui.lock.selected.files.7a3e9c21")
    let thisFileBeforeOpening = LocalizationKey("ui.lock.this.file.before.opening.0d16b072")
}

struct LocalizationUILockedKeys {
    let by = LocalizationKey("ui.locked.by.192b78cf")
    let byYou = LocalizationKey("ui.locked.by.you.f2a7c3f2")
    let files = LocalizationKey("ui.locked.files.457daf19")
    let filesBlockOtherUsersUntilCommitOrUnl = LocalizationKey("ui.locked.files.block.other.users.until.commit.or.unl.6a2e91bf")
}

struct LocalizationUILockingKeys {
    let preventsConcurrentCommitsByOtherUse = LocalizationKey("ui.locking.prevents.concurrent.commits.by.other.use.0f657e2c")
}

struct LocalizationUILocksKeys {
    let labelFormatted = LocalizationKey("ui.locks.46e6922e")
    let labelSecondary = LocalizationKey("ui.locks.dac8d38d")
}

struct LocalizationUIMacKeys {
    let systemTimeZone = LocalizationKey("ui.mac.system.time.zone.df3e6992")
}

struct LocalizationUIManageKeys {
    let ignoreRules = LocalizationKey("ui.manage.ignore.rules.7eac76b1")
}

struct LocalizationUIMarkKeys {
    let forDeletion = LocalizationKey("ui.mark.for.deletion.ec31cd20")
    let forRepositoryDeletion = LocalizationKey("ui.mark.for.repository.deletion.3c417fc1")
}

struct LocalizationUIMarkedKeys {
    let itemSForDeletionCommitToDeleteThem = LocalizationKey("ui.marked.item.s.for.deletion.commit.to.delete.them.ac2b38ab")
}

struct LocalizationUIMixedKeys {
    let revisions = LocalizationKey("ui.mixed.revisions.6faee919")
}

struct LocalizationUIModificationKeys {
    let dateUnavailable = LocalizationKey("ui.modification.date.unavailable.7b2ebc97")
}

struct LocalizationUIModifiedKeys {
    let labelFormatted = LocalizationKey("ui.modified.98221376")
    let labelPrimary = LocalizationKey("ui.modified.01365bb2")
}

struct LocalizationUIMoveKeys {
    let orRenameTheLocalFileThenUpdate = LocalizationKey("ui.move.or.rename.the.local.file.then.update.1e3c7a90")
}

struct LocalizationUIMultipleKeys {
    let canonicallyEquivalentServerPathsExi = LocalizationKey("ui.multiple.canonically.equivalent.server.paths.exi.55798f96")
}

struct LocalizationUIMyKeys {
    let file = LocalizationKey("ui.my.file.e70a2b5b")
    let localBase = LocalizationKey("ui.my.local.base.eff15763")
    let localFolderR = LocalizationKey("ui.my.local.folder.r.6668e9b0")
    let propertiesAlsoKept = LocalizationKey("ui.my.properties.also.kept.b81e64af")
}

struct LocalizationUINeedKeys {
    let help = LocalizationKey("ui.need.help.bf7256df")
}

struct LocalizationUINeedsKeys {
    let lockCommitRequired = LocalizationKey("ui.needs.lock.commit.required.4c6e82a1")
    let lockDisable = LocalizationKey("ui.needs.lock.disable.3d8a20f6")
    let lockEnable = LocalizationKey("ui.needs.lock.enable.0b7e4c91")
    let lockEnabled = LocalizationKey("ui.needs.lock.enabled.9a1f5c37")
}

struct LocalizationUINewKeys {
    let fileName = LocalizationKey("ui.new.file.name.8d41e6a0")
    let label = LocalizationKey("ui.new.479ccc40")
    let repositoryUrl = LocalizationKey("ui.new.repository.url.5d4b9f02")
    let workingFolder = LocalizationKey("ui.new.working.folder.5db27c9c")
}

struct LocalizationUINoKeys {
    let changedFiles = LocalizationKey("ui.no.changed.files.27bf2bab")
    let changes = LocalizationKey("ui.no.changes.ea917fd6")
    let commitHistory = LocalizationKey("ui.no.commit.history.a78ed291")
    let commitMessage = LocalizationKey("ui.no.commit.message.911ccc29")
    let fileHistory = LocalizationKey("ui.no.file.history.c4cc1ef1")
    let files = LocalizationKey("ui.no.files.5245ffcc")
    let gitignore = LocalizationKey("ui.no.gitignore.44540a9b")
    let gitignoreFileWasFoundInTheWorkingCopy = LocalizationKey("ui.no.gitignore.file.was.found.in.the.working.copy.ce93a706")
    let incomingChanges = LocalizationKey("ui.no.incoming.changes.8302e8b6")
    let itemsInRepositoryDirectory = LocalizationKey("ui.no.items.in.repository.directory.4d8b1f63")
    let label = LocalizationKey("ui.no.bafd7322")
    let lockedFiles = LocalizationKey("ui.no.locked.files.7d32eee0")
    let passwordIsStored = LocalizationKey("ui.no.password.is.stored.44110abb")
    let searchResults = LocalizationKey("ui.no.search.results.e40b4a06")
    let serverDeletionsRemaining = LocalizationKey("ui.no.server.deletions.remaining.3e7b9a12")
    let svnIgnoreRulesAreConfigured = LocalizationKey("ui.no.svn.ignore.rules.are.configured.71e0180f")
    let textDiffIsAvailableThisMayBeANewOrB = LocalizationKey("ui.no.text.diff.is.available.this.may.be.a.new.or.b.e90ec831")
    let value = LocalizationKey("ui.no.value.480d48f5")
}

struct LocalizationUINotKeys {
    let available = LocalizationKey("ui.not.available.60326cf1")
}

struct LocalizationUIObstructedKeys {
    let localFile = LocalizationKey("ui.obstructed.local.file.74a9c2e5")
}

struct LocalizationUIOnKeys {
    let successBothTheOriginalAndRecoveredCopie = LocalizationKey("ui.on.success.both.the.original.and.recovered.copie.9a6ba4b9")
}

struct LocalizationUIOnlyKeys {
    let verifiedWorkingCopyWillBeDeletedPath = LocalizationKey("ui.only.verified.working.copy.will.be.deleted.path.d8c0a71e")
}

struct LocalizationUIOpenedKeys {
    let withoutALockAConcurrentCommitByAno = LocalizationKey("ui.opened.without.a.lock.a.concurrent.commit.by.ano.ff588344")
}

struct LocalizationUIOpeningKeys {
    let aFileLockedByYou = LocalizationKey("ui.opening.a.file.locked.by.you.742588ff")
}

struct LocalizationUIOperationKeys {
    let wasInterruptedCleanupPrompt = LocalizationKey("ui.operation.was.interrupted.cleanup.prompt.c7f01d92")
}

struct LocalizationUIOriginalKeys {
    let message = LocalizationKey("ui.original.message.fbd14889")
}

struct LocalizationUIOverwriteKeys {
    let withMine = LocalizationKey("ui.overwrite.with.mine.8d42f39b")
}

struct LocalizationUIParentKeys {
    let directory = LocalizationKey("ui.parent.directory.1b7e4a93")
}

struct LocalizationUIPasswordKeys {
    let label = LocalizationKey("ui.password.945c94ed")
}

struct LocalizationUIPathKeys {
    let recoveryCompletedTheOriginalWorkingFol = LocalizationKey("ui.path.recovery.completed.the.original.working.fol.2fde9c42")
}

struct LocalizationUIPendingKeys {
    let deletionFormatted = LocalizationKey("ui.pending.deletion.4b08f65b")
    let deletionPrimary = LocalizationKey("ui.pending.deletion.1652cca1")
}

struct LocalizationUIPickKeys {
    let theNewLocationOfThisSvnWorkingFolder = LocalizationKey("ui.pick.the.new.location.of.this.svn.working.folder.0c58fa9e")
}

struct LocalizationUIPleaseKeys {
    let sendQuestionsTo = LocalizationKey("ui.please.send.questions.to.f2d48929")
}

struct LocalizationUIPressKeys {
    let oOrUseTheButtonAtTheBottomLeft = LocalizationKey("ui.press.o.or.use.the.button.at.the.bottom.left.42abfdb5")
}

struct LocalizationUIPreviewKeys {
    let failedUpdateStillAvailable = LocalizationKey("ui.preview.failed.update.still.available.2c71be90")
}

struct LocalizationUIPropertiesKeys {
    let changed = LocalizationKey("ui.properties.changed.b933354d")
}

struct LocalizationUIPropertyKeys {
    let conflict = LocalizationKey("ui.property.conflict.2fd61b8a")
    let conflictBlocksCommitUntilResolved = LocalizationKey("ui.property.conflict.blocks.commit.until.resolved.bf3c8a12")
    let conflictResolvedReviewBeforeCommit = LocalizationKey("ui.property.conflict.resolved.review.before.commit.7b5e91c4")
    let modified = LocalizationKey("ui.property.modified.4c9a78e1")
}

struct LocalizationUIQuestionsKeys {
    let support = LocalizationKey("ui.questions.support.b20404dc")
}

struct LocalizationUIRecoverKeys {
    let toNewWorkingFolder = LocalizationKey("ui.recover.to.new.working.folder.141e043c")
}

struct LocalizationUIRecoveryKeys {
    let preview = LocalizationKey("ui.recovery.preview.be45be07")
}

struct LocalizationUIRefreshKeys {
    let label = LocalizationKey("ui.refresh.0aca6bd2")
}

struct LocalizationUIRefreshedKeys {
    let label = LocalizationKey("ui.refreshed.41ebae4b")
}

struct LocalizationUIRegisterKeys {
    let anExistingSvnWorkingFolderInTheA = LocalizationKey("ui.register.an.existing.svn.working.folder.in.the.a.361385a1")
    let existingLocalFolder = LocalizationKey("ui.register.existing.local.folder.fcf466c4")
}

struct LocalizationUIReleaseKeys {
    let allMyLocks = LocalizationKey("ui.release.all.my.locks.5d8c31a7")
    let lock = LocalizationKey("ui.release.lock.695a2075")
    let lockNormally = LocalizationKey("ui.release.lock.normally.5e1039ab")
    let locksCount = LocalizationKey("ui.release.locks.count.1f6b83d4")
    let myLock = LocalizationKey("ui.release.my.lock.1b0c3150")
}

struct LocalizationUIReloadKeys {
    let localChangesAndTheLatestServerCommi = LocalizationKey("ui.reload.local.changes.and.the.latest.server.commi.19e409f3")
}

struct LocalizationUIRelocateKeys {
    let repository = LocalizationKey("ui.relocate.repository.6f3c2a98")
}

struct LocalizationUIRelocatingKeys {
    let repository = LocalizationKey("ui.relocating.repository.18b5d4e7")
}

struct LocalizationUIRemoveKeys {
    let inheritedRulesFromTheParentDirectory = LocalizationKey("ui.remove.inherited.rules.from.the.parent.directory.7c2d3995")
    let label = LocalizationKey("ui.remove.d4be5a3e")
    let theSelectedWorkingFolderFromTheApp = LocalizationKey("ui.remove.the.selected.working.folder.from.the.app..ffe092ae")
    let thisRule = LocalizationKey("ui.remove.this.rule.2908b9d1")
    let workingFolderFromAppConfirmation = LocalizationKey("ui.remove.working.folder.from.app.confirmation.54d24642")
}

struct LocalizationUIRemovedKeys {
    let ignoreRule = LocalizationKey("ui.removed.ignore.rule.bb8aeaf0")
}

struct LocalizationUIRenameKeys {
    let withHistory = LocalizationKey("ui.rename.with.history.2a7c91e5")
}

struct LocalizationUIReplaceKeys {
    let localPropertiesWithServerValues = LocalizationKey("ui.replace.local.properties.with.server.values.c2804d9a")
    let withTheServerFileYourLocalEditsLe = LocalizationKey("ui.replace.with.the.server.file.your.local.edits.le.f08dec1d")
}

struct LocalizationUIReplacedKeys {
    let label = LocalizationKey("ui.replaced.6da39732")
}

struct LocalizationUIRepositoryKeys {
    let authenticationFailed = LocalizationKey("ui.repository.authentication.failed.6b2e9c14")
    let connectionFailed = LocalizationKey("ui.repository.connection.failed.1e5a7c93")
    let contentsFailed = LocalizationKey("ui.repository.contents.failed.3c8f2d61")
    let directoryEmpty = LocalizationKey("ui.repository.directory.empty.7a2c5e90")
    let locks = LocalizationKey("ui.repository.locks.dff91f03")
    let mayHaveMoved = LocalizationKey("ui.repository.may.have.moved.31d0a5f8")
    let relocated = LocalizationKey("ui.repository.relocated.4e1b8d60")
    let relocationFailedRecovery = LocalizationKey("ui.repository.relocation.failed.recovery.73a9e2c4")
    let relocationSummary = LocalizationKey("ui.repository.relocation.summary.4a7e30b1")
    let temporaryFileCleanup = LocalizationKey("ui.repository.temporary.file.cleanup.4dd78db2")
    let url = LocalizationKey("ui.repository.url.a29f5816")
    let urlUnchanged = LocalizationKey("ui.repository.url.unchanged.3a6d92e5")
}

struct LocalizationUIResolveKeys {
    let conflictAction = LocalizationKey("ui.resolve.conflict.592b6d3a")
    let conflictSecondary = LocalizationKey("ui.resolve.conflict.d9c365ea")
    let conflictedFilesBeforeCommitting = LocalizationKey("ui.resolve.conflicted.files.before.committing.e5cfd21c")
    let duplicateServerPathsManually = LocalizationKey("ui.resolve.duplicate.server.paths.manually.e8b5d352")
    let unicodePathConflictsBeforeComparing = LocalizationKey("ui.resolve.unicode.path.conflicts.before.comparing..17151bba")
}

struct LocalizationUIResolvingKeys {
    let label = LocalizationKey("ui.resolving.d5e0b71c")
}

struct LocalizationUIRestoreKeys {
    let fileFromServerVersion = LocalizationKey("ui.restore.file.from.server.version.4dd51eb7")
    let localFile = LocalizationKey("ui.restore.local.file.b40bfb4b")
    let selectedFilesAction = LocalizationKey("ui.restore.selected.files.action.7b3e1d95")
    let selectedFilesConfirmation = LocalizationKey("ui.restore.selected.files.confirmation.6d81b3e4")
    let selectedFilesCount = LocalizationKey("ui.restore.selected.files.count.2c9f4a70")
    let selectedPendingDeletions = LocalizationKey("ui.restore.selected.pending.deletions.9c4f7a13")
    let selectedServerFiles = LocalizationKey("ui.restore.selected.server.files.4f2a7c91")
    let serverVersionRemovesTheseItems = LocalizationKey("ui.restore.server.version.removes.these.items.9d41c60b")
    let targetNotDeleted = LocalizationKey("ui.restore.target.not.deleted.1d6a4b82")
    let workingFileConfirmation = LocalizationKey("ui.restore.working.file.confirmation.0ab7e3c9")
    let workingFileToRevision = LocalizationKey("ui.restore.working.file.to.revision.79c4a2e6")
    let workingFileWarning = LocalizationKey("ui.restore.working.file.warning.62d159af")
}

struct LocalizationUIRestoredKeys {
    let label = LocalizationKey("ui.restored.98d96c01")
    let revisionCommitRequired = LocalizationKey("ui.restored.revision.commit.required.f9346b20")
    let selectedServerFiles = LocalizationKey("ui.restored.selected.server.files.2e4c7a91")
}

struct LocalizationUIRestoringKeys {
    let revision = LocalizationKey("ui.restoring.revision.c840d51f")
}

struct LocalizationUIRevealKeys {
    let inFinder = LocalizationKey("ui.reveal.in.finder.52d4a206")
}

struct LocalizationUIRevertKeys {
    let conflictDiscardsLocalChangesAndConflict = LocalizationKey("ui.revert.conflict.discards.local.changes.and.conflict.51b3d907")
    let label = LocalizationKey("ui.revert.f621e9ba")
    let localChangesAction = LocalizationKey("ui.revert.local.changes.c62907ae")
    let localChangesQuestion = LocalizationKey("ui.revert.local.changes.0fa51499")
}

struct LocalizationUIRevertedKeys {
    let localChanges = LocalizationKey("ui.reverted.local.changes.4b9ba3ac")
}

struct LocalizationUIReviewKeys {
    let commit = LocalizationKey("ui.review.commit.8b36485e")
    let forceLock = LocalizationKey("ui.review.force.lock.6c91f2da")
    let label = LocalizationKey("ui.review.618262db")
    let repositoryRelocation = LocalizationKey("ui.review.repository.relocation.2f8a41d0")
    let updateThenRetryCommit = LocalizationKey("ui.review.update.then.retry.commit.6a1e9c43")
    let verifiedFilesBeforeDeletingAndCommitt = LocalizationKey("ui.review.verified.files.before.deleting.and.committ.9aac943d")
}

struct LocalizationUIRevisionKeys {
    let historyClientUnavailable = LocalizationKey("ui.revision.history.client.unavailable.5d7a91c2")
    let optional = LocalizationKey("ui.revision.optional.63ad9f02")
    let restoreBackupInsideWorkingCopy = LocalizationKey("ui.revision.restore.backup.inside.working.copy.107e9c6a")
    let restoreBackupVerificationFailed = LocalizationKey("ui.revision.restore.backup.verification.failed.d9152a6c")
    let restoreMissingWorkingFile = LocalizationKey("ui.revision.restore.missing.working.file.346db8a7")
    let restorePathOutsideWorkingCopy = LocalizationKey("ui.revision.restore.path.outside.working.copy.87d5e210")
    let restoreReplacementVerificationFailed = LocalizationKey("ui.revision.restore.replacement.verification.failed.b8714e35")
    let restoreUnsafeWorkingFile = LocalizationKey("ui.revision.restore.unsafe.working.file.4a960fb3")
    let saveInvalidDestination = LocalizationKey("ui.revision.save.invalid.destination.5f4d2c81")
}

struct LocalizationUIRunKeys {
    let update = LocalizationKey("ui.run.update.e17c8217")
    let workingCopyCleanup = LocalizationKey("ui.run.working.copy.cleanup.b71c28de")
}

struct LocalizationUISaveKeys {
    let inKeychainAndUse = LocalizationKey("ui.save.in.keychain.and.use.9c0fd0d4")
    let inMacosKeychainOptional = LocalizationKey("ui.save.in.macos.keychain.optional.d544f3fd")
    let label = LocalizationKey("ui.save.7c93b7e1")
    let theSvnUsernameAndNewPasswordForThis = LocalizationKey("ui.save.the.svn.username.and.new.password.for.this..72748974")
    let theWorkingFolderLocationSvnUsernameAn = LocalizationKey("ui.save.the.working.folder.location.svn.username.an.4f0a7c19")
    let thisRevisionAs = LocalizationKey("ui.save.this.revision.as.3e8d79a1")
}

struct LocalizationUISavedKeys {
    let commitSelectionNoLongerAvailable = LocalizationKey("ui.saved.commit.selection.no.longer.available.6f81b3d4")
    let historicalRevision = LocalizationKey("ui.saved.historical.revision.76ec18b4")
}

struct LocalizationUISavingKeys {
    let label = LocalizationKey("ui.saving.6a1b2f0c")
    let revision = LocalizationKey("ui.saving.revision.4fb2c8d0")
}

struct LocalizationUISearchKeys {
    let authorFileMessageOrRevision = LocalizationKey("ui.search.author.file.message.or.revision.6c2b5d76")
    let files = LocalizationKey("ui.search.files.e3607184")
}

struct LocalizationUISecureKeys {
    let entryBlocksTheKoreanInputMethodReve = LocalizationKey("ui.secure.entry.blocks.the.korean.input.method.reve.3f7b0c25")
}

struct LocalizationUISelectKeys {
    let aChangedFileToViewItsDiff = LocalizationKey("ui.select.a.changed.file.to.view.its.diff.409b3672")
    let aCommit = LocalizationKey("ui.select.a.commit.8977b05a")
    let aFile = LocalizationKey("ui.select.a.file.12b00b2b")
    let allCurrentlyChangedFilesForCommit = LocalizationKey("ui.select.all.currently.changed.files.for.commit.ccad7410")
    let allSelectAll = LocalizationKey("ui.select.all.061b129c")
    let allSelectAll2 = LocalizationKey("ui.select.all.ef1f5eca")
}

struct LocalizationUISelectedKeys {
    let label = LocalizationKey("ui.selected.685ae833")
}

struct LocalizationUISendKeys {
    let email = LocalizationKey("ui.send.email.f71021b3")
}

struct LocalizationUIServerKeys {
    let certificateProblem = LocalizationKey("ui.server.certificate.problem.6c18f2a9")
    let certificateProblemDetected = LocalizationKey("ui.server.certificate.problem.detected.281e7d4c")
    let changesInsideAPendingDeletionMayNot = LocalizationKey("ui.server.changes.inside.a.pending.deletion.may.not.475f8db6")
    let commit = LocalizationKey("ui.server.commit.952e9a4a")
    let deletionCount = LocalizationKey("ui.server.deletion.count.793b7522")
    let deletionWarning = LocalizationKey("ui.server.deletion.warning.81e94f35")
    let file = LocalizationKey("ui.server.file.4c69a88d")
    let latest = LocalizationKey("ui.server.latest.52ad60d5")
    let latestR = LocalizationKey("ui.server.latest.r.e1c092b2")
    let propertiesAlsoApplied = LocalizationKey("ui.server.properties.also.applied.3ac57d92")
    let propertyValuesWillBeDiscarded = LocalizationKey("ui.server.property.values.will.be.discarded.84d6f2c1")
    let revision = LocalizationKey("ui.server.revision.c11b62aa")
    let versionChangesWillBeDiscarded = LocalizationKey("ui.server.version.changes.will.be.discarded.4ab613d2")
}

struct LocalizationUISettingsKeys {
    let label = LocalizationKey("ui.settings.2f7c48b3")
}

struct LocalizationUIShowKeys {
    let ignoredFiles = LocalizationKey("ui.show.ignored.files.508dbd97")
    let password = LocalizationKey("ui.show.password.9b3d2e71")
    let theMacosKeychainAccessPromptAgain = LocalizationKey("ui.show.the.macos.keychain.access.prompt.again.d57d9f96")
}

struct LocalizationUIShowingKeys {
    let firstCommitsOfTotal = LocalizationKey("ui.showing.first.commits.of.total.8d6f4a21")
}

struct LocalizationUIShowsKeys {
    let theDiffForThisFile = LocalizationKey("ui.shows.the.diff.for.this.file.6f52b16a")
}

struct LocalizationUISourceKeys {
    let isNotFile = LocalizationKey("ui.source.is.not.file.6a3f8d20")
    let isNotVersioned = LocalizationKey("ui.source.is.not.versioned.1e9c4a72")
}

struct LocalizationUIStopKeys {
    let checkout = LocalizationKey("ui.stop.checkout.b0f4e2a7")
    let theCheckoutInProgress = LocalizationKey("ui.stop.the.checkout.in.progress.5d0c9b71")
}

struct LocalizationUISvnKeys {
    let authenticationRequired = LocalizationKey("ui.svn.authentication.required.797a2cdb")
    let ignoreRules = LocalizationKey("ui.svn.ignore.rules.90435aad")
    let password = LocalizationKey("ui.svn.password.5e0660b7")
    let username = LocalizationKey("ui.svn.username.90a19d48")
    let usernameOptional = LocalizationKey("ui.svn.username.optional.fff42bd5")
}

struct LocalizationUISwitchedKeys {
    let path = LocalizationKey("ui.switched.path.8f2c4a71")
    let pathCommitWarning = LocalizationKey("ui.switched.path.commit.warning.3d7b91e6")
}

struct LocalizationUISymbolicKeys {
    let link = LocalizationKey("ui.symbolic.link.0dc00212")
}

struct LocalizationUITemporaryKeys {
    let label = LocalizationKey("ui.temporary.5738ffab")
}

struct LocalizationUITheKeys {
    let bundledSvnExecutableCouldNotBeFoundRe = LocalizationKey("ui.the.bundled.svn.executable.could.not.be.found.re.8656fcae")
    let checkoutWasCanceledPartiallyDownloadedF = LocalizationKey("ui.the.checkout.was.canceled.partially.downloaded.f.7a1c4d58")
    let commitCompletedButWorkingCopyValidation = LocalizationKey("ui.the.commit.completed.but.working.copy.validation.e58fd53c")
    let commitIsBasedOnAnOlderWorkingCopySta = LocalizationKey("ui.the.commit.is.based.on.an.older.working.copy.sta.834c44c4")
    let commitWillBeRecordedWithAnEmptyMessag = LocalizationKey("ui.the.commit.will.be.recorded.with.an.empty.messag.9c31be05")
    let conflictRemainsAfterTheSvnCommandRevie = LocalizationKey("ui.the.conflict.remains.after.the.svn.command.revie.2162b675")
    let conflictWasResolvedReviewTheFileBefore = LocalizationKey("ui.the.conflict.was.resolved.review.the.file.before.7821924b")
    let currentWorkingFileCouldNotBeFound = LocalizationKey("ui.the.current.working.file.could.not.be.found.60c92e05")
    let currentWorkingFileMustBeARegularFile = LocalizationKey("ui.the.current.working.file.must.be.a.regular.file..1af7fbcd")
    let defaultIsKoreaStandardTimeKstThisDoes = LocalizationKey("ui.the.default.is.korea.standard.time.kst.this.does.02bc8ed0")
    let fileIsLockedASuccessfulCommitAutomatic = LocalizationKey("ui.the.file.is.locked.a.successful.commit.automatic.54dc63dd")
    let lockWasForceReleased = LocalizationKey("ui.the.lock.was.force.released.16b02da9")
    let lockWasReleased = LocalizationKey("ui.the.lock.was.released.3aee6b8e")
    let macosUnicodePathWasMatchedToTheActual = LocalizationKey("ui.the.macos.unicode.path.was.matched.to.the.actual.0575e471")
    let newFolderIsAppliedWhenYouSave = LocalizationKey("ui.the.new.folder.is.applied.when.you.save.2b70a1cd")
    let recoveryBackupOfTheCurrentWorkingFile = LocalizationKey("ui.the.recovery.backup.of.the.current.working.file..048b3539")
    let recoveryDestinationFolderMustBeEmpty = LocalizationKey("ui.the.recovery.destination.folder.must.be.empty.2f9bc173")
    let runningSvnCheckoutWillBeStoppedAlready = LocalizationKey("ui.the.running.svn.checkout.will.be.stopped.already.4b7d5a19")
    let savedPasswordWasDeleted = LocalizationKey("ui.the.saved.password.was.deleted.a729310e")
    let selectedFolderIsNotAnSvnLocalWorking = LocalizationKey("ui.the.selected.folder.is.not.an.svn.local.working..c602474e")
    let selectedVersionOfYourFileCouldNotBeR = LocalizationKey("ui.the.selected.version.of.your.file.could.not.be.r.70a89d83")
    let serverFileVersionCouldNotBeFound = LocalizationKey("ui.the.server.file.version.could.not.be.found.3483616c")
    let serverFileVersionMustBeARegularFileN = LocalizationKey("ui.the.server.file.version.must.be.a.regular.file.n.7eb568b2")
    let svnAccountOrPasswordIsNotValid = LocalizationKey("ui.the.svn.account.or.password.is.not.valid.6d81e3f4")
    let svnResponseCouldNotBeRead = LocalizationKey("ui.the.svn.response.could.not.be.read.6a3d5aa8")
    let svnServerDeniedReadAccessToThisFileC = LocalizationKey("ui.the.svn.server.denied.read.access.to.this.file.c.2ec5cc64")
    let workingCopyContainsMixedRevisionsRThis = LocalizationKey("ui.the.working.copy.contains.mixed.revisions.r.this.c69e6def")
    let workingCopyIsUpToDateWithTheServer = LocalizationKey("ui.the.working.copy.is.up.to.date.with.the.server.e31e447e")
    let workingFolderNoLongerExistsRestoreThe = LocalizationKey("ui.the.working.folder.no.longer.exists.restore.the..4946d37c")
    let workingFolderWasChangedTo = LocalizationKey("ui.the.working.folder.was.changed.to.9c6f01b2")
}

struct LocalizationUIThereKeys {
    let areNoGitRulesToImport = LocalizationKey("ui.there.are.no.git.rules.to.import.03bd12e9")
    let areNoLocallyModifiedFiles = LocalizationKey("ui.there.are.no.locally.modified.files.8560ad60")
}

struct LocalizationUIThisKeys {
    let commitMessageWasSavedWithIncorrectEnc = LocalizationKey("ui.this.commit.message.was.saved.with.incorrect.enc.355e2cb5")
    let diskStoresKoreanFilenamesInDecomposed = LocalizationKey("ui.this.disk.stores.korean.filenames.in.decomposed..fe399d66")
    let fileCannotBeCommittedUntilItIsMarked = LocalizationKey("ui.this.file.cannot.be.committed.until.it.is.marked.201bfa2c")
    let fileIsCurrentlyLockedByOpeningWithout = LocalizationKey("ui.this.file.is.currently.locked.by.opening.without.ca1f8e9a")
    let isAServerCommit = LocalizationKey("ui.this.is.a.server.commit.4162d83c")
    let isYourLocalBaseRevision = LocalizationKey("ui.this.is.your.local.base.revision.5912a346")
    let localWorkingFolderIsAlreadyRegistered = LocalizationKey("ui.this.local.working.folder.is.already.registered.b8836f70")
    let onlyMarksTheItemsForDeletionTheyAre = LocalizationKey("ui.this.only.marks.the.items.for.deletion.they.are..594bb2c0")
}

struct LocalizationUITreeKeys {
    let conflict = LocalizationKey("ui.tree.conflict.2ea1184c")
    let conflictIsNotAChoiceBetweenTwoFiles = LocalizationKey("ui.tree.conflict.is.not.a.choice.between.two.files.66dcb7a1")
    let conflictResolvedWithSubtreeBackup = LocalizationKey("ui.tree.conflict.resolved.with.subtree.backup.4c17e9a3")
}

struct LocalizationUIUkKeys {
    let time = LocalizationKey("ui.uk.time.46ba8995")
}

struct LocalizationUIUnableKeys {
    let toCheckTheAppStoreForUpdates = LocalizationKey("ui.unable.to.check.the.app.store.for.updates.a1a5b5ac")
    let toLoadChanges = LocalizationKey("ui.unable.to.load.changes.78b04452")
    let toOpenFile = LocalizationKey("ui.unable.to.open.file.ae08bd77")
}

struct LocalizationUIUncommittedKeys {
    let changes = LocalizationKey("ui.uncommitted.changes.35359722")
    let changesBranchFromYourLocalBase = LocalizationKey("ui.uncommitted.changes.branch.from.your.local.base..d49c86b6")
    let changesCount = LocalizationKey("ui.uncommitted.changes.count.7e3c19d4")
    let changesInWillBeDiscardedAndCan = LocalizationKey("ui.uncommitted.changes.in.will.be.discarded.and.can.df7e8671")
}

struct LocalizationUIUnicodeKeys {
    let pathConflict = LocalizationKey("ui.unicode.path.conflict.1ea3bdc6")
}

struct LocalizationUIUnknownKeys {
    let author = LocalizationKey("ui.unknown.author.511030fa")
    let error = LocalizationKey("ui.unknown.error.745cd1b7")
}

struct LocalizationUIUnsupportedKeys {
    let conflictType = LocalizationKey("ui.unsupported.conflict.type.1a0e94e8")
    let label = LocalizationKey("ui.unsupported.3d400c13")
}

struct LocalizationUIUnversionedKeys {
    let label = LocalizationKey("ui.unversioned.ffbcbcb7")
}

struct LocalizationUIUpKeys {
    let toDate = LocalizationKey("ui.up.to.date.cf368157")
}

struct LocalizationUIUpdateKeys {
    let andRetryCommit = LocalizationKey("ui.update.and.retry.commit.4c6f1a82")
    let conflictsBlockedCommitRetry = LocalizationKey("ui.update.conflicts.blocked.commit.retry.8b3d6f20")
    let createdConflictsCommitNotRetried = LocalizationKey("ui.update.created.conflicts.commit.not.retried.7a4c2e19")
    let label = LocalizationKey("ui.update.0f38eb76")
    let preview = LocalizationKey("ui.update.preview.3e2a4411")
    let requiredBeforeCommitRetry = LocalizationKey("ui.update.required.before.commit.retry.3f8c1d67")
    let requiredPrimary = LocalizationKey("ui.update.required.9da93c25")
    let requiredSecondary = LocalizationKey("ui.update.required.f846039b")
}

struct LocalizationUIUpdatingKeys {
    let label = LocalizationKey("ui.updating.4d2f9a11")
}

struct LocalizationUIUsKeys {
    let easternTime = LocalizationKey("ui.us.eastern.time.9e917cad")
    let pacificTime = LocalizationKey("ui.us.pacific.time.5c9c3b6f")
}

struct LocalizationUIUseKeys {
    let currentWorkingFilePrimary = LocalizationKey("ui.use.current.working.file.275f4c29")
    let currentWorkingFileQuestion = LocalizationKey("ui.use.current.working.file.40ab0712")
    let myFilePrimary = LocalizationKey("ui.use.my.file.36631b8e")
    let myFileQuestion = LocalizationKey("ui.use.my.file.d12a8b2d")
    let onlyForServersWithSelfSignedCertificat = LocalizationKey("ui.use.only.for.servers.with.self.signed.certificat.cd3b5e55")
    let repositoryPath = LocalizationKey("ui.use.repository.path.8f1d4b62")
    let serverFilePrimary = LocalizationKey("ui.use.server.file.30c6c26c")
    let serverFileQuestion = LocalizationKey("ui.use.server.file.949587dc")
    let thisSessionOnly = LocalizationKey("ui.use.this.session.only.08dcce43")
    let thisWhenTheTargetServerSCertificateIs = LocalizationKey("ui.use.this.when.the.target.server.s.certificate.is.2fa0c076")
}

struct LocalizationUIUsernameKeys {
    let label = LocalizationKey("ui.username.4e1b650a")
}

struct LocalizationUIVersionKeys {
    let isAvailable = LocalizationKey("ui.version.is.available.7e5cfb4e")
    let label = LocalizationKey("ui.version.6bb2f91c")
}

struct LocalizationUIVersionedKeys {
    let itemsBelowTheSelectedDirectoryWil = LocalizationKey("ui.versioned.items.below.the.selected.directory.wil.f7d01b47")
}

struct LocalizationUIViewKeys {
    let changesInThisCommit = LocalizationKey("ui.view.changes.in.this.commit.afab8525")
    let inAppStore = LocalizationKey("ui.view.in.app.store.7c79e972")
    let theLockedFilesAndTheirCountInThisRe = LocalizationKey("ui.view.the.locked.files.and.their.count.in.this.re.1d4d4a51")
    let theOriginalMessageBeforeRestoration = LocalizationKey("ui.view.the.original.message.before.restoration.6a5e3b2b")
}

struct LocalizationUIWhenKeys {
    let youChooseAVersionTheCurrentWorkingFi = LocalizationKey("ui.when.you.choose.a.version.the.current.working.fi.70533c5a")
}

struct LocalizationUIWorkingKeys {
    let copyCleanup = LocalizationKey("ui.working.copy.cleanup.62f3ac11")
    let copyCleanupCompleted = LocalizationKey("ui.working.copy.cleanup.completed.11c93f4a")
    let copyCleanupFailedContactSupport = LocalizationKey("ui.working.copy.cleanup.failed.contact.support.81a7d2ce")
    let copyOperationInterruptedRunCleanup = LocalizationKey("ui.working.copy.operation.interrupted.run.cleanup.0bc374e1")
}

struct LocalizationUIYesKeys {
    let label = LocalizationKey("ui.yes.93cba074")
}

struct LocalizationUIYouKeys {
    let reUsingTheLatestVersion = LocalizationKey("ui.you.re.using.the.latest.version.18d5624c")
}

struct LocalizationUIYourKeys {
    let fileVersionCouldNotBeFound = LocalizationKey("ui.your.file.version.could.not.be.found.576883d5")
    let fileVersionMustBeARegularFileNotAS = LocalizationKey("ui.your.file.version.must.be.a.regular.file.not.a.s.0ea5ff6f")
    let localBaseRevisionIsEarlierThanTheLat = LocalizationKey("ui.your.local.base.revision.is.earlier.than.the.lat.e0f7b1d7")
    let localUpdateBaseFallsBetweenTwoServer = LocalizationKey("ui.your.local.update.base.falls.between.two.server..5815a927")
}
