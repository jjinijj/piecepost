import CloudKit
import Testing
@testable import PiecePost

/// 기획서 settings-erase-records 결정 5·완료 기준 9.
@MainActor
struct ZoneDeletionActionTests {
    @Test func deletedErasesLocal() {
        #expect(ZoneDeletionAction.action(for: .deleted, isPaused: false) == .eraseLocal)
    }

    @Test func purgedErasesLocal() {
        #expect(ZoneDeletionAction.action(for: .purged, isPaused: false) == .eraseLocal)
    }

    @Test func encryptedDataResetKeepsLocal() {
        #expect(ZoneDeletionAction.action(for: .encryptedDataReset, isPaused: false) == .keepLocal)
    }

    /// 계정 변경으로 멈춘 동안은 이유와 상관없이 반영하지 않는다.
    @Test func pausedIgnoresEveryReason() {
        for reason in [CKDatabase.DatabaseChange.Deletion.Reason.deleted, .purged, .encryptedDataReset] {
            #expect(ZoneDeletionAction.action(for: reason, isPaused: true) == .ignoreWhilePaused)
        }
    }
}
