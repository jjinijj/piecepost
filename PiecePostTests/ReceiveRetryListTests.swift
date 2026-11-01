import Foundation
import Testing
@testable import PiecePost

struct ReceiveRetryListTests {
    private let fileURL = URL.temporaryDirectory
        .appending(path: "ReceiveRetryListTests-\(UUID().uuidString)")
        .appending(path: "receive-retry.json")

    @Test func startsEmpty() {
        #expect(ReceiveRetryList(fileURL: fileURL).names().isEmpty)
    }

    @Test func addedNamesSurviveNewInstance() throws {
        let list = ReceiveRetryList(fileURL: fileURL)
        try list.add("stamp-2026-11-18")
        try list.add("stamp-2026-11-19")
        try list.add("stamp-2026-11-18")  // 중복은 한 번만
        #expect(ReceiveRetryList(fileURL: fileURL).names() == ["stamp-2026-11-18", "stamp-2026-11-19"])
    }

    @Test func removeDeletesOnlyGivenNames() throws {
        let list = ReceiveRetryList(fileURL: fileURL)
        try list.add("stamp-2026-11-18")
        try list.add("stamp-2026-11-19")
        try list.remove(["stamp-2026-11-18", "stamp-2026-01-01"])
        #expect(list.names() == ["stamp-2026-11-19"])
    }

    @Test func removingLastNameDeletesFile() throws {
        let list = ReceiveRetryList(fileURL: fileURL)
        try list.add("stamp-2026-11-18")
        try list.remove(["stamp-2026-11-18"])
        #expect(list.names().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    @Test func corruptFileBecomesEmpty() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("깨짐".utf8).write(to: fileURL)
        #expect(ReceiveRetryList(fileURL: fileURL).names().isEmpty)
    }
}
