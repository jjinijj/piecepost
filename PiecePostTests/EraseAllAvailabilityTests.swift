import Testing
@testable import PiecePost

/// 기획서 settings-erase-records 결정 6(첫 시도 settings-erase-all 비활성 조건 표와 같음). 모든 `SyncStatus`와 0장·1장 이상 조합.
@MainActor
struct EraseAllAvailabilityTests {
    private static let iCloudBlocked: [SyncStatus] = [
        .notStarted, .iCloudUnavailable, .iCloudTemporarilyUnavailable, .accountChanged,
    ]
    private static let iCloudUsable: [SyncStatus] = [.idle, .syncing, .quotaExceeded, .error(code: 2)]

    @Test(arguments: iCloudBlocked, [0, 1, 5])
    func iCloudUnavailableDisablesWithICloudReason(status: SyncStatus, count: Int) {
        let availability = EraseAllAvailability(status: status, visibleStampCount: count)

        #expect(!availability.isEnabled)
        #expect(availability.reason == "지금은 iCloud를 쓸 수 없어 지울 수 없어요.")
    }

    @Test(arguments: iCloudUsable)
    func noStampsDisablesWithEmptyReason(status: SyncStatus) {
        let availability = EraseAllAvailability(status: status, visibleStampCount: 0)

        #expect(!availability.isEnabled)
        #expect(availability.reason == "지울 기록이 없어요.")
    }

    @Test(arguments: iCloudUsable, [1, 5])
    func usableICloudWithStampsEnables(status: SyncStatus, count: Int) {
        let availability = EraseAllAvailability(status: status, visibleStampCount: count)

        #expect(availability.isEnabled)
        #expect(availability.reason == nil)
    }

    /// 두 목록이 `SyncStatus` 8가지를 겹치지 않게 모두 담는지.
    @Test func tablesCoverEveryStatus() {
        let labels = Set((Self.iCloudBlocked + Self.iCloudUsable).map(\.label))
        #expect(labels.count == 8)
    }
}
