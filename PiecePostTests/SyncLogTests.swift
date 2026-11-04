import Foundation
import Testing
@testable import PiecePost

@MainActor
struct SyncLogTests {
    @Test func clearRemovesAllEntries() {
        let log = SyncLog()
        log.add("하나")
        log.add("둘")

        log.clear()

        #expect(log.entries.isEmpty)
        log.add("셋")
        #expect(log.entries.map(\.message) == ["셋"])
    }
}
