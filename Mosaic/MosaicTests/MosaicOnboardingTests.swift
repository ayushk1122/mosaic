import Foundation
import Testing

@testable import Mosaic

@Suite
struct MosaicOnboardingTests {
    @Test
    func phoneNormalizationBuildsE164() {
        #expect(MosaicPhoneNumber.normalized("+1 (415) 212-7777") == "+14152127777")
        #expect(MosaicPhoneNumber.normalized("4152127777") == "+14152127777")
        #expect(MosaicPhoneNumber.normalized("123") == nil)
    }

    @Test
    func otpBodiesMatchSupabaseAuth() throws {
        let signUpEmail = MosaicPhoneNumber.sendEmailOTPBody(email: "Ada@Example.com", createUser: true)
        #expect(signUpEmail["email"] as? String == "ada@example.com")
        #expect(signUpEmail["create_user"] as? Bool == true)
        let signInEmail = MosaicPhoneNumber.sendEmailOTPBody(email: "ada@example.com", createUser: false)
        #expect(signInEmail["create_user"] as? Bool == false)

        let emailVerify = MosaicPhoneNumber.verifyEmailOTPBody(email: "ada@example.com", token: "123456")
        #expect(emailVerify["type"] as? String == "email")
        #expect(emailVerify["token"] as? String == "123456")

        let smsSend = MosaicPhoneNumber.sendOTPBody(phone: "+14152127777", createUser: false)
        #expect(smsSend["phone"] as? String == "+14152127777")
        #expect(smsSend["create_user"] as? Bool == false)

        #expect(MosaicAccount.looksLikeUnknownAccount(status: 422, body: Data(#"{"msg":"User not found"}"#.utf8)))

        let smsVerify = MosaicPhoneNumber.verifySMSBody(phone: "+14152127777", token: "123456")
        #expect(smsVerify["type"] as? String == "sms")
    }

    @Test
    func onboardingRouterPrefersCacheAndLocalAccount() {
        #expect(
            MosaicOnboardingRouter.route(
                cachedComplete: true,
                hasLocalAccount: false,
                status: nil
            ) == .readyForPreparation
        )
        #expect(
            MosaicOnboardingRouter.route(
                cachedComplete: false,
                hasLocalAccount: true,
                status: nil
            ) == .readyForPreparation
        )
        #expect(
            MosaicOnboardingRouter.route(
                cachedComplete: false,
                hasLocalAccount: false,
                status: nil
            ) == .retry
        )
        let pending = MosaicOnboardingStatus(onboardedAt: nil, username: "user_abcd", displayName: "", birthday: nil)
        #expect(
            MosaicOnboardingRouter.route(
                cachedComplete: false,
                hasLocalAccount: false,
                status: pending
            ) == .needsSetup
        )
    }

    @Test
    func onboardingStatusParsesBirthdayAndCompletion() throws {
        let json = """
        [{"onboarded_at":"2026-10-16T12:00:00+00:00","username":"ada_golf","display_name":"Ada","birthday":"1994-03-02"}]
        """
        let status = try #require(try MosaicOnboardingClient.status(from: Data(json.utf8)))
        #expect(status.isOnboarded)
        #expect(status.username == "ada_golf")
        #expect(status.displayName == "Ada")
        #expect(status.birthday != nil)
    }
}
