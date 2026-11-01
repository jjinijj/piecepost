import Foundation

/// 받은 변경을 로컬에 반영하지 못한 레코드 이름 목록.
///
/// CKSyncEngine은 콜백이 끝나면 "여기까지 받았다"는 위치를 앞으로 옮기므로, 반영에 실패한 레코드는
/// 다음 가져오기에서 다시 오지 않는다. 그래서 이름을 파일에 남겨 두고 따로 다시 받는다.
/// 레코드 이름에 날짜가 들어 있으므로 로그에는 개수만 남긴다(불변 규칙 8).
nonisolated final class ReceiveRetryList: Sendable {
    static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Sync", directoryHint: .isDirectory)
            .appending(path: "receive-retry.json", directoryHint: .notDirectory)
    }

    private let store: SyncStateStore

    init(fileURL: URL = ReceiveRetryList.defaultFileURL) {
        store = SyncStateStore(fileURL: fileURL)
    }

    /// 파일이 없거나 깨졌으면 빈 목록. 깨진 파일은 지운다.
    func names() -> Set<String> {
        do {
            return try store.load(Set<String>.self) ?? []
        } catch {
            store.clear()
            return []
        }
    }

    func add(_ name: String) throws {
        var current = names()
        guard current.insert(name).inserted else { return }
        try store.save(current)
    }

    func remove(_ removed: some Sequence<String>) throws {
        var current = names()
        let before = current.count
        current.subtract(removed)
        guard current.count != before else { return }
        if current.isEmpty {
            store.clear()
        } else {
            try store.save(current)
        }
    }
}
