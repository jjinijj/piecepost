import Foundation
import Observation
import OSLog

/// 동기화 진단 로그. OSLog에 남기고, 시험 화면에 보여줄 최근 항목을 메모리에 보관한다.
///
/// 상태·개수·필드 이름·오류 코드만 남긴다. 기록 내용·사진·날짜는 남기지 않는다(불변 규칙 8).
@Observable
final class SyncLog {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let time: Date
        let message: String
    }

    static let maxEntries = 100

    /// 최근 항목이 앞에 온다.
    private(set) var entries: [Entry] = []

    @ObservationIgnored
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PiecePost", category: "sync")

    func add(_ message: String, now: Date = .now) {
        logger.info("\(message, privacy: .public)")
        entries.insert(Entry(time: now, message: message), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }
}
