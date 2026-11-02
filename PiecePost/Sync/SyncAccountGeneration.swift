import Foundation

/// 계정 상태가 바뀔 때마다 올라가는 세대 번호. `await` 로 기다리는 사이 계정이 바뀌었는지 가린다.
///
/// 멈춤 여부 하나만 보면 "기다리는 사이 멈췄다가 다시 재개된" 경우를 놓친다. 그래서 요청 때 세대를 들고 있다가
/// 돌아온 뒤 지금 세대와 비교한다. 멈춤·재개, 엔진의 로그인·로그아웃·계정 전환 알림 때 올린다.
struct SyncAccountGeneration {
    private(set) var value = 0

    mutating func advance() {
        value += 1
    }

    /// 요청 때 세대와 지금 세대가 같고 멈춰 있지 않을 때만 기다려 받은 결과를 반영한다.
    func allowsApplying(requestedAt generation: Int, isPaused: Bool) -> Bool {
        !isPaused && generation == value
    }
}
