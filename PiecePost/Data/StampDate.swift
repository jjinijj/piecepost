import Foundation

/// 우표 날짜 문자열("YYYY-MM-DD")과 `Date` 사이의 변환. 앱 전체에서 이곳에서만 변환한다.
///
/// - "그날이 며칠인가"는 기기 시간대(`Calendar.current.timeZone`)를 따른다.
/// - 문자열은 그레고리력 + `en_US_POSIX`로 고정한다. 기기 달력이 불교력·일본력이어도
///   레코드 이름에 "2569-11-18" 같은 값이 들어가지 않게 하기 위함.
nonisolated enum StampDate {
    static func string(from date: Date, timeZone: TimeZone = Calendar.current.timeZone) -> String {
        formatter(timeZone: timeZone).string(from: date)
    }

    /// 형식이 틀리거나 존재하지 않는 날짜면 nil. 반환값은 그날 시작 시각.
    static func date(from string: String, timeZone: TimeZone = Calendar.current.timeZone) -> Date? {
        guard hasValidShape(string) else { return nil }
        let formatter = formatter(timeZone: timeZone)
        // 되돌려 같은 문자열이 나와야 통과. "2026-02-30" 같은 값을 걸러낸다.
        guard let date = formatter.date(from: string), formatter.string(from: date) == string else {
            return nil
        }
        return date
    }

    static func isValid(_ string: String) -> Bool {
        date(from: string, timeZone: TimeZone(identifier: "UTC")!) != nil
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    /// 숫자 4-2-2 자리와 하이픈 위치만 검사한다.
    private static func hasValidShape(_ string: String) -> Bool {
        let bytes = Array(string.utf8)
        guard bytes.count == 10 else { return false }
        for (index, byte) in bytes.enumerated() {
            if index == 4 || index == 7 {
                guard byte == UInt8(ascii: "-") else { return false }
            } else {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return false }
            }
        }
        return true
    }
}
