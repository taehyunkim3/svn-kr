import Foundation

enum AppContactSupport {
    static let email = "thkim@mrdevello.com"
    static let mailURL = URL(string: "mailto:\(email)")!

    static func menuTitle(for language: AppLanguage) -> String {
        language.localized(.ui.about.questionsSupport)
    }

    static func alertTitle(for language: AppLanguage) -> String {
        language.localized(.ui.about.needHelp)
    }

    static func message(for language: AppLanguage) -> String {
        language.localized(.ui.about.pleaseSendQuestions, email)
    }

    static func mailButtonTitle(for language: AppLanguage) -> String {
        language.localized(.ui.about.sendEmail)
    }

    static func closeButtonTitle(for language: AppLanguage) -> String {
        language.localized(.ui.common.close)
    }
}
