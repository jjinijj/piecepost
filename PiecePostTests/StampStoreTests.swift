import Foundation
import SwiftData
import Testing
@testable import PiecePost

@MainActor
struct StampStoreTests {
    private let container: ModelContainer
    private let store: StampStore
    private var changes: [String] { recorder.dates }
    private let recorder = ChangeRecorder()

    init() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: Stamp.self, configurations: configuration)
        let recorder = recorder
        store = StampStore(context: container.mainContext) { recorder.dates.append($0) }
    }

    private let created = Date(timeIntervalSince1970: 1_800_000_000)
    private let later = Date(timeIntervalSince1970: 1_800_000_600)

    @discardableResult
    private func makeStamp(date: String = "2026-11-18", note: String = "맑음") throws -> Stamp {
        try store.create(date: date, note: note, photoPath: "p.heic", thumbnailPath: "t.heic", now: created)
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

    @Test func createRejectsDuplicateDateWithoutOverwriting() throws {
        try makeStamp(note: "처음")
        #expect(throws: StampStoreError.alreadyExists) {
            try store.create(date: "2026-11-18", note: "덮어쓰기", photoPath: "x", thumbnailPath: "y")
        }
        #expect(try store.stamp(for: "2026-11-18")?.note == "처음")
        #expect(try store.visibleStamps().count == 1)
    }

    @Test func createRequiresValidDateAndPhoto() {
        #expect(throws: StampStoreError.invalidDate) {
            try store.create(date: "2026-02-30", note: "", photoPath: "p", thumbnailPath: "t")
        }
        #expect(throws: StampStoreError.missingPhoto) {
            try store.create(date: "2026-11-18", note: "", photoPath: "", thumbnailPath: "t")
        }
        #expect(changes.isEmpty)
    }

    // MARK: 기록 수정

    @Test func updateNoteKeepsPhotoUploadFlag() throws {
        let stamp = try makeStamp()
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

    @Test func deleteNeverUploadedRemovesRow() throws {
        try makeStamp()
        try store.delete(date: "2026-11-18")
        #expect(try store.stamp(for: "2026-11-18") == nil)
        #expect(changes == ["2026-11-18", "2026-11-18"])
    }

    @Test func deleteUploadedMarksPendingDeletion() throws {
        let stamp = try makeStamp()
        stamp.systemFields = Data([1])
        stamp.needsUpload = false

        try store.delete(date: "2026-11-18")

        #expect(stamp.pendingDeletion)
        #expect(stamp.needsUpload)
        #expect(try store.visibleStamps().isEmpty)
        #expect(throws: StampStoreError.notFound) { try store.delete(date: "2026-11-18") }
        #expect(throws: StampStoreError.notFound) { try store.updateNote(date: "2026-11-18", note: "x") }
    }

    @Test func recreateOnPendingDeletionReusesSystemFields() throws {
        let stamp = try makeStamp(note: "이전")
        stamp.systemFields = Data([1])
        try store.delete(date: "2026-11-18")

        let recreated = try store.create(
            date: "2026-11-18", note: "새로", photoPath: "p2.heic", thumbnailPath: "t2.heic", now: later
        )

        #expect(recreated.systemFields == Data([1]))
        #expect(!recreated.pendingDeletion)
        #expect(recreated.note == "새로")
        #expect(recreated.photoPath == "p2.heic")
        #expect(recreated.createdAt == later)
        #expect(recreated.photoNeedsUpload)
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
