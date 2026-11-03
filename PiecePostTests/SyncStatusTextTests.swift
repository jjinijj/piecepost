import Testing
@testable import PiecePost

/// 기획서 settings-skeleton 상태 문구 표의 8가지 경우.
struct SyncStatusTextTests {
    @Test func idle() {
        let text = SyncStatusText(.idle)
        #expect(text.title == "iCloud에 백업됨")
        #expect(text.detail == nil)
    }

    @Test func syncing() {
        let text = SyncStatusText(.syncing)
        #expect(text.title == "백업하는 중")
        #expect(text.detail == nil)
    }

    @Test func notStarted() {
        let text = SyncStatusText(.notStarted)
        #expect(text.title == "확인하는 중")
        #expect(text.detail == nil)
    }

    @Test func iCloudUnavailable() {
        let text = SyncStatusText(.iCloudUnavailable)
        #expect(text.title == "iCloud 꺼짐")
        #expect(text.detail == "기기에만 저장돼요. iCloud에 로그인하면 백업돼요.")
    }

    @Test func iCloudTemporarilyUnavailable() {
        let text = SyncStatusText(.iCloudTemporarilyUnavailable)
        #expect(text.title == "iCloud 일시 사용 불가")
        #expect(text.detail == "기기에 저장해 두고 잠시 뒤 다시 백업해요.")
    }

    @Test func accountChanged() {
        let text = SyncStatusText(.accountChanged)
        #expect(text.title == "계정 변경됨")
        #expect(text.detail == "처음 백업한 iCloud 계정이 아니라 백업을 멈췄어요. 원래 계정으로 돌아오면 이어서 해요.")
    }

    @Test func quotaExceeded() {
        let text = SyncStatusText(.quotaExceeded)
        #expect(text.title == "iCloud 용량 부족")
        #expect(text.detail == "기기에는 저장돼 있어요. iCloud 공간을 확보하면 다시 백업해요.")
    }

    @Test(arguments: [2, 36, 110])
    func error(code: Int) {
        let text = SyncStatusText(.error(code: code))
        #expect(text.title == "백업 오류")
        #expect(text.detail == "오류 코드 \(code)")
    }

    /// 기존 시험 화면 문구는 바꾸지 않는다(범위 밖).
    @Test func spikeLabelUnchanged() {
        #expect(SyncStatus.notStarted.label == "연결 전")
        #expect(SyncStatus.idle.label == "정상")
    }
}
