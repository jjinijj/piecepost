import Foundation
import SwiftData

/// 받은 우표를 어떻게 처리했는지. 로그에는 이 값만 남긴다(날짜·내용은 남기지 않음).
nonisolated enum ReceiveOutcome: Equatable, Sendable {
    case inserted
    case updated
    /// 로컬에 아직 보내지 않은 변경이 있어 건드리지 않음. 충돌 처리는 다음 PR에서 정한다.
    case skippedLocalPending
    /// 로컬에서 삭제 대기 중이라 건드리지 않음(삭제 우선).
    case skippedPendingDeletion
}

/// CloudKit에서 받은 변경과 보낸 결과를 로컬 저장소에 반영하는 규칙.
/// CloudKit을 직접 부르지 않으므로 iCloud 없이 테스트할 수 있다.
///
/// 여기서 바꾼 내용은 `StampStore.onLocalChange`를 부르지 않는다. 받은 변경이 다시 업로드되지 않게 하기 위함.
final class SyncChangeApplier {
    private let context: ModelContext
    private let fileStore: StampFileStore

    init(context: ModelContext, fileStore: StampFileStore = StampFileStore()) {
        self.context = context
        self.fileStore = fileStore
    }

    // MARK: 받은 변경

    /// 받은 우표를 반영한다. 사진 임시 파일은 이 안에서 앱 폴더로 복사한다.
    @discardableResult
    func applyReceived(_ received: ReceivedStamp) throws -> ReceiveOutcome {
        let existing = try stamp(for: received.date)
        if let existing {
            if existing.pendingDeletion { return .skippedPendingDeletion }
            if existing.needsUpload { return .skippedLocalPending }
        }

        let paths = try fileStore.importFiles(
            photoFrom: received.photoFileURL,
            thumbnailFrom: received.thumbnailFileURL
        )
        let outcome: ReceiveOutcome
        let replacedPaths: [String]
        if let existing {
            replacedPaths = [existing.photoPath, existing.thumbnailPath]
            existing.note = received.note
            existing.photoPath = paths.photoPath
            existing.thumbnailPath = paths.thumbnailPath
            existing.createdAt = received.createdAt
            existing.updatedAt = received.updatedAt
            existing.schemaVersion = received.schemaVersion
            existing.systemFields = received.systemFields
            existing.needsUpload = false
            existing.photoNeedsUpload = false
            outcome = .updated
        } else {
            replacedPaths = []
            context.insert(Stamp(
                date: received.date,
                note: received.note,
                photoPath: paths.photoPath,
                thumbnailPath: paths.thumbnailPath,
                createdAt: received.createdAt,
                updatedAt: received.updatedAt,
                schemaVersion: received.schemaVersion,
                systemFields: received.systemFields,
                needsUpload: false,
                photoNeedsUpload: false
            ))
            outcome = .inserted
        }

        do {
            try save()
        } catch {
            fileStore.remove(paths.all)
            throw error
        }
        fileStore.remove(replacedPaths)
        return outcome
    }

    /// 서버에서 지워진 우표. 로컬에 보낼 변경이 있어도 지운다(삭제 우선).
    /// `unknownItem`(올렸는데 서버에 이미 없음)도 같은 처리를 한다.
    /// - Returns: 로컬에서 지웠으면 true
    @discardableResult
    func applyServerDeletion(date: String) throws -> Bool {
        guard let stamp = try stamp(for: date) else { return false }
        try removeRowAndFiles(stamp)
        return true
    }

    // MARK: 내부

    private func stamp(for date: String) throws -> Stamp? {
        var descriptor = FetchDescriptor<Stamp>(predicate: #Predicate { $0.date == date })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func removeRowAndFiles(_ stamp: Stamp) throws {
        let paths = [stamp.photoPath, stamp.thumbnailPath]
        context.delete(stamp)
        try save()
        fileStore.remove(paths)
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
