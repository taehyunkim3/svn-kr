import Foundation

enum AppContactSupport {
    static let email = "thkim@mrdevello.com"
    static let mailURL = URL(string: "mailto:\(email)")!

    static func menuTitle(for language: AppLanguage) -> String {
        language.text("문의 및 도움말", "Questions & Support")
    }

    static func alertTitle(for language: AppLanguage) -> String {
        language.text("문의 사항이 있으신가요?", "Need help?")
    }

    static func message(for language: AppLanguage) -> String {
        language.text(
            "문의 사항은 \(email)으로 남겨 주세요.",
            "Please send questions to \(email)."
        )
    }

    static func mailButtonTitle(for language: AppLanguage) -> String {
        language.text("메일 보내기", "Send Email")
    }

    static func closeButtonTitle(for language: AppLanguage) -> String {
        language.text("닫기", "Close")
    }
}
