import Foundation
import Testing
@testable import PiecePost

struct SyncStateStoreTests {
    private struct SampleState: Codable, Equatable {
        let token: String
        let count: Int
    }

    private let store = SyncStateStore(
        fileURL: URL.temporaryDirectory
            .appending(path: "SyncStateStoreTests-\(UUID().uuidString)")
            .appending(path: "engine-state.json")
    )

    @Test func missingFileLoadsNil() throws {
        #expect(try store.load(SampleState.self) == nil)
    }

    @Test func savedStateLoadsBack() throws {
        let state = SampleState(token: "abc", count: 3)
        try store.save(state)
        #expect(try store.load(SampleState.self) == state)
    }

    @Test func corruptFileThrows() throws {
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("깨진 파일".utf8).write(to: store.fileURL)
        #expect(throws: (any Error).self) {
            try store.load(SampleState.self)
        }
    }

    @Test func clearRemovesFile() throws {
        try store.save(SampleState(token: "abc", count: 1))
        store.clear()
        #expect(try store.load(SampleState.self) == nil)
    }
}
