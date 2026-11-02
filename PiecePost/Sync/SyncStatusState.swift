import Foundation

/// 동기화 상태를 만드는 재료. 엔진이 고치고, 화면에는 `status`만 보낸다.
///
/// 여러 상태가 겹칠 수 있어서(예: 용량 부족인데 계정이 바뀜) 따로 들고 있다가 우선순위로 하나를 고른다.
struct SyncStatusState: Equatable {
    /// 엔진을 만들었는지. 만들기 전에는 "연결 전"
    var isStarted = false
    var account: SyncAccountCondition = .unknown
    /// 기억한 계정과 다른 Apple ID라 동기화를 멈췄는지
    var isPausedForAccountChange = false
    var isQuotaExceeded = false
    var isSyncing = false
    /// 판단 분기에 없는 저장 실패 코드. 다음 보내기·가져오기가 시작되면 지운다
    var errorCode: Int?

    /// 우선순위: iCloud 꺼짐 > 일시 사용 불가 > 계정 변경됨 > 용량 부족 > 동기화 중 > 오류 > 정상.
    /// 계정을 쓸 수 없는 상태를 먼저 보여 준다. 다른 Apple ID에서 로그아웃하면 "iCloud 꺼짐"이 보이고,
    /// 다시 그 계정으로 로그인하면 "계정 변경됨"으로 돌아온다.
    var status: SyncStatus {
        guard isStarted else { return .notStarted }
        switch account {
        case .signedOut: return .iCloudUnavailable
        case .temporarilyUnavailable: return .iCloudTemporarilyUnavailable
        case .unknown, .available: break
        }
        if isPausedForAccountChange { return .accountChanged }
        if isQuotaExceeded { return .quotaExceeded }
        if isSyncing { return .syncing }
        if let errorCode { return .error(code: errorCode) }
        return .idle
    }

    /// 보낸 결과 한 묶음을 반영한다. 용량 부족 실패가 있으면 "용량 부족", 없고 하나라도 성공했으면 "용량 부족"을 푼다.
    mutating func recordSendResult(succeeded: Int, quotaFailures: Int) {
        if quotaFailures > 0 {
            isQuotaExceeded = true
        } else if succeeded > 0 {
            isQuotaExceeded = false
        }
    }
}
