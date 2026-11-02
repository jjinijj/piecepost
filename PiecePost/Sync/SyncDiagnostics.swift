import CloudKit
import Foundation

/// 동기화 진단 로그에 쓰는 문구. 개수·상태·오류 코드만 만든다(불변 규칙 8: 날짜·기록·레코드 이름 없음).
/// CloudKit 서버 없이 확인할 수 있게 엔진과 떼어 둔다.
enum SyncDiagnostics {
    /// 엔진 대기 목록의 개수만 센다. 예: `엔진 대기: 저장 1, 삭제 0, 존 0`
    static func pendingSummary(
        recordZoneChanges: [CKSyncEngine.PendingRecordZoneChange],
        databaseChanges: [CKSyncEngine.PendingDatabaseChange]
    ) -> String {
        var saves = 0, deletes = 0
        for change in recordZoneChanges {
            switch change {
            case .saveRecord: saves += 1
            case .deleteRecord: deletes += 1
            @unknown default: break
            }
        }
        return "엔진 대기: 저장 \(saves), 삭제 \(deletes), 존 \(databaseChanges.count)"
    }

    /// 보낼 묶음에 담은 개수. 예: `보낼 묶음: 저장 1, 삭제 0`
    static func batchSummary(saves: Int, deletes: Int) -> String {
        "보낼 묶음: 저장 \(saves), 삭제 \(deletes)"
    }

    /// iCloud 계정 상태 이름. 예: `iCloud 계정: available`
    static func accountStatusLine(_ status: CKAccountStatus) -> String {
        let name: String
        switch status {
        case .available: name = "available"
        case .noAccount: name = "noAccount"
        case .restricted: name = "restricted"
        case .temporarilyUnavailable: name = "temporarilyUnavailable"
        case .couldNotDetermine: name = "couldNotDetermine"
        @unknown default: name = "unknown(\(status.rawValue))"
        }
        return "iCloud 계정: \(name)"
    }

    /// 보내기 시작 이유. 엔진이 스스로 시작했는지, "지금 보내기"로 시작했는지 가린다.
    static func sendStartLine(_ reason: CKSyncEngine.SyncReason) -> String {
        switch reason {
        case .scheduled: "보내기 시작(자동)"
        case .manual: "보내기 시작(수동)"
        @unknown default: "보내기 시작"
        }
    }
}
