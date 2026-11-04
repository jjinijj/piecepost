/// 설정 화면 "기록 전부 지우기" 버튼을 누를 수 있는지와 누를 수 없는 이유.
/// 화면 밖에서 동기화 상태와 보이는 우표 수만 보고 정해 단위 테스트로 확인한다(기획서 settings-erase-records 결정 6·완료 기준 1, 첫 시도와 같음).
struct EraseAllAvailability: Equatable {
    static let iCloudUnavailableReason = "지금은 iCloud를 쓸 수 없어 지울 수 없어요."
    static let nothingToEraseReason = "지울 기록이 없어요."

    let isEnabled: Bool
    /// 비활성일 때만 보이는 이유 한 줄. 활성이면 nil
    let reason: String?

    /// 둘 다 해당하면 iCloud 이유를 보인다.
    /// - Parameter visibleStampCount: 삭제 대기(`pendingDeletion`)를 뺀 우표 수
    init(status: SyncStatus, visibleStampCount: Int) {
        if !Self.canUseICloud(status) {
            isEnabled = false
            reason = Self.iCloudUnavailableReason
        } else if visibleStampCount == 0 {
            isEnabled = false
            reason = Self.nothingToEraseReason
        } else {
            isEnabled = true
            reason = nil
        }
    }

    /// 용량 부족·오류일 때도 지울 수 있다(공간을 비울 수 있게).
    private static func canUseICloud(_ status: SyncStatus) -> Bool {
        switch status {
        case .notStarted, .iCloudUnavailable, .iCloudTemporarilyUnavailable, .accountChanged: false
        case .idle, .syncing, .quotaExceeded, .error: true
        }
    }
}
