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

    @Test func removeDeletesFilesAndIgnoresMissingOnes() throws {
        let paths = try fileStore.save(photo)
        fileStore.remove(paths.all + ["Photos/없는파일.heic"])
        for path in paths.all {
            #expect(!FileManager.default.fileExists(atPath: fileStore.url(for: path).path(percentEncoded: false)))
        }
    }
}
