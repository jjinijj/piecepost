import CloudKit
import Foundation
import Testing
@testable import PiecePost

/// 기획서 settings-erase-records 결정 2·3, 완료 기준 5: 서버 레코드를 다 지워야 로컬을 지우고,
/// 일부만 지웠으면 '일부만', 하나도 못 지웠으면 '실패'. `unknownItem` 은 지운 것으로 본다.
@MainActor
struct RecordEraseOutcomeTests {
    private func id(_ date: String) -> CKRecord.ID {
        StampRecordMapper.recordID(for: date)
    }

    private var ids: [CKRecord.ID] { [id("2026-11-01"), id("2026-11-02"), id("2026-11-03")] }

    // MARK: 판정

    @Test func noRecordsIsErased() {
        #expect(RecordEraseOutcome.outcome(requested: [], results: [:]) == .erased)
    }

    @Test func allDeletedIsErased() {
        let results = Dictionary(uniqueKeysWithValues: ids.map { ($0, Result<Void, any Error>.success(())) })
        #expect(RecordEraseOutcome.outcome(requested: ids, results: results) == .erased)
    }

    @Test func unknownItemCountsAsDeleted() {
        var results = Dictionary(uniqueKeysWithValues: ids.map { ($0, Result<Void, any Error>.success(())) })
        results[ids[1]] = .failure(CKError(.unknownItem))
        #expect(RecordEraseOutcome.outcome(requested: ids, results: results) == .erased)

        let allGone = Dictionary(uniqueKeysWithValues: ids.map { ($0, Result<Void, any Error>.failure(CKError(.unknownItem))) })
        #expect(RecordEraseOutcome.outcome(requested: ids, results: allGone) == .erased)
    }

    @Test func someFailedIsPartial() {
        var results = Dictionary(uniqueKeysWithValues: ids.map { ($0, Result<Void, any Error>.success(())) })
        results[ids[2]] = .failure(CKError(.networkFailure))
        #expect(RecordEraseOutcome.outcome(requested: ids, results: results) == .partial(.none))
    }

    @Test func noneDeletedIsFailed() {
        let results = Dictionary(uniqueKeysWithValues: ids.map { ($0, Result<Void, any Error>.failure(CKError(.networkUnavailable))) })
        #expect(RecordEraseOutcome.outcome(requested: ids, results: results) == .failed(.none))
    }

    /// 결과가 없는 레코드는 지웠는지 알 수 없으므로 실패로 본다.
    @Test func missingResultIsFailure() {
        let results: [CKRecord.ID: Result<Void, any Error>] = [ids[0]: .success(())]
        #expect(RecordEraseOutcome.outcome(requested: ids, results: results) == .partial(.none))
        #expect(RecordEraseOutcome.outcome(requested: ids, results: [:]) == .failed(.none))
    }

    // MARK: 동기화 상태 반영

    @Test func notAuthenticatedSignsOut() {
        let results = Dictionary(uniqueKeysWithValues: ids.map { ($0, Result<Void, any Error>.failure(CKError(.notAuthenticated))) })
        #expect(RecordEraseOutcome.outcome(requested: ids, results: results) == .failed(.signedOut))
    }

    @Test func quotaExceededMarksQuota() {
        var results = Dictionary(uniqueKeysWithValues: ids.map { ($0, Result<Void, any Error>.success(())) })
        results[ids[0]] = .failure(CKError(.quotaExceeded))
        #expect(RecordEraseOutcome.outcome(requested: ids, results: results) == .partial(.quotaExceeded))
    }

    @Test func signedOutWinsOverQuota() {
        let results: [CKRecord.ID: Result<Void, any Error>] = [
            ids[0]: .failure(CKError(.quotaExceeded)),
            ids[1]: .failure(CKError(.notAuthenticated)),
            ids[2]: .failure(CKError(.networkFailure)),
        ]
        #expect(RecordEraseOutcome.outcome(requested: ids, results: results) == .failed(.signedOut))
    }

    @Test func unhandledCodeFailsWithoutStatusChange() {
        let results = Dictionary(uniqueKeysWithValues: ids.map { ($0, Result<Void, any Error>.failure(CKError(.permissionFailure))) })
        #expect(RecordEraseOutcome.outcome(requested: ids, results: results) == .failed(.none))
    }

    // MARK: 목록 실패

    @Test func listingFailureIsFailed() {
        #expect(RecordEraseOutcome.outcome(forListingFailure: CKError(.networkUnavailable)) == .failed(.none))
        #expect(RecordEraseOutcome.outcome(forListingFailure: CKError(.notAuthenticated)) == .failed(.signedOut))
        #expect(RecordEraseOutcome.outcome(forListingFailure: NSError(domain: "x", code: 1)) == .failed(.none))
    }

    // MARK: 묶음 전체가 던졌을 때

    @Test func thrownErrorFailsEveryRecordInBatch() {
        let results = RecordEraseOutcome.results(forThrown: CKError(.networkFailure), requested: ids)
        #expect(results.count == 3)
        #expect(RecordEraseOutcome.outcome(requested: ids, results: results) == .failed(.none))
    }

    @Test func partialFailureUsesPerRecordErrors() {
        let error = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: [ids[0]: CKError(.unknownItem), ids[1]: CKError(.quotaExceeded)] as [AnyHashable: any Error],
        ])
        let results = RecordEraseOutcome.results(forThrown: error, requested: ids)
        // ids[0] 은 이미 없음(지운 것), ids[1] 은 용량 부족, ids[2] 는 결과를 확인할 수 없어 실패
        #expect(RecordEraseOutcome.outcome(requested: ids, results: results) == .partial(.quotaExceeded))
    }
}
