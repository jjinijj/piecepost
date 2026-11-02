import Foundation
import Testing
@testable import PiecePost

@MainActor
struct SyncStatusStateTests {
    private func started(_ change: (inout SyncStatusState) -> Void = { _ in }) -> SyncStatusState {
        var state = SyncStatusState()
        state.isStarted = true
        change(&state)
        return state
    }

    @Test func notStartedBeforeEngine() {
        var state = SyncStatusState()
        state.account = .signedOut
        #expect(state.status == .notStarted)
    }

    @Test func startedWithNothingIsIdle() {
        let available = started { $0.account = .available }
        #expect(started().status == .idle)
        #expect(available.status == .idle)
    }

    @Test func signedOutShowsICloudOff() {
        let state = started { $0.account = .signedOut }
        #expect(state.status == .iCloudUnavailable)
    }

    @Test func temporarilyUnavailableIsNotShownAsOff() {
        let state = started { $0.account = .temporarilyUnavailable }
        #expect(state.status == .iCloudTemporarilyUnavailable)
        #expect(state.status.label == "iCloud 일시 사용 불가")
    }

    @Test func pausedShowsAccountChanged() {
        let state = started {
            $0.account = .available
            $0.isPausedForAccountChange = true
            $0.isSyncing = true
            $0.isQuotaExceeded = true
        }
        #expect(state.status == .accountChanged)
        #expect(state.status.label == "계정 변경됨")
    }

    @Test func signedOutWinsOverPaused() {
        let state = started {
            $0.account = .signedOut
            $0.isPausedForAccountChange = true
        }
        #expect(state.status == .iCloudUnavailable)
    }

    @Test func quotaWinsOverSyncingAndError() {
        let state = started {
            $0.isQuotaExceeded = true
            $0.isSyncing = true
            $0.errorCode = 7
        }
        #expect(state.status == .quotaExceeded)
    }

    @Test func syncingWinsOverError() {
        let syncing = started { $0.isSyncing = true; $0.errorCode = 7 }
        let failed = started { $0.errorCode = 7 }
        #expect(syncing.status == .syncing)
        #expect(failed.status == .error(code: 7))
    }

    // MARK: 용량 부족

    @Test func quotaFailureSetsQuotaExceeded() {
        var state = started()
        state.recordSendResult(succeeded: 2, quotaFailures: 1)
        #expect(state.status == .quotaExceeded)
    }

    @Test func successWithoutQuotaFailureClearsQuota() {
        var state = started { $0.isQuotaExceeded = true }
        state.recordSendResult(succeeded: 1, quotaFailures: 0)
        #expect(state.status == .idle)
    }

    @Test func emptyResultKeepsQuota() {
        var state = started { $0.isQuotaExceeded = true }
        state.recordSendResult(succeeded: 0, quotaFailures: 0)
        #expect(state.isQuotaExceeded)
    }

    // MARK: 포그라운드 진입

    @Test func launchCountsAsHandledEntry() {
        var gate = ForegroundEntryGate()
        let handled = gate.shouldHandleActivation()
        #expect(!handled)
    }

    @Test func handlesOncePerForegroundEntry() {
        var gate = ForegroundEntryGate()
        gate.didEnterBackground()
        let first = gate.shouldHandleActivation()
        // 같은 진입 안에서 다시 활성이 돼도(제어 센터 등) 처리하지 않는다
        let second = gate.shouldHandleActivation()
        let third = gate.shouldHandleActivation()
        #expect(first)
        #expect(!second)
        #expect(!third)
    }

    @Test func nextForegroundEntryHandlesAgain() {
        var gate = ForegroundEntryGate()
        gate.didEnterBackground()
        _ = gate.shouldHandleActivation()
        gate.didEnterBackground()
        let handled = gate.shouldHandleActivation()
        #expect(handled)
    }
}
