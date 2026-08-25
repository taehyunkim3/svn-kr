import Foundation

enum AppContactSupport {
    static let email = "thkim@mrdevello.com"
    static let mailURL = URL(string: "mailto:\(email)")!

    static func menuTitle(for language: AppLanguage) -> String {
        language.localized(.ui.questions.support)
    }

    static func alertTitle(for language: AppLanguage) -> String {
        language.localized(.ui.need.help)
    }

    static func message(for language: AppLanguage) -> String {
        language.localized(.ui.please.sendQuestionsTo, email)
    }

    static func mailButtonTitle(for language: AppLanguage) -> String {
        language.localized(.ui.send.email)
    }

    static func closeButtonTitle(for language: AppLanguage) -> String {
        language.localized(.ui.close.label)
    }
}
