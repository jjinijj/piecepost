import Foundation

/// 기록(note) 정리 규칙. 선택 입력, 최대 50자(`String.count`), 줄바꿈 불가, 앞뒤 공백 제거.
nonisolated enum StampNote {
    static let maxLength = 50

    /// 줄바꿈은 공백으로 바꾸고, 앞뒤 공백을 지운 뒤 50자로 자른다. 공백만 있으면 "".
    static func normalize(_ raw: String) -> String {
        let singleLine = raw
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .joined(separator: " ")
        let trimmed = singleLine.trimmingCharacters(in: .whitespaces)
        // 자른 끝에 공백이 남을 수 있어 한 번 더 지운다.
        return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }

    /// 입력 중에 쓰는 제한. 줄바꿈을 공백으로 바꾸고 50자를 넘지 않게만 한다.
    /// 앞뒤 공백은 입력 중에 지우지 않는다(띄어쓰기를 막지 않기 위해). 저장할 때 `normalize`로 지운다.
    static func limitInput(_ raw: String) -> String {
        let singleLine = raw
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .joined(separator: " ")
        return String(singleLine.prefix(maxLength))
    }
}
