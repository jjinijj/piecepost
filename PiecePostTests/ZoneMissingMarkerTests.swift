import Foundation
import Testing
@testable import PiecePost

/// 기획서 settings-erase-records 결정 5(첫 시도 결정 7): 존을 지운 뒤 첫 저장 예약에 존 만들기를 함께 예약하고, 존 저장이 성공하면 표시를 지운다.
@MainActor
struct ZoneMissingMarkerTests {
    // MARK: 존 만들기 함께 예약

    @Test func withoutMarkNoZoneSave() {
        let marker = ZoneMissingMarker()
        #expect(!marker.needsZoneSave(for: .save(date: "2026-11-04")))
        #expect(!marker.needsZoneSave(for: .delete(date: "2026-11-04")))
    }

    @Test func markedSaveAddsZoneSave() {
        var marker = ZoneMissingMarker()
        marker.set()
        #expect(marker.needsZoneSave(for: .save(date: "2026-11-04")))
    }

    @Test func markedDeleteDoesNotAddZoneSave() {
        var marker = ZoneMissingMarker()
        marker.set()
        #expect(!marker.needsZoneSave(for: .delete(date: "2026-11-04")))
    }

    @Test func markStaysUntilZoneSaved() {
        // 저장 예약을 여러 번 해도(수정, 재시작 뒤 다시 넣기) 존이 저장되기 전까지는 계속 함께 예약한다.
        var marker = ZoneMissingMarker()
        marker.set()
        _ = marker.needsZoneSave(for: .save(date: "2026-11-04"))
        #expect(marker.needsZoneSave(for: .save(date: "2026-11-05")))
    }

    // MARK: 표시 지우기

    @Test func stampsZoneSavedClearsMark() {
        var marker = ZoneMissingMarker()
        marker.set()
        let cleared = marker.zonesSaved(containsStampsZone: true)
        #expect(cleared)
        #expect(!marker.isSet)
        #expect(!marker.needsZoneSave(for: .save(date: "2026-11-04")))
    }

    @Test func otherZoneSavedKeepsMark() {
        var marker = ZoneMissingMarker()
        marker.set()
        let cleared = marker.zonesSaved(containsStampsZone: false)
        #expect(!cleared)
        #expect(marker.isSet)
    }

    @Test func zoneSavedWithoutMarkReportsNothing() {
        var marker = ZoneMissingMarker()
        let cleared = marker.zonesSaved(containsStampsZone: true)
        #expect(!cleared)
        #expect(!marker.isSet)
    }

    @Test func restoredMarkStillAddsZoneSave() {
        // 앱을 다시 켜도 저장된 표시로 첫 보내기에 존을 함께 만든다.
        let marker = ZoneMissingMarker(isSet: true)
        #expect(marker.needsZoneSave(for: .save(date: "2026-11-04")))
    }

    // MARK: 저장

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "zone-missing-\(UUID().uuidString).json", directoryHint: .notDirectory)
    }

    @Test func storeRoundTrip() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ZoneMissingMarkerStore(fileURL: url)
        #expect(!store.load())

        try store.save(true)
        #expect(ZoneMissingMarkerStore(fileURL: url).load())

        try store.save(false)
        #expect(!ZoneMissingMarkerStore(fileURL: url).load())
    }

    @Test func corruptFileLoadsFalseAndIsRemoved() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)

        #expect(!ZoneMissingMarkerStore(fileURL: url).load())
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
