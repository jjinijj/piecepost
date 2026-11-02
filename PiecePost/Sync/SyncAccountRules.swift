import CloudKit
import CryptoKit
import Foundation

/// iCloud 계정이 지금 어떤 상태인지. 계정 변경(다른 Apple ID)은 따로 `SyncStatusState.isPausedForAccountChange`로 둔다.
enum SyncAccountCondition: Equatable {
    /// 아직 확인하지 않음
    case unknown
    case available
    /// noAccount·restricted, 엔진의 로그아웃 알림, 저장 `notAuthenticated` → "iCloud 꺼짐"
    case signedOut
    /// temporarilyUnavailable·couldNotDetermine → 오프라인처럼 처리, "iCloud 일시 사용 불가"
    case temporarilyUnavailable
}

/// 계정 비교 결과.
struct SyncAccountEvaluation: Equatable {
    /// 기억한 계정과 다른 계정이라 동기화를 멈춰야 하는지
    let isDifferentAccount: Bool
    /// 기기에 새로 기억할 계정 지문. 바꿀 것이 없으면 nil
    let fingerprintToStore: String?
}

/// 계정 상태와 계정 비교 규칙. CloudKit 서버 없이 확인할 수 있게 엔진과 떼어 둔다.
enum SyncAccountRules {
    /// 계정 상태 값을 앱이 쓰는 상태로 바꾼다.
    static func condition(for status: CKAccountStatus) -> SyncAccountCondition {
        switch status {
        case .available: .available
        case .noAccount, .restricted: .signedOut
        case .temporarilyUnavailable, .couldNotDetermine: .temporarilyUnavailable
        @unknown default: .temporarilyUnavailable
        }
    }

    /// 지금 계정을 마지막으로 동기화한 계정과 비교한다.
    ///
    /// 기준은 기기에 기억한 계정이고, 없으면 엔진이 알려 준 이전 계정(엔진 상태가 기억하는 마지막 계정)이다.
    /// 둘 다 없으면 처음 동기화하는 것이므로 지금 계정을 기억한다.
    /// - Parameters:
    ///   - current: 지금 계정의 지문
    ///   - stored: 기기에 기억한 계정의 지문
    ///   - previous: 엔진이 계정 전환을 알릴 때 준 이전 계정의 지문
    static func evaluate(current: String, stored: String?, previous: String?) -> SyncAccountEvaluation {
        guard let baseline = stored ?? previous else {
            return SyncAccountEvaluation(isDifferentAccount: false, fingerprintToStore: current)
        }
        // 기억한 것이 없었으면 기준으로 삼은 계정을 기억해 다음 확인에도 쓴다.
        let toStore = stored == nil ? baseline : nil
        return SyncAccountEvaluation(isDifferentAccount: baseline != current, fingerprintToStore: toStore)
    }

    /// 계정 식별자(사용자 레코드 이름)를 그대로 저장하지 않고 비교용 지문으로 바꾼다. 로그에는 지문도 남기지 않는다.
    static func fingerprint(ofUserRecordName name: String) -> String {
        SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
