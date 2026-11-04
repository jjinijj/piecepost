import Foundation

/// '존 없음' 표시(기획서 settings-erase-records 결정 5, 첫 시도 settings-erase-all 결정 7).
///
/// 서버의 존 삭제(`deleted`·`purged`)를 반영해 로컬을 지우거나, 전부 지우기에서 서버에 존이 없음을 알게 되면 세운다. 표시가 있는 동안 저장을 예약할 때
/// 존 만들기(`.saveZone`)도 함께 예약해, 첫 보내기가 `zoneNotFound` 를 거치지 않게 한다.
/// 실측에서 `zoneNotFound` 뒤 다시 넣은 예약을 CKSyncEngine 이 자동으로 보내지 않았다.
/// 존 저장이 성공하면 지운다. 기존 `zoneNotFound` 처리는 그대로 둔다.
struct ZoneMissingMarker: Equatable {
    private(set) var isSet: Bool

    /// - Parameter isSet: 기기에 저장된 값
    init(isSet: Bool = false) {
        self.isSet = isSet
    }

    mutating func set() {
        isSet = true
    }

    /// 이 변경을 예약할 때 존 만들기도 함께 예약해야 하는지. 새 우표·수정(저장)일 때만.
    /// 삭제는 서버에 없으면 `unknownItem`·`zoneNotFound` 처리로 끝나므로 존을 만들지 않는다.
    func needsZoneSave(for change: PendingStampChange) -> Bool {
        guard isSet else { return false }
        if case .save = change { return true }
        return false
    }

    /// 존 저장 결과를 받았다. 우표 존이 저장됐으면 표시를 지운다.
    /// - Returns: 지웠으면 true
    mutating func zonesSaved(containsStampsZone: Bool) -> Bool {
        guard isSet, containsStampsZone else { return false }
        isSet = false
        return true
    }
}

/// '존 없음' 표시를 기기에 저장한다. 앱을 껐다 켜도 첫 보내기에 존을 함께 만들 수 있게.
nonisolated final class ZoneMissingMarkerStore: Sendable {
    static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Sync", directoryHint: .isDirectory)
            .appending(path: "zone-missing.json", directoryHint: .notDirectory)
    }

    private let store: SyncStateStore

    init(fileURL: URL = ZoneMissingMarkerStore.defaultFileURL) {
        store = SyncStateStore(fileURL: fileURL)
    }

    /// 없거나 깨졌으면 false. 깨진 파일은 지운다.
    func load() -> Bool {
        do {
            return try store.load(Bool.self) ?? false
        } catch {
            store.clear()
            return false
        }
    }

    func save(_ isSet: Bool) throws {
        if isSet {
            try store.save(true)
        } else {
            store.clear()
        }
    }
}
