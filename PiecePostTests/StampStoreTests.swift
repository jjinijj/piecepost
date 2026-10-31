import Foundation
import SwiftData
import Testing
@testable import PiecePost

@MainActor
struct StampStoreTests {
    private let container: ModelContainer
    private let fileStore: StampFileStore
    private let store: StampStore
    private let recorder = ChangeRecorder()
    private var changes: [String] { recorder.dates }

    private let created = Date(timeIntervalSince1970: 1_800_000_000)
    private let later = Date(timeIntervalSince1970: 1_800_000_600)
    // StampStore는 이미지를 해석하지 않으므로 임의 바이트로 충분하다.
    private let samplePhoto = ProcessedPhoto(photo: Data([1, 2, 3]), thumbnail: Data([4, 5]))

    init() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: Stamp.self, configurations: configuration)
        fileStore = StampFileStore(
            baseURL: URL.temporaryDirectory.appending(path: "StampStoreTests-\(UUID().uuidString)")
        )
        let recorder = recorder
        store = StampStore(context: container.mainContext, fileStore: fileStore) {
            recorder.dates.append($0)
        }
    }

    @discardableResult
    private func makeStamp(date: String = "2026-11-18", note: String = "맑음") throws -> Stamp {
        try store.create(date: date, note: note, photo: samplePhoto, now: created)
    }

    private func fileExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: fileStore.url(for: path).path(percentEncoded: false))
    }

    private func storedFileCount() -> Int {
        let folders = [StampFileStore.photosFolder, StampFileStore.thumbnailsFolder]
        return folders.reduce(0) { count, folder in
            let url = fileStore.baseURL.appending(path: folder)
            return count + ((try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)))?.count ?? 0)
        }
    }

    // MARK: 생성

    @Test func createMarksForFullUpload() throws {
        let stamp = try makeStamp(note: "  바다\n산책  ")
        #expect(stamp.note == "바다 산책")
        #expect(stamp.needsUpload)
        #expect(stamp.photoNeedsUpload)
        #expect(!stamp.pendingDeletion)
        #expect(stamp.systemFields == nil)
        #expect(stamp.schemaVersion == 1)
        #expect(stamp.createdAt == created && stamp.updatedAt == created)
        #expect(changes == ["2026-11-18"])
    }

    @Test func createWritesPhotoFiles() throws {
        let stamp = try makeStamp()
        #expect(stamp.photoPath.hasPrefix("Photos/"))
        #expect(stamp.thumbnailPath.hasPrefix("Thumbnails/"))
        #expect(try Data(contentsOf: fileStore.url(for: stamp.photoPath)) == samplePhoto.photo)
        #expect(try Data(contentsOf: fileStore.url(for: stamp.thumbnailPath)) == samplePhoto.thumbnail)
    }

    @Test func createRejectsDuplicateDateWithoutOverwritingOrLeavingFiles() throws {
        try makeStamp(note: "처음")
        #expect(storedFileCount() == 2)
        #expect(throws: StampStoreError.alreadyExists) {
            try store.create(date: "2026-11-18", note: "덮어쓰기", photo: samplePhoto)
        }
        #expect(try store.stamp(for: "2026-11-18")?.note == "처음")
        #expect(try store.visibleStamps().count == 1)
        #expect(storedFileCount() == 2)
    }

    @Test func createRequiresValidDateAndPhoto() {
        #expect(throws: StampStoreError.invalidDate) {
            try store.create(date: "2026-02-30", note: "", photo: samplePhoto)
        }
        #expect(throws: StampStoreError.missingPhoto) {
            try store.create(date: "2026-11-18", note: "", photo: ProcessedPhoto(photo: Data(), thumbnail: Data([1])))
        }
        #expect(changes.isEmpty)
        #expect(storedFileCount() == 0)
    }

    // MARK: 기록 수정

    @Test func updateNoteKeepsPhotoFilesAndUploadFlag() throws {
        let stamp = try makeStamp()
        let photoPath = stamp.photoPath
        let thumbnailPath = stamp.thumbnailPath
        // 업로드 완료 상태를 흉내 낸다.
        stamp.systemFields = Data([1])
        stamp.needsUpload = false
        stamp.photoNeedsUpload = false

        try store.updateNote(date: "2026-11-18", note: "흐림", now: later)

        #expect(stamp.note == "흐림")
        #expect(stamp.updatedAt == later)
        #expect(stamp.createdAt == created)
        #expect(stamp.needsUpload)
        #expect(!stamp.photoNeedsUpload)
        #expect(stamp.photoPath == photoPath && stamp.thumbnailPath == thumbnailPath)
        #expect(fileExists(photoPath) && fileExists(thumbnailPath))
    }

    @Test func updateNoteWithSameTextDoesNothing() throws {
        let stamp = try makeStamp(note: "맑음")
        stamp.needsUpload = false
        try store.updateNote(date: "2026-11-18", note: " 맑음 ", now: later)
        #expect(!stamp.needsUpload)
        #expect(stamp.updatedAt == created)
        #expect(changes == ["2026-11-18"])
    }

    @Test func updateNoteOnMissingDateThrows() {
        #expect(throws: StampStoreError.notFound) {
            try store.updateNote(date: "2026-11-18", note: "흐림")
        }
    }

    // MARK: 삭제

    @Test func deleteNeverUploadedRemovesRowAndFiles() throws {
        let stamp = try makeStamp()
        let paths = [stamp.photoPath, stamp.thumbnailPath]

        try store.delete(date: "2026-11-18")

        #expect(try store.stamp(for: "2026-11-18") == nil)
        #expect(!paths.contains(where: fileExists))
        #expect(changes == ["2026-11-18", "2026-11-18"])
    }

    @Test func deleteUploadedMarksPendingDeletionAndKeepsFiles() throws {
        let stamp = try makeStamp()
        stamp.systemFields = Data([1])
        stamp.needsUpload = false

        try store.delete(date: "2026-11-18")

        #expect(stamp.pendingDeletion)
        #expect(stamp.needsUpload)
        #expect(fileExists(stamp.photoPath) && fileExists(stamp.thumbnailPath))
        #expect(try store.visibleStamps().isEmpty)
        #expect(throws: StampStoreError.notFound) { try store.delete(date: "2026-11-18") }
        #expect(throws: StampStoreError.notFound) { try store.updateNote(date: "2026-11-18", note: "x") }
    }

    @Test func recreateOnPendingDeletionReusesSystemFieldsAndReplacesFiles() throws {
        let stamp = try makeStamp(note: "이전")
        let oldPaths = [stamp.photoPath, stamp.thumbnailPath]
        stamp.systemFields = Data([1])
        try store.delete(date: "2026-11-18")

        let newPhoto = ProcessedPhoto(photo: Data([9, 9]), thumbnail: Data([8]))
        let recreated = try store.create(date: "2026-11-18", note: "새로", photo: newPhoto, now: later)

        #expect(recreated.systemFields == Data([1]))
        #expect(!recreated.pendingDeletion)
        #expect(recreated.note == "새로")
        #expect(recreated.createdAt == later)
        #expect(recreated.photoNeedsUpload)
        #expect(!oldPaths.contains(recreated.photoPath))
        #expect(try Data(contentsOf: fileStore.url(for: recreated.photoPath)) == newPhoto.photo)
        #expect(!oldPaths.contains(where: fileExists))
        #expect(storedFileCount() == 2)
        #expect(try store.visibleStamps().count == 1)
    }

    // MARK: 조회

    @Test func visibleStampsAreSortedNewestFirst() throws {
        try makeStamp(date: "2026-11-01")
        try makeStamp(date: "2026-11-18")
        try makeStamp(date: "2025-12-31")
        #expect(try store.visibleStamps().map(\.date) == ["2026-11-18", "2026-11-01", "2025-12-31"])
    }
}

@MainActor
private final class ChangeRecorder {
    var dates: [String] = []
}
