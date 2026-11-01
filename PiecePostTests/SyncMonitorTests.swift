import Foundation
import Testing
@testable import PiecePost

@MainActor
struct SyncMonitorTests {
    @Test func logKeepsNewestFirst() {
        let log = SyncLog()
        log.add("첫째", now: Date(timeIntervalSince1970: 1))
        log.add("둘째", now: Date(timeIntervalSince1970: 2))
        #expect(log.entries.map(\.message) == ["둘째", "첫째"])
    }

    @Test func logKeepsAtMostMaxEntries() {
        let log = SyncLog()
        for index in 0..<(SyncLog.maxEntries + 20) {
            log.add("항목 \(index)")
        }
        #expect(log.entries.count == SyncLog.maxEntries)
        #expect(log.entries.first?.message == "항목 \(SyncLog.maxEntries + 19)")
        #expect(log.entries.last?.message == "항목 20")
    }

    @Test func monitorStartsNotConnected() {
        let monitor = SyncMonitor()
        #expect(monitor.status == .notStarted)
        #expect(monitor.status.label == "연결 전")
    }

    @Test func statusLabels() {
        #expect(SyncStatus.idle.label == "정상")
        #expect(SyncStatus.syncing.label == "동기화 중")
        #expect(SyncStatus.iCloudUnavailable.label == "iCloud 꺼짐")
        #expect(SyncStatus.quotaExceeded.label == "용량 부족")
        #expect(SyncStatus.error(code: 4).label == "오류(4)")
    }
}
