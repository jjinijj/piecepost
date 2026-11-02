import Foundation

/// 포그라운드 진입 한 번에 진입 처리(계정 확인, 용량 부족 다시 보내기)를 한 번만 하게 한다.
///
/// 화면이 활성으로 바뀌는 일은 제어 센터를 내렸다 올릴 때처럼 백그라운드를 거치지 않고도 생긴다.
/// 백그라운드에 들어갔다가 처음 활성이 될 때만 진입으로 본다. 앱 시작은 시작 때 처리를 따로 하므로 처리한 것으로 둔다.
struct ForegroundEntryGate {
    private var handledCurrentEntry = true

    mutating func didEnterBackground() {
        handledCurrentEntry = false
    }

    /// 이번 진입에서 처음 활성이 됐으면 true, 이미 처리했으면 false.
    mutating func shouldHandleActivation() -> Bool {
        guard !handledCurrentEntry else { return false }
        handledCurrentEntry = true
        return true
    }
}
