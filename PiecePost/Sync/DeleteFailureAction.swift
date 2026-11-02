import CloudKit
import Foundation

/// 삭제 실패(`failedRecordDeletes`)를 어떻게 처리할지. CLAUDE.md 판단 분기를 따른다.
enum DeleteFailureAction: Equatable {
    /// 네트워크·일시 오류. 삭제 대기를 유지하고 재시도는 엔진에 맡긴다
    case keepPendingForRetry
    /// 용량 부족. 저장 실패와 같게 "용량 부족", 삭제 대기 유지
    case quotaExceeded
    /// 인증 안 됨. "iCloud 꺼짐", 삭제 대기 유지
    case signedOut
    /// 서버에 이미 없음. 삭제 성공과 같게 로컬 행·사진 파일을 지운다
    case treatAsDeleted
    /// 판단 분기에 없는 코드. 로그만 남기고 삭제 대기 유지(처리 방식은 정하지 않음)
    case unhandled

    static func action(for code: CKError.Code) -> DeleteFailureAction {
        switch code {
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited:
            .keepPendingForRetry
        case .quotaExceeded: .quotaExceeded
        case .notAuthenticated: .signedOut
        case .unknownItem: .treatAsDeleted
        default: .unhandled
        }
    }
}
