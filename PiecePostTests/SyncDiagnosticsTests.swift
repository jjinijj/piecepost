import CloudKit
import Foundation
import Testing
@testable import PiecePost

@MainActor
struct SyncDiagnosticsTests {
    private let zoneID = StampRecordMapper.zoneID

    @Test func pendingSummaryEmpty() {
        let line = SyncDiagnostics.pendingSummary(recordZoneChanges: [], databaseChanges: [])
        #expect(line == "엔진 대기: 저장 0, 삭제 0, 존 0")
    }

    @Test func pendingSummaryCountsEachKind() {
        let line = SyncDiagnostics.pendingSummary(
            recordZoneChanges: [
                .saveRecord(StampRecordMapper.recordID(for: "2026-11-01")),
                .saveRecord(StampRecordMapper.recordID(for: "2026-11-02")),
                .deleteRecord(StampRecordMapper.recordID(for: "2026-10-31")),
            ],
            databaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))]
        )
        #expect(line == "엔진 대기: 저장 2, 삭제 1, 존 1")
    }

    /// 불변 규칙 8: 개수만 남기고 날짜·레코드 이름은 남기지 않는다.
    @Test func pendingSummaryHasNoRecordNameOrDate() {
        let line = SyncDiagnostics.pendingSummary(
            recordZoneChanges: [.saveRecord(StampRecordMapper.recordID(for: "2026-11-18"))],
            databaseChanges: []
        )
        #expect(!line.contains("stamp-"))
        #expect(!line.contains("2026"))
        #expect(!line.contains("11-18"))
    }

    @Test func batchSummary() {
        #expect(SyncDiagnostics.batchSummary(saves: 1, deletes: 0) == "보낼 묶음: 저장 1, 삭제 0")
        #expect(SyncDiagnostics.batchSummary(saves: 0, deletes: 2) == "보낼 묶음: 저장 0, 삭제 2")
    }

    @Test func accountStatusLines() {
        #expect(SyncDiagnostics.accountStatusLine(.available) == "iCloud 계정: available")
        #expect(SyncDiagnostics.accountStatusLine(.noAccount) == "iCloud 계정: noAccount")
        #expect(SyncDiagnostics.accountStatusLine(.restricted) == "iCloud 계정: restricted")
        #expect(SyncDiagnostics.accountStatusLine(.temporarilyUnavailable) == "iCloud 계정: temporarilyUnavailable")
        #expect(SyncDiagnostics.accountStatusLine(.couldNotDetermine) == "iCloud 계정: couldNotDetermine")
    }

    @Test func sendStartLines() {
        #expect(SyncDiagnostics.sendStartLine(.scheduled) == "보내기 시작(자동)")
        #expect(SyncDiagnostics.sendStartLine(.manual) == "보내기 시작(수동)")
    }

    @Test func describeKeepsOnlyCKErrorCode() {
        #expect(StampSyncEngine.describe(CKError(.accountTemporarilyUnavailable)) == "CKError 36")
    }
}
