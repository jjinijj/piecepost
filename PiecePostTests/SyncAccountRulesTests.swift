import CloudKit
import Foundation
import Testing
@testable import PiecePost

@MainActor
struct SyncAccountRulesTests {
    // MARK: 계정 상태

    @Test func availableIsAvailable() {
        #expect(SyncAccountRules.condition(for: .available) == .available)
    }

    @Test func noAccountAndRestrictedAreSignedOut() {
        #expect(SyncAccountRules.condition(for: .noAccount) == .signedOut)
        #expect(SyncAccountRules.condition(for: .restricted) == .signedOut)
    }

    @Test func temporarilyUnavailableAndCouldNotDetermineAreTemporary() {
        #expect(SyncAccountRules.condition(for: .temporarilyUnavailable) == .temporarilyUnavailable)
        #expect(SyncAccountRules.condition(for: .couldNotDetermine) == .temporarilyUnavailable)
    }

    // MARK: 계정 비교

    @Test func firstSyncRemembersCurrentAccount() {
        let result = SyncAccountRules.evaluate(current: "A", stored: nil, previous: nil)
        #expect(result == SyncAccountEvaluation(isDifferentAccount: false, fingerprintToStore: "A"))
    }

    @Test func sameAccountChangesNothing() {
        let result = SyncAccountRules.evaluate(current: "A", stored: "A", previous: nil)
        #expect(result == SyncAccountEvaluation(isDifferentAccount: false, fingerprintToStore: nil))
    }

    @Test func differentAccountPausesAndKeepsRememberedAccount() {
        let result = SyncAccountRules.evaluate(current: "B", stored: "A", previous: nil)
        #expect(result == SyncAccountEvaluation(isDifferentAccount: true, fingerprintToStore: nil))
    }

    @Test func returningToRememberedAccountResumes() {
        // 엔진이 B → A 전환을 알려도 기준은 기억한 A
        let result = SyncAccountRules.evaluate(current: "A", stored: "A", previous: "B")
        #expect(result == SyncAccountEvaluation(isDifferentAccount: false, fingerprintToStore: nil))
    }

    @Test func storedAccountWinsOverEnginePreviousAccount() {
        let result = SyncAccountRules.evaluate(current: "B", stored: "A", previous: "B")
        #expect(result.isDifferentAccount)
    }

    @Test func enginePreviousAccountIsBaselineWhenNothingStored() {
        // 기억하기 전 빌드에서 올라온 경우: 엔진 상태가 기억하는 A가 마지막으로 동기화한 계정
        let result = SyncAccountRules.evaluate(current: "B", stored: nil, previous: "A")
        #expect(result == SyncAccountEvaluation(isDifferentAccount: true, fingerprintToStore: "A"))
    }

    @Test func firstAccountWaitsForSyncWhenEngineHasHistory() {
        // 기억하기 전 빌드에서 올라옴: 엔진 상태의 계정이 다를 수 있어 지금은 기억하지 않는다
        let result = SyncAccountRules.evaluate(current: "B", stored: nil, previous: nil, engineHasHistory: true)
        #expect(result == SyncAccountEvaluation(
            isDifferentAccount: false,
            fingerprintToStore: nil,
            fingerprintToStoreAfterSync: "B"
        ))
    }

    @Test func engineHistoryDoesNotMatterOnceRemembered() {
        let result = SyncAccountRules.evaluate(current: "B", stored: "A", previous: nil, engineHasHistory: true)
        #expect(result == SyncAccountEvaluation(isDifferentAccount: true, fingerprintToStore: nil))
    }

    @Test func fingerprintIsStableAndHidesName() {
        let name = "_0123456789abcdef"
        let fingerprint = SyncAccountRules.fingerprint(ofUserRecordName: name)
        #expect(fingerprint == SyncAccountRules.fingerprint(ofUserRecordName: name))
        #expect(fingerprint != SyncAccountRules.fingerprint(ofUserRecordName: "_other"))
        #expect(!fingerprint.contains(name))
        #expect(fingerprint.count == 64)
    }

    // MARK: 기억한 계정 파일

    private func makeStore() -> SyncAccountStore {
        SyncAccountStore(
            fileURL: URL.temporaryDirectory
                .appending(path: "SyncAccountStoreTests-\(UUID().uuidString)")
                .appending(path: "account.json")
        )
    }

    @Test func storeStartsEmpty() {
        #expect(makeStore().load() == nil)
    }

    @Test func storeLoadsSavedFingerprint() throws {
        let store = makeStore()
        try store.save("abc")
        #expect(store.load() == "abc")
    }

    @Test func corruptStoreLoadsNil() throws {
        let url = URL.temporaryDirectory
            .appending(path: "SyncAccountStoreTests-\(UUID().uuidString)")
            .appending(path: "account.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("깨진 파일".utf8).write(to: url)
        let store = SyncAccountStore(fileURL: url)
        #expect(store.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    // MARK: 삭제 실패

    @Test func deleteFailureActions() {
        #expect(DeleteFailureAction.action(for: .networkUnavailable) == .keepPendingForRetry)
        #expect(DeleteFailureAction.action(for: .networkFailure) == .keepPendingForRetry)
        #expect(DeleteFailureAction.action(for: .quotaExceeded) == .quotaExceeded)
        #expect(DeleteFailureAction.action(for: .notAuthenticated) == .signedOut)
        #expect(DeleteFailureAction.action(for: .unknownItem) == .treatAsDeleted)
        #expect(DeleteFailureAction.action(for: .permissionFailure) == .unhandled)
        #expect(DeleteFailureAction.action(for: .zoneNotFound) == .unhandled)
    }
}
