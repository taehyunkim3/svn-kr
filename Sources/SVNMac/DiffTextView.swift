import SwiftUI

/// 큰 diff도 줄마다 SwiftUI 뷰를 만들지 않고 하나의 Text로 렌더링합니다.
struct DiffTextView: View {
    private let text: AttributedString

    init(_ value: String) {
        var result = AttributedString()
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            var attributedLine = AttributedString(String(line))
            if line.hasPrefix("+"), !line.hasPrefix("+++") {
                attributedLine.foregroundColor = .green
            } else if line.hasPrefix("-"), !line.hasPrefix("---") {
                attributedLine.foregroundColor = .red
            }
            result.append(attributedLine)
            if index != lines.indices.last { result.append(AttributedString("\n")) }
        }
        text = result
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding()
        }
    }
}
