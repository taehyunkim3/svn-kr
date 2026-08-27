import SwiftUI

/// 앱의 주요 화면 크기 계약입니다.
///
/// 화면별로 숫자를 직접 넣으면 부모와 자식이 서로 다른 최소 크기를 요구하면서
/// SplitView가 상태 변경 때마다 재배치됩니다. 창과 작업 패널의 크기는 이 타입만
/// 소유하고, 개별 콘텐츠 뷰는 남은 공간을 채우는 역할만 맡습니다.
enum AppLayout {
    static let windowMinimumWidth: CGFloat = 1_120
    static let windowMinimumHeight: CGFloat = 700
    static let windowDefaultWidth: CGFloat = 1_280
    static let windowDefaultHeight: CGFloat = 780
    static let aboutWindowSize = CGSize(width: 420, height: 330)
    static let settingsWindowSize = CGSize(width: 560, height: 350)

    static let sidebarMinimumWidth: CGFloat = 190
    static let sidebarIdealWidth: CGFloat = 230
    static let sidebarMaximumWidth: CGFloat = 300

    /// 툴바의 아이콘·텍스트와 진행 표시기가 버튼/창 가장자리에 붙지 않게 하는 여백입니다.
    static let toolbarItemHorizontalPadding: CGFloat = 6

    static let changesPrimaryMinimumWidth: CGFloat = 380
    static let changesDetailMinimumWidth: CGFloat = 400
    static let changesDisclosureSize = CGSize(width: 18, height: 18)
    static let untrackedChildIndentation: CGFloat = 18
    static let historyPrimaryMinimumWidth: CGFloat = 520
    static let historyDetailMinimumWidth: CGFloat = 380

    /// 분할 보기의 폴더 트리는 이름만 보여주므로 좁게 시작하고, 내용 표가 넓게 열립니다.
    static let fileBrowserFolderPaneMinimumWidth: CGFloat = 180
    static let fileBrowserContentsPaneMinimumWidth: CGFloat = 520
    static let fileBrowserFolderDisclosureHitTargetSize = CGSize(width: 20, height: 20)
    /// 좌측 대 우측을 1:3으로 시작합니다. 창 크기가 달라도 같은 비율을 유지하려면
    /// 고정 너비가 아니라 사용 가능한 너비에서 계산해야 합니다.
    static let fileBrowserFolderPaneWidthFraction: CGFloat = 0.25

    /// `requested`가 nil이면 1:3 시작 비율을, 값이 있으면 사용자가 옮긴 위치를
    /// 두 패널의 최소 너비 안으로 가둔 결과를 돌려줍니다.
    static func fileBrowserFolderPaneWidth(
        requested: CGFloat?,
        availableWidth: CGFloat
    ) -> CGFloat {
        guard availableWidth > 0 else { return fileBrowserFolderPaneMinimumWidth }
        let target = requested ?? availableWidth * fileBrowserFolderPaneWidthFraction
        // 내용 표가 최소 너비를 지킬 수 있는 범위 안에서만 요청을 반영합니다.
        let maximum = max(
            fileBrowserFolderPaneMinimumWidth,
            availableWidth - fileBrowserContentsPaneMinimumWidth
        )
        return min(max(target, fileBrowserFolderPaneMinimumWidth), maximum)
    }

    /// 파일 이름은 경로가 길어 가장 자주 잘리므로 다른 열보다 넓게 잡습니다.
    static let fileBrowserNameColumnMinimumWidth: CGFloat = 200
    static let fileBrowserNameColumnIdealWidth: CGFloat = 320
    /// 작업 열은 두 버튼 이름이 줄임표 없이 들어가야 합니다.
    static let fileBrowserActionsColumnMinimumWidth: CGFloat = 230

    /// 기록 상세의 파일 목록은 사용자가 조절하는 분할 영역이 아닙니다.
    /// 높이를 한곳에서 고정해 로딩/빈 화면/diff 상태 전환에도 아래 패널이 흔들리지 않게 합니다.
    static let historyChangedFilesHeight: CGFloat = 220

    static let addRepositorySheetMinimumSize = CGSize(width: 700, height: 700)
    static let checkoutLogHeight: CGFloat = 180
    static let commitLogHeight: CGFloat = 140
    static let repositoryLocksSheetMinimumSize = CGSize(width: 680, height: 440)
    static let ignoreRulesSheetMinimumSize = CGSize(width: 760, height: 620)
    static let deletionConfirmationSheetMinimumSize = CGSize(width: 620, height: 360)
    static let commitConfirmationSheetMinimumSize = CGSize(width: 840, height: 620)
    /// 업데이트 미리보기의 커밋 펼침 아이콘입니다. 리비전 숫자와 세로 중앙을 맞추고
    /// 아이콘 글리프보다 넓은 탭 영역을 확보하기 위해 명시적인 크기를 사용합니다.
    static let updatePreviewCommitDisclosureSize = CGSize(width: 20, height: 20)
    static let updatePreviewCommitDisclosureSpacing: CGFloat = 8
    static let documentOpenConfirmationSheetMinimumSize = CGSize(width: 620, height: 320)
    static let updatePreviewSheetMinimumSize = CGSize(width: 720, height: 480)
    static let temporaryFileCleanupSheetMinimumSize = CGSize(width: 720, height: 520)
    static let fileHistorySheetMinimumSize = CGSize(width: 760, height: 520)
    static let filePropertiesSheetMinimumSize = CGSize(width: 520, height: 300)
    static let conflictResolutionSheetMinimumSize = CGSize(width: 680, height: 480)
    static let pathRecoverySheetMinimumSize = CGSize(width: 700, height: 520)
    static let repositoryPathNormalizationSheetMinimumSize = CGSize(width: 820, height: 620)
    static let repositoryPathNormalizationConfirmationSheetMinimumSize = CGSize(width: 680, height: 480)
    static let errorDetailsSheetMinimumSize = CGSize(width: 640, height: 380)
    static let authenticationSheetWidth: CGFloat = 620
    static let credentialsSheetWidth: CGFloat = 560
    static let credentialFieldMinimumWidth: CGFloat = 360
    static let repositoryURLFieldMinimumWidth: CGFloat = 440
    static let logMessagePopoverMinimumWidth: CGFloat = 360
    static let logMessagePopoverIdealWidth: CGFloat = 520
    static let logMessagePopoverMaximumWidth: CGFloat = 640
    static let inlineErrorMaximumHeight: CGFloat = 160
    /// 트리 충돌 되돌리기 확인창이 한 번에 나열하는 경로 개수입니다.
    /// 나머지는 "외 N개"로 접어 대화상자가 화면 밖으로 넘치지 않게 합니다.
    static let treeConflictRestoreListedPathLimit = 12
}

extension View {
    /// 시트가 최소 크기만 보고한 뒤 작은 콘텐츠를 가운데 배치하지 않도록
    /// 루트 컨테이너 자체가 시트의 전체 제안 크기를 채우게 합니다.
    func appSheetFrame(minimumSize: CGSize) -> some View {
        frame(
            minWidth: minimumSize.width,
            maxWidth: .infinity,
            minHeight: minimumSize.height,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }
}

/// 변경 화면과 기록 화면이 공유하는 유일한 좌우 크기 소유자입니다.
///
/// 중요: 호출하는 화면에서 좌우 자식에 다시 무한 높이 frame을 붙이지 않습니다.
/// SplitView의 전체 크기와 두 패널의 최소 너비는 이 컨테이너가 함께 결정해야
/// 콘텐츠의 고유 크기가 달라져도 위·아래 빈 공간이 생기지 않습니다.
struct WorkspaceSplitView<Primary: View, Detail: View>: View {
    private let primaryMinWidth: CGFloat
    private let detailMinWidth: CGFloat
    private let primary: Primary
    private let detail: Detail

    init(
        primaryMinWidth: CGFloat,
        detailMinWidth: CGFloat,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder detail: () -> Detail
    ) {
        self.primaryMinWidth = primaryMinWidth
        self.detailMinWidth = detailMinWidth
        self.primary = primary()
        self.detail = detail()
    }

    var body: some View {
        HSplitView {
            primary
                .frame(minWidth: primaryMinWidth, maxHeight: .infinity)

            detail
                .frame(minWidth: detailMinWidth, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
