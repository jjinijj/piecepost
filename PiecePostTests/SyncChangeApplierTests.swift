import CloudKit
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
    private let evenLater = Date(timeIntervalSince1970: 1_800_001_200)
    private let localPhoto = ProcessedPhoto(photo: Data([1, 1]), thumbnail: Data([2]))
    /// `received()`의 기본 사진과 같은 내용
    private let serverPhoto = ProcessedPhoto(photo: Data([7, 7, 7]), thumbnail: Data([8]))

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
    private func uploadedStamp(
        date: String = "2026-11-18",
        note: String = "로컬",
        photo: ProcessedPhoto? = nil
    ) throws -> Stamp {
        let stamp = try store.create(date: date, note: note, photo: photo ?? localPhoto, now: created)
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

    /// 앱 폴더에 남은 사진 파일 수. 밀린 쪽 파일이 남지 않았는지 볼 때 쓴다.
    private func photoFileCount() throws -> Int {
        let folder = fileStore.baseURL.appending(path: StampFileStore.photosFolder)
        return try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).count
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

    // MARK: 받기 충돌 (로컬에 보낼 변경이 있을 때)

    @Test func receivedLaterThanLocalPendingWinsAndDropsLocalChange() throws {
        let local = try uploadedStamp()
        let oldPaths = [local.photoPath, local.thumbnailPath]
        try store.updateNote(date: "2026-11-18", note: "로컬 수정", now: later)

        let outcome = try applier.applyReceived(try received(note: "서버", updatedAt: evenLater))

        #expect(outcome == .conflictServerWon)
        #expect(local.note == "서버")
        #expect(local.updatedAt == evenLater)
        #expect(local.systemFields == Data([42]))
        #expect(!local.needsUpload && !local.photoNeedsUpload)
        #expect(try fileData(local.photoPath) == Data([7, 7, 7]))
        // 밀린 로컬 사진 파일은 지운다
        #expect(!oldPaths.contains(where: fileExists))
        #expect(try photoFileCount() == 1)
        // 보낼 변경이 없어졌으므로 엔진에 예약이 남아 있어도 보내지 않는다
        #expect(try applier.pendingChanges().isEmpty)
        #expect(try applier.uploadValues(for: "2026-11-18") == nil)
    }

    @Test func localPendingLaterThanReceivedIsKeptWithNewSystemFields() throws {
        let local = try uploadedStamp(photo: serverPhoto)
        let paths = [local.photoPath, local.thumbnailPath]
        try store.updateNote(date: "2026-11-18", note: "로컬 수정", now: evenLater)

        let outcome = try applier.applyReceived(try received(note: "서버", updatedAt: later, photo: serverPhoto.photo))

        #expect(outcome == .conflictLocalWon(resendsPhoto: false))
        #expect(local.note == "로컬 수정")
        #expect(local.updatedAt == evenLater)
        #expect(local.needsUpload)
        // 같은 사진이면 기록만 보낸다(불변 규칙 5)
        #expect(!local.photoNeedsUpload)
        // 다음 보내기는 받은 서버 레코드를 기준으로 한다
        #expect(local.systemFields == Data([42]))
        #expect(try applier.uploadValues(for: "2026-11-18")?.systemFields == Data([42]))
        // 받은 사진은 복사하지 않는다
        #expect([local.photoPath, local.thumbnailPath] == paths)
        #expect(try photoFileCount() == 1)
    }

    @Test func localPendingWithSameTimestampIsKept() throws {
        let local = try uploadedStamp(photo: serverPhoto)
        try store.updateNote(date: "2026-11-18", note: "로컬 수정", now: later.addingTimeInterval(0.0004))

        // CloudKit은 밀리초까지만 저장하므로 1ms 안의 차이는 같은 시각으로 본다
        let outcome = try applier.applyReceived(try received(updatedAt: later, photo: serverPhoto.photo))

        #expect(outcome == .conflictLocalWon(resendsPhoto: false))
        #expect(local.note == "로컬 수정" && local.needsUpload)
    }

    @Test func localWinnerResendsPhotoWhenServerPhotoDiffers() throws {
        // 다른 기기가 같은 날짜를 지우고 새 사진으로 다시 만든 사이, 이 기기는 기록만 고친 상황
        let local = try uploadedStamp()
        try store.updateNote(date: "2026-11-18", note: "로컬 수정", now: evenLater)

        let outcome = try applier.applyReceived(try received(updatedAt: later, photo: Data([9, 9])))

        #expect(outcome == .conflictLocalWon(resendsPhoto: true))
        #expect(local.needsUpload && local.photoNeedsUpload)
        #expect(try fileData(local.photoPath) == localPhoto.photo)
        #expect(try applier.uploadValues(for: "2026-11-18")?.photoNeedsUpload == true)
    }

    @Test func uploadValuesAreNilWithoutPendingChange() throws {
        try uploadedStamp()
        #expect(try applier.uploadValues(for: "2026-11-18") == nil)
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

    // MARK: 보낼 때 충돌 (serverRecordChanged)

    /// 실제 CKRecord에서 뽑은 시스템 필드. 보낼 레코드를 이 값으로 복원할 수 있다.
    private func realSystemFields(date: String = "2026-11-18") -> Data {
        let record = CKRecord(recordType: StampRecordMapper.recordType, recordID: StampRecordMapper.recordID(for: date))
        return StampRecordMapper.encodeSystemFields(of: record)
    }

    @Test func saveConflictLocalLaterKeepsLocalAndResendsOnServerBase() throws {
        let local = try uploadedStamp(photo: serverPhoto)
        try store.updateNote(date: "2026-11-18", note: "로컬 수정", now: evenLater)
        let serverFields = realSystemFields()

        let outcome = try applier.resolveSaveConflict(
            server: try received(note: "서버", updatedAt: later, photo: serverPhoto.photo, systemFields: serverFields)
        )

        #expect(outcome == .conflictLocalWon(resendsPhoto: false))
        #expect(local.note == "로컬 수정" && local.updatedAt == evenLater)
        #expect(local.needsUpload && !local.photoNeedsUpload)
        #expect(local.systemFields == serverFields)
        #expect(try photoFileCount() == 1)

        // 다시 보낼 레코드는 서버 시스템 필드를 기준으로 하고, 같은 사진이면 기록만 담는다(불변 규칙 5)
        let values = try #require(try applier.uploadValues(for: "2026-11-18"))
        #expect(values.systemFields == serverFields)
        let record = StampRecordMapper.record(from: values)
        #expect(record[StampRecordMapper.Field.note] as? String == "로컬 수정")
        #expect(record[StampRecordMapper.Field.photo] == nil)

        // 다시 보내기 성공 → 보낼 변경이 없어진다(반복 없음)
        #expect(try applier.markSaved(
            date: "2026-11-18", systemFields: Data([77]), sentUpdatedAt: values.updatedAt, sentBaseSystemFields: serverFields
        ))
        #expect(!local.needsUpload && local.systemFields == Data([77]))
        #expect(try applier.uploadValues(for: "2026-11-18") == nil)
    }

    @Test func saveConflictLocalWinnerSendsPhotoWhenServerPhotoDiffers() throws {
        // 서버에는 다른 사진이 있고 로컬은 기록만 고친 상태에서 로컬이 이김
        let local = try uploadedStamp()
        try store.updateNote(date: "2026-11-18", note: "로컬 수정", now: evenLater)

        let outcome = try applier.resolveSaveConflict(
            server: try received(updatedAt: later, photo: Data([9, 9]), systemFields: realSystemFields())
        )

        #expect(outcome == .conflictLocalWon(resendsPhoto: true))
        #expect(local.photoNeedsUpload)
        let record = StampRecordMapper.record(from: try #require(try applier.uploadValues(for: "2026-11-18")))
        let photo = try #require(record[StampRecordMapper.Field.photo] as? CKAsset)
        #expect(photo.fileURL == fileStore.url(for: local.photoPath))
        #expect(record[StampRecordMapper.Field.thumbnail] is CKAsset)
    }

    @Test func saveConflictNewLocalPhotoIsSentWhenLocalWins() throws {
        // 두 기기가 같은 날짜를 따로 만든 경우(S5): 로컬은 처음부터 사진을 보낼 예정
        let local = try store.create(date: "2026-11-18", note: "A", photo: localPhoto, now: evenLater)

        let outcome = try applier.resolveSaveConflict(
            server: try received(note: "B", updatedAt: later, systemFields: realSystemFields())
        )

        #expect(outcome == .conflictLocalWon(resendsPhoto: false))
        #expect(local.photoNeedsUpload && local.needsUpload)
        #expect(local.note == "A")
        #expect(try photoFileCount() == 1)
    }

    @Test func saveConflictServerLaterReplacesLocal() throws {
        let local = try store.create(date: "2026-11-18", note: "A", photo: localPhoto, now: later)
        let oldPaths = [local.photoPath, local.thumbnailPath]

        let outcome = try applier.resolveSaveConflict(server: try received(note: "B", updatedAt: evenLater))

        #expect(outcome == .conflictServerWon)
        #expect(local.note == "B" && local.updatedAt == evenLater)
        #expect(local.systemFields == Data([42]))
        #expect(!local.needsUpload && !local.photoNeedsUpload)
        #expect(try fileData(local.photoPath) == Data([7, 7, 7]))
        #expect(try fileData(local.thumbnailPath) == Data([8]))
        // 밀린 로컬 사진 파일은 지우고 이긴 쪽 파일만 남는다
        #expect(!oldPaths.contains(where: fileExists))
        #expect(try photoFileCount() == 1)
        #expect(try applier.pendingChanges().isEmpty)
        #expect(try applier.uploadValues(for: "2026-11-18") == nil)
    }

    @Test func saveConflictWithSameTimestampTakesServer() throws {
        let local = try store.create(date: "2026-11-18", note: "A", photo: localPhoto, now: later.addingTimeInterval(0.0004))

        let outcome = try applier.resolveSaveConflict(server: try received(note: "B", updatedAt: later))

        #expect(outcome == .conflictServerWon)
        #expect(local.note == "B" && !local.needsUpload)
    }

    @Test func saveConflictKeepsPendingDeletion() throws {
        try uploadedStamp()
        try store.delete(date: "2026-11-18")

        #expect(try applier.resolveSaveConflict(server: try received(updatedAt: evenLater)) == .skippedPendingDeletion)

        let local = try #require(try stamp())
        #expect(local.pendingDeletion && local.needsUpload)
        #expect(local.systemFields == Data([1]))
    }

    @Test func saveConflictForMissingRowDoesNothing() throws {
        #expect(try applier.resolveSaveConflict(server: try received()) == .skippedPendingDeletion)
        #expect(try stamp() == nil)
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
