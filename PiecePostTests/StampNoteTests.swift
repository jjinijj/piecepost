import Testing
@testable import PiecePost

struct StampNoteTests {
    @Test func trimsLeadingAndTrailingSpaces() {
        #expect(StampNote.normalize("  맑음  ") == "맑음")
    }

    @Test(arguments: ["", "   ", "\n", " \n\t "])
    func whitespaceOnlyBecomesEmpty(_ value: String) {
        #expect(StampNote.normalize(value) == "")
    }

    @Test func replacesNewlinesWithSpaces() {
        #expect(StampNote.normalize("바다\n산책") == "바다 산책")
        #expect(StampNote.normalize("바다\r\n산책") == "바다 산책")
    }

    @Test func keepsExactlyFiftyCharacters() {
        let fifty = String(repeating: "가", count: 50)
        #expect(StampNote.normalize(fifty) == fifty)
        #expect(StampNote.normalize(fifty + "나").count == 50)
    }

    @Test func countsComposedCharactersAsOne() {
        // 가족 이모지(여러 스칼라)도 String.count 기준 1자
        let family = "👨‍👩‍👧‍👦"
        let result = StampNote.normalize(String(repeating: family, count: 60))
        #expect(result.count == 50)
        #expect(result == String(repeating: family, count: 50))
    }

    @Test func trimsTrailingSpaceLeftByTruncation() {
        let input = String(repeating: "가", count: 49) + " 나"
        #expect(StampNote.normalize(input) == String(repeating: "가", count: 49))
    }
}
