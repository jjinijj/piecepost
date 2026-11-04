import CloudKit
import Foundation

/// 기록 전부 지우기에서 서버 우표 레코드 삭제 결과를 어떻게 처리할지(기획서 settings-erase-records 결정 2·3, 완료 기준 5).
enum RecordEraseOutcome: Equatable {
    /// 서버 레코드가 모두 지워졌거나 이미 없음(0개였던 경우 포함). 이 기기의 우표·사진·로그를 지운다
    case erased
    /// 일부만 지웠다. 이 기기는 지우지 않고 "iCloud에서 일부만 지웠어요." 를 알린다. 다시 누르면 남은 것을 지운다
    case partial(EraseFailureEffect)
    /// 하나도 못 지웠다. 이 기기는 지우지 않고 "지우지 못했어요." 를 알린다
    case failed(EraseFailureEffect)

    /// 레코드 목록을 얻지 못했을 때. 아무것도 지우지 않았으므로 실패다.
    static func outcome(forListingFailure error: any Error) -> RecordEraseOutcome {
        .failed(effect(for: [error]))
    }

    /// - Parameters:
    ///   - requested: 지우라고 보낸 레코드 ID 전부
    ///   - results: 레코드별 삭제 결과. 결과가 없는 레코드는 실패로 본다
    static func outcome(
        requested: [CKRecord.ID],
        results: [CKRecord.ID: Result<Void, any Error>]
    ) -> RecordEraseOutcome {
        var removed = 0
        var failures: [any Error] = []
        for id in requested {
            switch results[id] {
            case .success:
                removed += 1
            case .failure(let error) where (error as? CKError)?.code == .unknownItem:
                // 서버에 이미 없음. 기존 unknownItem 처리처럼 지운 것으로 본다
                removed += 1
            case .failure(let error):
                failures.append(error)
            case nil:
                failures.append(CKError(.internalError))
            }
        }
        if failures.isEmpty { return .erased }
        let effect = effect(for: failures)
        return removed == 0 ? .failed(effect) : .partial(effect)
    }

    /// 묶음 요청 전체가 던졌을 때 레코드별 결과로 바꾼다. 일부 실패(`partialFailure`)면 레코드별 오류를 쓴다.
    /// 오류 목록에 없는 레코드도 성공을 확인할 수 없으므로 같은 오류로 실패 처리한다(다시 누르면 남은 것을 지운다).
    static func results(
        forThrown error: any Error,
        requested: [CKRecord.ID]
    ) -> [CKRecord.ID: Result<Void, any Error>] {
        let partialErrors = (error as? CKError).flatMap { $0.code == .partialFailure ? $0.partialErrorsByItemID : nil }
        var results: [CKRecord.ID: Result<Void, any Error>] = [:]
        for id in requested {
            results[id] = .failure(partialErrors?[id] ?? error)
        }
        return results
    }

    /// 동기화 상태에 반영할 것. 로그아웃이 용량 부족보다 앞선다.
    private static func effect(for errors: [any Error]) -> EraseFailureEffect {
        let codes = errors.compactMap { ($0 as? CKError)?.code }
        if codes.contains(.notAuthenticated) { return .signedOut }
        if codes.contains(.quotaExceeded) { return .quotaExceeded }
        // 네트워크 오류는 상태를 바꾸지 않는다. 그 밖의 코드는 로그만 남긴다(CLAUDE.md 판단 분기, 기획서 결정 3)
        return .none
    }
}

/// 지우기가 실패했을 때 동기화 상태에 반영할 것.
enum EraseFailureEffect: Equatable {
    /// 상태는 그대로(네트워크 오류, 판단 분기에 없는 코드)
    case none
    /// `notAuthenticated` → "iCloud 꺼짐"
    case signedOut
    /// `quotaExceeded` → "용량 부족"
    case quotaExceeded
}
