import Foundation

enum MosaicPhoneNumber {
    /// Default region when the user enters a national number without a country code.
    static let defaultCountryCode = "1"

    /// Builds an E.164 phone number for Supabase Auth. Returns nil when digits are too short.
    static func normalized(_ raw: String, countryCode: String = defaultCountryCode) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("+") {
            let digits = digitsOnly(trimmed.dropFirst())
            guard (8...15).contains(digits.count) else { return nil }
            return "+\(digits)"
        }
        let digits = digitsOnly(trimmed)
        guard (10...15).contains(digits.count) else { return nil }
        let code = digitsOnly(countryCode)
        guard !code.isEmpty else { return nil }
        return "+\(code)\(digits)"
    }

    static func digitsOnly(_ text: String) -> String {
        String(text.filter(\.isNumber))
    }

    static func digitsOnly<S: StringProtocol>(_ text: S) -> String {
        String(text.filter(\.isNumber))
    }

    /// JSON body for `POST /auth/v1/otp` with a phone number.
    static func sendOTPBody(phone: String, createUser: Bool = true) -> [String: Any] {
        ["phone": phone, "create_user": createUser]
    }

    /// JSON body for `POST /auth/v1/verify` with an SMS code.
    static func verifySMSBody(phone: String, token: String) -> [String: Any] {
        ["type": "sms", "phone": phone, "token": token]
    }

    /// JSON body for `POST /auth/v1/otp` with an email address.
    static func sendEmailOTPBody(email: String, createUser: Bool = true) -> [String: Any] {
        ["email": email.lowercased(), "create_user": createUser]
    }

    /// JSON body for `POST /auth/v1/verify` with an email code.
    static func verifyEmailOTPBody(email: String, token: String) -> [String: Any] {
        ["type": "email", "email": email.lowercased(), "token": token]
    }
}
