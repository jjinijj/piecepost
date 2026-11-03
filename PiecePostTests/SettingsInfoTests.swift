import Foundation
import Testing
@testable import PiecePost

/// 설정 화면 "정보" 구역: 약관 줄 표시 여부와 버전 문구.
struct SettingsInfoTests {
    private let privacy = URL(string: "https://example.com/privacy")!
    private let terms = URL(string: "https://example.com/terms")!

    @Test func noURLsHidesBothRows() {
        #expect(LegalLinks.visibleItems(privacyPolicy: nil, termsOfService: nil).isEmpty)
    }

    @Test func bothURLsShowBothRowsInOrder() {
        let items = LegalLinks.visibleItems(privacyPolicy: privacy, termsOfService: terms)
        #expect(items == [
            LegalLinks.Item(title: "개인정보 처리방침", url: privacy),
            LegalLinks.Item(title: "이용약관", url: terms),
        ])
    }

    @Test func onlyPrivacyURLShowsPrivacyRow() {
        let items = LegalLinks.visibleItems(privacyPolicy: privacy, termsOfService: nil)
        #expect(items.map(\.title) == ["개인정보 처리방침"])
    }

    @Test func onlyTermsURLShowsTermsRow() {
        let items = LegalLinks.visibleItems(privacyPolicy: nil, termsOfService: terms)
        #expect(items.map(\.title) == ["이용약관"])
        #expect(items.first?.url == terms)
    }

    /// 지금은 주소가 없어 두 줄 모두 숨는다.
    @Test func currentConstantsAreEmpty() {
        #expect(LegalLinks.privacyPolicyURL == nil)
        #expect(LegalLinks.termsOfServiceURL == nil)
        #expect(LegalLinks.visibleItems.isEmpty)
    }

    @Test func versionShowsShortVersionAndBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "12"]
        #expect(AppVersion.text(infoDictionary: info) == "1.0 (12)")
    }

    @Test func versionWithoutBuildShowsShortVersionOnly() {
        #expect(AppVersion.text(infoDictionary: ["CFBundleShortVersionString": "1.0"]) == "1.0")
    }

    @Test func currentVersionMatchesAppBundle() {
        let info = Bundle.main.infoDictionary ?? [:]
        let expected = "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
        #expect(AppVersion.current == expected)
    }
}
