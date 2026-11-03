import Foundation

/// 설정 화면 "버전" 줄의 문구. `CFBundleShortVersionString (CFBundleVersion)` 형식.
enum AppVersion {
    static var current: String {
        text(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    /// 빌드 설정으로 두 값이 항상 들어 있다. 없으면 있는 값만 보여 준다.
    static func text(infoDictionary: [String: Any]) -> String {
        let version = infoDictionary["CFBundleShortVersionString"] as? String
        let build = infoDictionary["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return version
        case let (nil, build?): return "(\(build))"
        case (nil, nil): return ""
        }
    }
}
