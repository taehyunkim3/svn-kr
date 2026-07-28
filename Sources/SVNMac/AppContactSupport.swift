import Foundation

enum AppContactSupport {
    static let email = "thkim@mrdevello.com"
    static let mailURL = URL(string: "mailto:\(email)")!

    static func menuTitle(for language: AppLanguage) -> String {
        language.localized("ui.questions.support.b20404dc")
    }

    static func alertTitle(for language: AppLanguage) -> String {
        language.localized("ui.need.help.bf7256df")
    }

    static func message(for language: AppLanguage) -> String {
        language.localized("ui.please.send.questions.to.f2d48929", email)
    }

    static func mailButtonTitle(for language: AppLanguage) -> String {
        language.localized("ui.send.email.f71021b3")
    }

    static func closeButtonTitle(for language: AppLanguage) -> String {
        language.localized("ui.close.3ea43db3")
    }
}
