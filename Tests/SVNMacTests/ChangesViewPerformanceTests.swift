import Foundation
import Testing

@Suite("ChangesViewPerformanceTests")
struct ChangesViewPerformanceTests {
    @Test func commitMessageStateIsOwnedByIsolatedControlsView() throws {
        let sources = try svnMacSources()
        let changesView = try source(named: "ChangesView.swift", in: sources)
        let commitControls = try source(named: "CommitControlsView.swift", in: sources)

        #expect(changesView.contains("CommitControlsView()"))
        #expect(!changesView.contains("@State private var commitMessage"))
        #expect(commitControls.contains("@State private var commitMessage"))
    }

    @Test func changedFileListDoesNotConcatenateStatusCollections() throws {
        let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())

        #expect(!changesView.contains("store.statuses +"))
        #expect(changesView.contains("ForEach(store.statuses)"))
        #expect(changesView.contains("ForEach(store.ignoredStatuses)"))
    }

    @Test func largeHistoryDiffUsesOneAttributedTextView() throws {
        let sources = try svnMacSources()
        let historyDiff = try source(named: "HistoryRevisionDiffView.swift", in: sources)
        let diffText = try source(named: "DiffTextView.swift", in: sources)

        #expect(historyDiff.contains("DiffTextView(value)"))
        #expect(!historyDiff.contains("ForEach(Array(lines.enumerated())"))
        #expect(diffText.contains("Text(text)"))
    }

    @Test func changesViewDistinguishesMissingStatesAndSummarizesUnicodeCollisions() throws {
        let sources = try svnMacSources()
        let changesView = try source(named: "ChangesView.swift", in: sources)
        let commitControls = try source(named: "CommitControlsView.swift", in: sources)

        #expect(changesView.contains("삭제"))
        #expect(changesView.contains("로컬 누락"))
        #expect(changesView.contains("정리 필요"))
        #expect(changesView.contains("Cleanup Needed"))
        #expect(!changesView.contains("추가 취소됨"))
        #expect(changesView.contains("한글 경로 충돌"))
        #expect(changesView.contains("entry.isSelectableForCommit"))
        #expect(changesView.contains("entry.canScheduleRepositoryDeletion"))
        #expect(changesView.contains("처리 선택…"))
        #expect(changesView.contains("저장소에서도 삭제…"))
        #expect(changesView.contains("삭제 예정"))
        #expect(commitControls.contains("store.selectAllStatusPaths"))
        #expect(commitControls.contains("store.canCommitSelectedPaths"))
        #expect(commitControls.contains("store.scheduledDeletionCount"))
    }

    @Test func unversionedDirectoryExplainsRecursiveCommit() throws {
        let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())

        #expect(changesView.contains("하위 파일이 함께 추가됩니다."))
        #expect(changesView.contains("entry.item == .unversioned && entry.nodeKind == .directory"))
    }

    @Test func temporaryFilesHaveDedicatedBadgeAndSelectAllPolicy() throws {
        let sources = try svnMacSources()
        let changesView = try source(named: "ChangesView.swift", in: sources)
        let commitControls = try source(named: "CommitControlsView.swift", in: sources)

        #expect(changesView.contains("entry.isTemporaryFile"))
        #expect(changesView.contains("임시파일"))
        #expect(changesView.contains("Temporary"))
        #expect(commitControls.contains("store.selectAllStatusPaths"))
        #expect(commitControls.contains("store.selectedPaths.removeAll()"))
    }

    @Test func collisionActionsUseAggregateRepairabilityAndManualServerGuidance() throws {
        let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())

        #expect(changesView.contains("동일 한글 경로 정리"))
        #expect(changesView.contains("store.canRepairCanonicalAliases"))
        #expect(changesView.contains("await store.repairCanonicalAliases()"))
        #expect(changesView.contains("서버 중복 경로 수동 정리 필요"))
        #expect(!changesView.contains("if collision.repairableRawPath != nil"))
        #expect(!changesView.contains("await store.beginPathRecovery()"))
    }

    @Test func conflictResolutionOffersThreeSafeBinaryChoicesAndPathNotice() throws {
        let view = try source(named: "ConflictResolutionView.swift", in: try svnMacSources())

        #expect(view.contains("내 파일 열기"))
        #expect(view.contains("서버 파일 열기"))
        #expect(view.contains("내 파일 사용"))
        #expect(view.contains("서버 파일 사용"))
        #expect(view.contains("현재 작업 파일 사용"))
        #expect(view.contains("pendingChoice = .working"))
        #expect(view.contains("session.wasCanonicallyResolved"))
        #expect(view.contains("실제 SVN 관리 경로로 자동 보정했습니다"))
        #expect(view.contains("백업 폴더 열기"))
        #expect(view.contains("session.details.path"))
        #expect(view.contains("선택하는 순간의 현재 작업 파일은 별도의 숨김 복구본으로 보존됩니다"))
        #expect(view.contains("interactiveDismissDisabled(store.isResolvingConflict)"))
        #expect(view.contains("store.isResolvingConflict"))
        #expect(view.contains("취소"))
        #expect(view.components(separatedBy: ".disabled(store.isResolvingConflict)").count - 1 == 5)
        #expect(!view.contains("닫기"))
        #expect(view.contains("수정해도 실제 작업 파일에는 반영되지 않습니다"))
        #expect(!view.contains("enum ConflictResolutionCopy"))
        #expect(!view.contains("두 버전 모두 원본 옆에 보관"))
        #expect(!view.contains("현재 파일로 충돌 해결 완료"))
    }

    private func svnMacSources() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    }

    private func source(named name: String, in directory: URL) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}
