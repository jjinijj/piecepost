import Foundation
import SwiftData
import Testing
@testable import PiecePost

@MainActor
struct SyncChangeApplierTests {
    private let container: ModelContainer
    private let fileStore: StampFileStore
    private let store: StampStore
    private let applier: SyncChangeApplier
    private let tempFolder: URL

    private let created = Date(timeIntervalSince1970: 1_800_000_000)
    private let later = Date(timeIntervalSince1970: 1_800_000_600)
    private let localPhoto = ProcessedPhoto(photo: Data([1, 1]), thumbnail: Data([2]))

    init() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: Stamp.self, configurations: configuration)
        tempFolder = URL.temporaryDirectory.appending(path: "SyncChangeApplierTests-\(UUID().uuidString)")
        fileStore = StampFileStore(baseURL: tempFolder.appending(path: "Stamps"))
        store = StampStore(context: container.mainContext, fileStore: fileStore)
        applier = SyncChangeApplier(context: container.mainContext, fileStore: fileStore)
    }

    // MARK: 도우미

    /// CloudKit이 넘겨주는 임시 Asset 파일을 흉내 낸다.
    private func received(
        date: String = "2026-11-18",
        note: String = "서버",
        updatedAt: Date? = nil,
        photo: Data = Data([7, 7, 7]),
        thumbnail: Data = Data([8]),
        systemFields: Data = Data([42])
    ) throws -> ReceivedStamp {
        let assets = tempFolder.appending(path: "assets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let photoURL = assets.appending(path: "photo")
        let thumbnailURL = assets.appending(path: "thumbnail")
        try photo.write(to: photoURL)
        try thumbnail.write(to: thumbnailURL)
        return ReceivedStamp(
            date: date,
            note: note,
            createdAt: created,
            updatedAt: updatedAt ?? later,
            schemaVersion: 1,
            photoFileURL: photoURL,
            thumbnailFileURL: thumbnailURL,
            systemFields: systemFields
        )
    }

    /// 서버에 올라간 적이 있고 보낼 변경이 없는 로컬 우표.
    @discardableResult
    private func uploadedStamp(date: String = "2026-11-18", note: String = "로컬") throws -> Stamp {
        let stamp = try store.create(date: date, note: note, photo: localPhoto, now: created)
        stamp.systemFields = Data([1])
        stamp.needsUpload = false
        stamp.photoNeedsUpload = false
        try container.mainContext.save()
        return stamp
    }

    private func stamp(_ date: String = "2026-11-18") throws -> Stamp? {
        try store.stamp(for: date)
    }

    private func fileData(_ path: String) throws -> Data {
        try Data(contentsOf: fileStore.url(for: path))
    }

    private func fileExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: fileStore.url(for: path).path(percentEncoded: false))
    }

    // MARK: 받은 변경

    @Test func receivedNewStampIsInsertedWithCopiedPhotos() throws {
        let incoming = try received()

        #expect(try applier.applyReceived(incoming) == .inserted)

        let saved = try #require(try stamp())
        #expect(saved.note == "서버")
        #expect(saved.createdAt == created && saved.updatedAt == later)
        #expect(saved.systemFields == Data([42]))
        #expect(!saved.needsUpload && !saved.photoNeedsUpload && !saved.pendingDeletion)
        #expect(try fileData(saved.photoPath) == Data([7, 7, 7]))
        #expect(try fileData(saved.thumbnailPath) == Data([8]))
        // 앱 폴더로 복사되어 임시 파일이 사라져도 남아 있어야 한다.
        #expect(!saved.photoPath.contains("assets-"))
    }

    @Test func receivedUpdateReplacesValuesAndOldFiles() throws {
        let local = try uploadedStamp()
        let oldPaths = [local.photoPath, local.thumbnailPath]

        #expect(try applier.applyReceived(try received(note: "바뀜")) == .updated)

        #expect(local.note == "바뀜")
        #expect(local.updatedAt == later)
        #expect(local.systemFields == Data([42]))
        #expect(try fileData(local.photoPath) == Data([7, 7, 7]))
        #expect(!oldPaths.contains(where: fileExists))
    }

    @Test func receivedChangeDoesNotTouchLocalPendingUpload() throws {
        let local = try uploadedStamp()
        try store.updateNote(date: "2026-11-18", note: "로컬 수정", now: later)

        #expect(try applier.applyReceived(try received(note: "서버")) == .skippedLocalPending)

        #expect(local.note == "로컬 수정")
        #expect(local.needsUpload)
        #expect(local.systemFields == Data([1]))
    }

    @Test func receivedChangeKeepsLocalPendingDeletion() throws {
        try uploadedStamp()
        try store.delete(date: "2026-11-18")

        #expect(try applier.applyReceived(try received()) == .skippedPendingDeletion)

        let local = try #require(try stamp())
        #expect(local.pendingDeletion)
        #expect(try store.visibleStamps().isEmpty)
    }

    @Test func serverDeletionRemovesRowAndFilesEvenWithLocalEdit() throws {
        let local = try uploadedStamp()
        let paths = [local.photoPath, local.thumbnailPath]
        try store.updateNote(date: "2026-11-18", note: "로컬 수정", now: later)

        #expect(try applier.applyServerDeletion(date: "2026-11-18"))

        #expect(try stamp() == nil)
        #expect(!paths.contains(where: fileExists))
    }

    @Test func serverDeletionOfUnknownDateDoesNothing() throws {
        #expect(try !applier.applyServerDeletion(date: "2026-11-18"))
    }

    // MARK: 보낸 결과

    @Test func markSavedClearsUploadFlags() throws {
        let local = try store.create(date: "2026-11-18", note: "새로", photo: localPhoto, now: created)

        try applier.markSaved(date: "2026-11-18", systemFields: Data([9]), sentUpdatedAt: created, sentBaseSystemFields: nil)

        #expect(local.systemFields == Data([9]))
        #expect(!local.needsUpload)
        #expect(!local.photoNeedsUpload)
    }

    @Test func markSavedToleratesMillisecondPrecision() throws {
        let local = try store.create(date: "2026-11-18", note: "새로", photo: localPhoto, now: created.addingTimeInterval(0.0004))
        try applier.markSaved(date: "2026-11-18", systemFields: Data([9]), sentUpdatedAt: created, sentBaseSystemFields: nil)
        #expect(!local.needsUpload)
    }

    @Test func markSavedKeepsFlagsWhenEditedAfterSending() throws {
        let local = try store.create(date: "2026-11-18", note: "보낸 값", photo: localPhoto, now: created)
        // 올리는 도중에 또 고침
        try store.updateNote(date: "2026-11-18", note: "그 뒤 수정", now: later)

        try applier.markSaved(date: "2026-11-18", systemFields: Data([9]), sentUpdatedAt: created, sentBaseSystemFields: nil)

        #expect(local.systemFields == Data([9]))
        #expect(local.needsUpload)
        #expect(local.note == "그 뒤 수정")
    }

    @Test func markSavedKeepsPendingDeletion() throws {
        try uploadedStamp()
        try store.delete(date: "2026-11-18")

        try applier.markSaved(date: "2026-11-18", systemFields: Data([9]), sentUpdatedAt: created, sentBaseSystemFields: Data([1]))

        let local = try #require(try stamp())
        #expect(local.pendingDeletion && local.needsUpload)
    }

    @Test func markSavedIgnoresLateResultOfOlderSend() throws {
        // 보낸 A(기준 nil)가 늦게 도착하기 전에 다른 저장 B가 먼저 반영되어 systemFields가 바뀐 상황
        let local = try store.create(date: "2026-11-18", note: "B", photo: localPhoto, now: later)
        local.systemFields = Data([20])  // B의 결과
        local.needsUpload = false
        local.photoNeedsUpload = false

        let applied = try applier.markSaved(
            date: "2026-11-18", systemFields: Data([10]), sentUpdatedAt: created, sentBaseSystemFields: nil
        )

        #expect(!applied)
        #expect(local.systemFields == Data([20]))
        #expect(!local.needsUpload)
    }

    @Test func markSavedAppliesWhenBaseMatchesUploadedRecord() throws {
        let local = try uploadedStamp()
        try store.updateNote(date: "2026-11-18", note: "수정", now: later)

        let applied = try applier.markSaved(
            date: "2026-11-18", systemFields: Data([9]), sentUpdatedAt: later, sentBaseSystemFields: Data([1])
        )

        #expect(applied)
        #expect(local.systemFields == Data([9]))
        #expect(!local.needsUpload)
    }

    @Test func markDeletedRemovesPendingRowAndFiles() throws {
        let local = try uploadedStamp()
        let paths = [local.photoPath, local.thumbnailPath]
        try store.delete(date: "2026-11-18")
        #expect(paths.allSatisfy(fileExists))  // 삭제 대기 중에는 파일 유지

        try applier.markDeleted(date: "2026-11-18")

        #expect(try stamp() == nil)
        #expect(!paths.contains(where: fileExists))
    }

    @Test func markDeletedAfterRecreateUploadsAsNew() throws {
        try uploadedStamp()
        try store.delete(date: "2026-11-18")
        let recreated = try store.create(date: "2026-11-18", note: "다시", photo: localPhoto, now: later)
        recreated.needsUpload = false

        try applier.markDeleted(date: "2026-11-18")

        #expect(recreated.systemFields == nil)
        #expect(recreated.needsUpload && recreated.photoNeedsUpload)
        #expect(recreated.note == "다시")
    }

    // MARK: 보낼 변경

    @Test func pendingChangesCoverSavesAndDeletes() throws {
        try uploadedStamp(date: "2026-11-01")                                   // 보낼 것 없음
        try store.create(date: "2026-11-02", note: "", photo: localPhoto)      // 저장
        try uploadedStamp(date: "2026-11-03")
        try store.delete(date: "2026-11-03")                                   // 삭제

        #expect(try applier.pendingChanges() == [.save(date: "2026-11-02"), .delete(date: "2026-11-03")])
    }

    @Test func pendingChangeForDate() throws {
        try uploadedStamp(date: "2026-11-01")
        try uploadedStamp(date: "2026-11-02")
        try store.delete(date: "2026-11-02")

        #expect(try applier.pendingChange(for: "2026-11-01") == .save(date: "2026-11-01"))
        #expect(try applier.pendingChange(for: "2026-11-02") == .delete(date: "2026-11-02"))
        // 서버에 올라간 적 없어 바로 지워진 행
        #expect(try applier.pendingChange(for: "2026-11-03") == .delete(date: "2026-11-03"))
    }

    @Test func uploadValuesReflectLocalStamp() throws {
        let local = try uploadedStamp()
        try store.updateNote(date: "2026-11-18", note: "수정", now: later)

        let values = try #require(try applier.uploadValues(for: "2026-11-18"))

        #expect(values.date == "2026-11-18")
        #expect(values.note == "수정")
        #expect(values.updatedAt == later)
        #expect(values.systemFields == Data([1]))
        #expect(!values.photoNeedsUpload)
        #expect(values.photoURL == fileStore.url(for: local.photoPath))
        #expect(values.thumbnailURL == fileStore.url(for: local.thumbnailPath))
    }

    @Test func uploadValuesAreNilForMissingOrDeleted() throws {
        try uploadedStamp()
        try store.delete(date: "2026-11-18")
        #expect(try applier.uploadValues(for: "2026-11-18") == nil)
        #expect(try applier.uploadValues(for: "2026-11-19") == nil)
    }
}
