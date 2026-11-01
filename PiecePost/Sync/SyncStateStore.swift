import Foundation

/// CKSyncEngine 상태("어디까지 받았나" 등)를 파일로 저장·복원한다.
/// 복원하면 다음 실행 때 전체를 다시 내려받지 않는다.
nonisolated final class SyncStateStore: Sendable {
    static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Sync", directoryHint: .isDirectory)
            .appending(path: "engine-state.json", directoryHint: .notDirectory)
    }

    let fileURL: URL

    init(fileURL: URL = SyncStateStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// 파일이 없으면 nil. 파일이 깨졌으면 오류를 던진다(호출하는 쪽에서 지우고 처음부터 시작).
    func load<Value: Decodable>(_ type: Value.Type) throws -> Value? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(type, from: data)
    }

    func save(_ value: some Encodable) throws {
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // 잠긴 상태의 백그라운드 동기화에서도 읽고 쓸 수 있어야 한다.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
