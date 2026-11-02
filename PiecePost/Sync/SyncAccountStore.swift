import Foundation

/// 마지막으로 동기화한 iCloud 계정의 지문(`SyncAccountRules.fingerprint`)을 기기에 기억한다.
/// 계정 식별자 원문은 저장하지 않는다. 로그에도 남기지 않는다(불변 규칙 8).
nonisolated final class SyncAccountStore: Sendable {
    static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Sync", directoryHint: .isDirectory)
            .appending(path: "account.json", directoryHint: .notDirectory)
    }

    private let store: SyncStateStore

    init(fileURL: URL = SyncAccountStore.defaultFileURL) {
        store = SyncStateStore(fileURL: fileURL)
    }

    /// 없거나 깨졌으면 nil. 깨진 파일은 지운다(엔진이 알려 주는 이전 계정이 기준이 된다).
    func load() -> String? {
        do {
            return try store.load(String.self)
        } catch {
            store.clear()
            return nil
        }
    }

    func save(_ fingerprint: String) throws {
        try store.save(fingerprint)
    }
}
