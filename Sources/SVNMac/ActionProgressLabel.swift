import SwiftUI

/// 진행 중인 작업을 실행하는 버튼의 공통 라벨입니다.
///
/// 비활성화만으로는 "왜 눌리지 않는지"를 알 수 없으므로, 작업이 도는 동안에는
/// 아이콘 자리를 스피너로 바꾸고 진행 중 문구를 함께 보여 줍니다. 아이콘과
/// 스피너가 같은 자리를 쓰기 때문에 상태가 바뀌어도 버튼 폭이 크게 흔들리지 않습니다.
struct ActionProgressLabel: View {
    let title: String
    var inProgressTitle: String?
    var systemImage: String?
    let isInProgress: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isInProgress {
                ProgressView().controlSize(.small)
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            Text(isInProgress ? (inProgressTitle ?? title) : title)
        }
    }
}
