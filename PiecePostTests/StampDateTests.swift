import Foundation
import Testing
@testable import PiecePost

struct StampDateTests {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    @Test func roundTrip() throws {
        let date = try #require(StampDate.date(from: "2026-11-18", timeZone: seoul))
        #expect(StampDate.string(from: date, timeZone: seoul) == "2026-11-18")
    }

    @Test func usesDeviceTimeZoneForTheDay() {
        // 2026-11-18 15:30 UTC = 서울 2026-11-19 00:30
        let instant = Date(timeIntervalSince1970: 1_795_015_800)
        #expect(StampDate.string(from: instant, timeZone: TimeZone(identifier: "UTC")!) == "2026-11-18")
        #expect(StampDate.string(from: instant, timeZone: seoul) == "2026-11-19")
    }

    @Test(arguments: ["2026-11-18", "2028-02-29", "1999-01-01", "2100-12-31"])
    func acceptsValidDates(_ value: String) {
        #expect(StampDate.isValid(value))
    }

    @Test(arguments: [
        "2026-02-30",  // 없는 날짜
        "2027-02-29",  // 평년
        "2026-13-01",
        "2026-1-5",    // 자릿수
        "2026/11/18",
        "２０２６-11-18", // 전각 숫자
        "2026-11-18 ",
        "",
    ])
    func rejectsInvalidDates(_ value: String) {
        #expect(!StampDate.isValid(value))
    }

    @Test func ignoresNonGregorianDeviceCalendar() throws {
        // 기기 달력 설정과 무관하게 그레고리력 연도가 나와야 한다.
        let date = try #require(StampDate.date(from: "2026-11-18", timeZone: seoul))
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = seoul
        #expect(buddhist.component(.year, from: date) == 2569)
        #expect(StampDate.string(from: date, timeZone: seoul) == "2026-11-18")
    }
}
