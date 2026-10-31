import Foundation

nonisolated struct StoredPhotoPaths: Sendable, Equatable {
    let photoPath: String
    let thumbnailPath: String

    var all: [String] { [photoPath, thumbnailPath] }
}

/// 우표 사진 파일을 앱 폴더에 저장한다. DB에는 `baseURL` 기준 상대 경로만 남긴다.
///
/// 파일 이름은 매번 새 UUID를 쓴다. 업로드 대기 중인 CKAsset은 올리는 순간 파일을 읽으므로,
/// 같은 이름을 덮어쓰면 다른 사진이 올라갈 수 있기 때문.
nonisolated final class StampFileStore: Sendable {
    static let photosFolder = "Photos"
    static let thumbnailsFolder = "Thumbnails"

    static var defaultBaseURL: URL {
        URL.applicationSupportDirectory.appending(path: "Stamps", directoryHint: .isDirectory)
    }

    let baseURL: URL

    init(baseURL: URL = StampFileStore.defaultBaseURL) {
        self.baseURL = baseURL
    }

    func save(_ photo: ProcessedPhoto) throws -> StoredPhotoPaths {
        let name = "\(UUID().uuidString).heic"
        let paths = StoredPhotoPaths(
            photoPath: "\(Self.photosFolder)/\(name)",
            thumbnailPath: "\(Self.thumbnailsFolder)/\(name)"
        )
        do {
            try write(photo.photo, to: paths.photoPath)
            try write(photo.thumbnail, to: paths.thumbnailPath)
        } catch {
            remove(paths.all)
            throw error
        }
        return paths
    }

    func url(for relativePath: String) -> URL {
        baseURL.appending(path: relativePath, directoryHint: .notDirectory)
    }

    /// 없는 파일은 무시한다.
    func remove(_ relativePaths: [String]) {
        for path in relativePaths {
            try? FileManager.default.removeItem(at: url(for: path))
        }
    }

    private func write(_ data: Data, to relativePath: String) throws {
        let fileURL = url(for: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // complete로 하면 잠긴 상태의 백그라운드 동기화가 파일을 읽지 못한다.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
