import Foundation
import Observation

/// 화면에 보여줄 동기화 상태.
enum SyncStatus: Equatable {
    case notStarted
    case idle
    case syncing
    case iCloudUnavailable
    case quotaExceeded
    case error(code: Int)

    var label: String {
        switch self {
        case .notStarted: "연결 전"
        case .idle: "정상"
        case .syncing: "동기화 중"
        case .iCloudUnavailable: "iCloud 꺼짐"
        case .quotaExceeded: "용량 부족"
        case .error(let code): "오류(\(code))"
        }
    }
}

/// 동기화 엔진이 상태와 로그를 쓰고, 화면은 읽기만 한다.
/// 화면이 CloudKit을 직접 다루지 않도록 이 값만 노출한다(불변 규칙 4).
@Observable
final class SyncMonitor {
    var status: SyncStatus = .notStarted
    let log = SyncLog()
}
