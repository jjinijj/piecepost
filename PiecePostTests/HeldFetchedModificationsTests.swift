import Testing
@testable import PiecePost

/// 기획서 settings-erase-records 결정 4·8(왕복 2, Codex 지적): 지우는 동안 받은 다른 기기의 수정은 지운 뒤 다시 받고,
/// 자기 삭제를 포함한 삭제는 버린다.
@MainActor
struct HeldFetchedModificationsTests {
    @Test func successReturnsHeldModificationsToRetry() {
        var held = HeldFetchedModifications()
        held.hold(modified: ["stamp-2026-11-04", "stamp-2026-11-05"])

        #expect(held.release(erased: true) == ["stamp-2026-11-04", "stamp-2026-11-05"])
        #expect(held.names.isEmpty)
    }

    /// 실패하면 다시 받기 목록에 이미 수정·삭제가 모두 있으므로 더 넣지 않는다.
    @Test func failureReturnsNothing() {
        var held = HeldFetchedModifications()
        held.hold(modified: ["stamp-2026-11-04"])

        #expect(held.release(erased: false).isEmpty)
        #expect(held.names.isEmpty)
    }

    @Test func sameNameHeldOnce() {
        var held = HeldFetchedModifications()
        held.hold(modified: ["stamp-2026-11-04"])
        held.hold(modified: ["stamp-2026-11-04", "stamp-2026-11-06"])

        #expect(held.release(erased: true) == ["stamp-2026-11-04", "stamp-2026-11-06"])
    }

    @Test func nothingHeld() {
        var held = HeldFetchedModifications()
        #expect(held.release(erased: true).isEmpty)
    }

    /// 한 번 내보낸 뒤 다음 지우기에 이전 이름이 섞이지 않는다.
    @Test func releaseClearsForNextErase() {
        var held = HeldFetchedModifications()
        held.hold(modified: ["stamp-2026-11-04"])
        _ = held.release(erased: false)
        held.hold(modified: ["stamp-2026-11-07"])

        #expect(held.release(erased: true) == ["stamp-2026-11-07"])
    }
}
