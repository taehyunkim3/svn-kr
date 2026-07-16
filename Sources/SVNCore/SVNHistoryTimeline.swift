import Foundation

/// 서버 커밋 목록 안에서 로컬 작업 복사본의 기준 리비전을 어디에 그릴지 계산합니다.
///
/// SwiftUI 화면에서 직접 리비전 문자열을 비교하지 않도록 순수 계산을 코어로
/// 분리했습니다. 따라서 서버 기록의 범위가 바뀌거나 로컬 리비전이 HEAD보다
/// 앞서는 예외 상황도 UI와 무관하게 테스트할 수 있습니다.
public struct SVNHistoryTimeline: Equatable, Sendable {
    /// 서버 커밋 행 자체에 로컬 기준 표시를 함께 그릴 때 그 행의 리비전입니다.
    public let graphEntryRevision: String?
    /// 로컬 기준이 두 서버 커밋 사이에 있을 때 별도 행을 삽입할 위치입니다.
    public let insertionIndex: Int?
    /// 로컬 기준이 현재 불러온 서버 기록보다 더 오래된 경우입니다.
    public let isBeforeLoadedHistory: Bool

    public init(logs: [SVNLogEntry], workingCopyRevision: String?) {
        guard let workingCopyRevision,
              let headRevision = logs.first?.revision else {
            graphEntryRevision = nil
            insertionIndex = nil
            isBeforeLoadedHistory = false
            return
        }

        // 로컬 리비전이 HEAD와 같거나 더 크면 화면의 HEAD 행에 표시합니다.
        // 숫자로 변환할 수 없는 응답은 아래의 정확한 문자열 일치 경로로 넘깁니다.
        if let workingCopy = Int(workingCopyRevision),
           let head = Int(headRevision),
           workingCopy >= head {
            graphEntryRevision = headRevision
            insertionIndex = nil
            isBeforeLoadedHistory = false
            return
        }

        if logs.contains(where: { $0.revision == workingCopyRevision }) {
            graphEntryRevision = workingCopyRevision
            insertionIndex = nil
            isBeforeLoadedHistory = false
            return
        }

        graphEntryRevision = nil
        if let workingCopy = Int(workingCopyRevision) {
            insertionIndex = logs.firstIndex { entry in
                guard let revision = Int(entry.revision) else { return false }
                return revision < workingCopy
            }
        } else {
            insertionIndex = nil
        }
        isBeforeLoadedHistory = insertionIndex == nil && !logs.isEmpty
    }
}
