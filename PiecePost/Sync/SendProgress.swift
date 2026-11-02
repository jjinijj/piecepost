import Foundation

/// 보내기가 진행 중인지 기억한다. "지금 보내기"가 진행 중인 보내기와 겹치지 않게 한다.
///
/// 겹치면 두 보내기가 같은 레코드의 "보낼 때 값"을 덮어써, 먼저 온 결과가 다른 보내기의 값과 짝지어질 수 있다.
/// 진행 중 여부는 엔진 이벤트(WillSendChanges → DidSendChanges)와 "지금 보내기" 자체의 실행으로 판단한다.
/// 끝 이벤트가 오지 않으면 계속 진행 중으로 본다(의도된 동작. 그때 남는 건너뜀 로그가 진단이 되고, 앱을 다시 열면 풀린다).
struct SendProgress {
    /// 엔진이 보내기 시작을 알렸고 아직 끝을 알리지 않았다.
    private(set) var isEngineSending = false
    /// "지금 보내기"가 `sendChanges()`를 기다리는 중이다.
    private(set) var isManualSending = false

    var isSending: Bool { isEngineSending || isManualSending }

    mutating func engineWillSend() { isEngineSending = true }
    mutating func engineDidSend() { isEngineSending = false }

    /// "지금 보내기"를 시작해도 되면 진행 중으로 표시하고 true. 진행 중이면 아무것도 바꾸지 않고 false.
    mutating func beginManualSend() -> Bool {
        guard !isSending else { return false }
        isManualSending = true
        return true
    }

    mutating func endManualSend() { isManualSending = false }
}
