import Testing
@testable import PiecePost

@MainActor
struct SendProgressTests {
    @Test func manualSendStartsWhenIdle() {
        var progress = SendProgress()
        #expect(!progress.isSending)
        let began1 = progress.beginManualSend()
        #expect(began1)
        #expect(progress.isSending)
    }

    /// 자동 보내기 중(WillSendChanges 뒤 DidSendChanges 전)에는 건너뛴다.
    @Test func manualSendSkippedWhileEngineSending() {
        var progress = SendProgress()
        progress.engineWillSend()
        let began2 = progress.beginManualSend()
        #expect(!began2)
        #expect(!progress.isManualSending)
    }

    @Test func manualSendStartsAfterEngineFinished() {
        var progress = SendProgress()
        progress.engineWillSend()
        progress.engineDidSend()
        let began3 = progress.beginManualSend()
        #expect(began3)
    }

    /// "지금 보내기"를 기다리는 동안 다시 누르면 건너뛴다.
    @Test func secondManualSendSkippedUntilFirstEnds() {
        var progress = SendProgress()
        let began4 = progress.beginManualSend()
        #expect(began4)
        let began5 = progress.beginManualSend()
        #expect(!began5)
        progress.endManualSend()
        let began6 = progress.beginManualSend()
        #expect(began6)
    }

    /// 지금 보내기가 일으킨 엔진 보내기가 끝나도, sendChanges()가 돌아오기 전이면 여전히 진행 중이다.
    @Test func manualSendStillInProgressUntilEnded() {
        var progress = SendProgress()
        let began7 = progress.beginManualSend()
        #expect(began7)
        progress.engineWillSend()
        progress.engineDidSend()
        #expect(progress.isSending)
        let began8 = progress.beginManualSend()
        #expect(!began8)
        progress.endManualSend()
        #expect(!progress.isSending)
    }

    /// 끝 이벤트가 오지 않으면 계속 건너뛴다(의도된 동작).
    @Test func staysSendingWithoutDidSend() {
        var progress = SendProgress()
        progress.engineWillSend()
        let began9 = progress.beginManualSend()
        #expect(!began9)
        let began10 = progress.beginManualSend()
        #expect(!began10)
    }
}
