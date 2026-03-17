import Foundation

enum L10n {
    enum Common {
        static var appName: String { String(localized: "common.app_name") }
        static var continueAction: String { String(localized: "common.continue") }
        static var finishAction: String { String(localized: "common.finish") }
        static var cancel: String { String(localized: "common.cancel") }
        static var ok: String { String(localized: "common.ok") }
        static var guestName: String { String(localized: "common.guest_name") }
        static var authenticationTitle: String { String(localized: "common.authentication_title") }
        static var login: String { String(localized: "common.login") }
        static var register: String { String(localized: "common.register") }
    }

    enum Onboarding {
        static var page1Title: String { String(localized: "onboarding.page1.title") }
        static var page1Subtitle: String { String(localized: "onboarding.page1.subtitle") }
        static var page2Title: String { String(localized: "onboarding.page2.title") }
        static var page2Subtitle: String { String(localized: "onboarding.page2.subtitle") }
        static var page3Title: String { String(localized: "onboarding.page3.title") }
        static var page3Subtitle: String { String(localized: "onboarding.page3.subtitle") }
    }

    enum Auth {
        static var emailPlaceholder: String { String(localized: "auth.email_placeholder") }
        static var passwordPlaceholder: String { String(localized: "auth.password_placeholder") }
        static var fullNamePlaceholder: String { String(localized: "auth.full_name_placeholder") }
        static var forgotPassword: String { String(localized: "auth.forgot_password") }
        static var noAccount: String { String(localized: "auth.no_account") }
        static var alreadyAccount: String { String(localized: "auth.already_account") }
        static var loginSuccessTitle: String { String(localized: "auth.login_success_title") }
        static var otpPrompt: String { String(localized: "auth.otp_prompt") }
        static var otpPlaceholder: String { String(localized: "auth.otp_placeholder") }
        static var activateAccount: String { String(localized: "auth.activate_account") }
        static var activationTitle: String { String(localized: "auth.activation_title") }
        static var activationSentTitle: String { String(localized: "auth.activation_sent_title") }
        static func activationSentMessage(_ email: String) -> String {
            String(format: String(localized: "auth.activation_sent_message"), email)
        }
        static var codeSentTitle: String { String(localized: "auth.code_sent_title") }
        static var loginSegment: String { String(localized: "auth.segment_login") }
        static var registerSegment: String { String(localized: "auth.segment_register") }
        static var optionsPickerLabel: String { String(localized: "auth.options_picker_label") }
    }

    enum Home {
        static var latestReports: String { String(localized: "home.latest_reports") }
        static var noReportsToday: String { String(localized: "home.no_reports_today") }
        static var otherReports: String { String(localized: "home.other_reports") }
        static func errorPrefix(_ message: String) -> String {
            String(format: String(localized: "home.error_prefix"), message)
        }
        static func greeting(_ name: String) -> String {
            String(format: String(localized: "home.greeting"), name)
        }
    }

    enum Splash {
        static var accessibilityLogo: String { String(localized: "splash.logo_accessibility") }
    }
}
