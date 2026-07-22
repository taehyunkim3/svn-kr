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

    static let sidebarMinimumWidth: CGFloat = 190
    static let sidebarIdealWidth: CGFloat = 230
    static let sidebarMaximumWidth: CGFloat = 300

    static let changesPrimaryMinimumWidth: CGFloat = 380
    static let changesDetailMinimumWidth: CGFloat = 400
    static let historyPrimaryMinimumWidth: CGFloat = 520
    static let historyDetailMinimumWidth: CGFloat = 380

    /// 기록 상세의 파일 목록은 사용자가 조절하는 분할 영역이 아닙니다.
    /// 높이를 한곳에서 고정해 로딩/빈 화면/diff 상태 전환에도 아래 패널이 흔들리지 않게 합니다.
    static let historyChangedFilesHeight: CGFloat = 220

    static let addRepositorySheetMinimumSize = CGSize(width: 700, height: 700)
    static let checkoutLogHeight: CGFloat = 180
    static let repositoryLocksSheetMinimumSize = CGSize(width: 680, height: 440)
    static let ignoreRulesSheetMinimumSize = CGSize(width: 620, height: 420)
    static let updatePreviewSheetMinimumSize = CGSize(width: 720, height: 480)
    static let fileHistorySheetMinimumSize = CGSize(width: 760, height: 520)
    static let conflictResolutionSheetMinimumSize = CGSize(width: 680, height: 480)
    static let pathRecoverySheetMinimumSize = CGSize(width: 700, height: 520)
    static let errorDetailsSheetMinimumSize = CGSize(width: 640, height: 380)
    static let inlineErrorMaximumHeight: CGFloat = 160
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
