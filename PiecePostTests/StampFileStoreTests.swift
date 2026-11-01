import Foundation
import Testing
@testable import PiecePost

struct StampFileStoreTests {
    private let fileStore = StampFileStore(
        baseURL: URL.temporaryDirectory.appending(path: "StampFileStoreTests-\(UUID().uuidString)")
    )
    private let photo = ProcessedPhoto(photo: Data([1, 2, 3]), thumbnail: Data([4]))

    @Test func savesUnderSeparateFoldersWithRelativePaths() throws {
        let paths = try fileStore.save(photo)
        #expect(paths.photoPath.hasPrefix("Photos/") && paths.photoPath.hasSuffix(".heic"))
        #expect(paths.thumbnailPath.hasPrefix("Thumbnails/") && paths.thumbnailPath.hasSuffix(".heic"))
        #expect(!paths.photoPath.hasPrefix("/"))
        #expect(try Data(contentsOf: fileStore.url(for: paths.photoPath)) == photo.photo)
        #expect(try Data(contentsOf: fileStore.url(for: paths.thumbnailPath)) == photo.thumbnail)
    }

    @Test func eachSaveUsesNewFileNames() throws {
        let first = try fileStore.save(photo)
        let second = try fileStore.save(photo)
        #expect(first.photoPath != second.photoPath)
        #expect(first.thumbnailPath != second.thumbnailPath)
    }

    @Test func importCopiesFilesUnderNewNames() throws {
        let source = fileStore.baseURL.appending(path: "incoming")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let photoURL = source.appending(path: "photo")
        let thumbnailURL = source.appending(path: "thumbnail")
        try Data([5, 6]).write(to: photoURL)
        try Data([7]).write(to: thumbnailURL)

        let paths = try fileStore.importFiles(photoFrom: photoURL, thumbnailFrom: thumbnailURL)
        // 원본(임시 파일)이 사라져도 복사본은 남아야 한다.
        try FileManager.default.removeItem(at: source)

        #expect(paths.photoPath.hasPrefix("Photos/") && paths.thumbnailPath.hasPrefix("Thumbnails/"))
        #expect(try Data(contentsOf: fileStore.url(for: paths.photoPath)) == Data([5, 6]))
        #expect(try Data(contentsOf: fileStore.url(for: paths.thumbnailPath)) == Data([7]))
    }

    @Test func importFailureLeavesNoFiles() {
        let missing = fileStore.baseURL.appending(path: "없음")
        #expect(throws: (any Error).self) {
            try fileStore.importFiles(photoFrom: missing, thumbnailFrom: missing)
        }
        let photos = fileStore.baseURL.appending(path: StampFileStore.photosFolder)
        let count = (try? FileManager.default.contentsOfDirectory(atPath: photos.path(percentEncoded: false)))?.count ?? 0
        #expect(count == 0)
    }

    @Test func removeDeletesFilesAndIgnoresMissingOnes() throws {
        let paths = try fileStore.save(photo)
        fileStore.remove(paths.all + ["Photos/없는파일.heic"])
        for path in paths.all {
            #expect(!FileManager.default.fileExists(atPath: fileStore.url(for: path).path(percentEncoded: false)))
        }
    }
}
