import Testing
@testable import PiecePost

/// Codex 지적 1(왕복 2): 지우기와 겹친 보내기·받기 결과를 반영하지 않는다.
@MainActor
struct EraseFenceTests {
    @Test func appliesWhenNoErase() {
        let fence = EraseFence()
        #expect(fence.gate(startedAt: fence.token) == .apply)
    }

    @Test func holdsWhileErasing() {
        var fence = EraseFence()
        let before = fence.token
        fence.begin()

        #expect(fence.gate(startedAt: before) == .hold)
        #expect(fence.gate(startedAt: fence.token) == .hold)
    }

    /// 지우기 전에 시작한 작업의 결과가 성공한 지우기 뒤에 오면 버린다.
    @Test func dropsWorkStartedBeforeSuccessfulErase() {
        var fence = EraseFence()
        let before = fence.token
        fence.begin()
        let during = fence.token
        fence.end(erased: true)

        #expect(fence.gate(startedAt: before) == .drop)
        #expect(fence.gate(startedAt: during) == .drop)
    }

    @Test func appliesWorkStartedAfterSuccessfulErase() {
        var fence = EraseFence()
        fence.begin()
        fence.end(erased: true)

        #expect(fence.gate(startedAt: fence.token) == .apply)
    }

    /// 지우기가 실패하면 데이터가 그대로이므로 겹친 작업도 평소대로 반영한다.
    @Test func appliesWorkOverlappingFailedErase() {
        var fence = EraseFence()
        let before = fence.token
        fence.begin()
        let during = fence.token
        fence.end(erased: false)

        #expect(fence.gate(startedAt: before) == .apply)
        #expect(fence.gate(startedAt: during) == .apply)
    }

    /// 성공 뒤 실패한 지우기가 있어도, 성공보다 먼저 시작한 작업은 계속 버린다.
    @Test func failedEraseDoesNotReopenEarlierSuccess() {
        var fence = EraseFence()
        let before = fence.token
        fence.begin()
        fence.end(erased: true)
        let afterSuccess = fence.token
        fence.begin()
        fence.end(erased: false)

        #expect(fence.gate(startedAt: before) == .drop)
        #expect(fence.gate(startedAt: afterSuccess) == .apply)
    }
}
