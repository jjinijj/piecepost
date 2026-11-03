import Foundation

/// 설정 화면 "정보" 구역의 약관 링크.
/// 주소는 이 파일의 상수 한 곳에만 둔다. 비어 있으면 그 줄을 보이지 않는다(기획서 settings-skeleton 완료 기준 6).
enum LegalLinks {
    /// 개인정보 처리방침 주소. 아직 없음
    static let privacyPolicyURL: URL? = nil
    /// 이용약관 주소. 아직 없음
    static let termsOfServiceURL: URL? = nil

    struct Item: Equatable, Identifiable {
        let title: String
        let url: URL
        var id: String { title }
    }

    /// 지금 상수 기준으로 보일 줄
    static var visibleItems: [Item] {
        visibleItems(privacyPolicy: privacyPolicyURL, termsOfService: termsOfServiceURL)
    }

    /// 주소가 있는 줄만 순서대로 돌려준다.
    static func visibleItems(privacyPolicy: URL?, termsOfService: URL?) -> [Item] {
        [
            privacyPolicy.map { Item(title: "개인정보 처리방침", url: $0) },
            termsOfService.map { Item(title: "이용약관", url: $0) },
        ].compactMap { $0 }
    }
}
