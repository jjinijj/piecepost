import Foundation
import SwiftData

/// 엔진에 넣을 보낼 변경. 레코드 이름은 `StampRecordMapper.recordID(for:)`로 만든다.
nonisolated enum PendingStampChange: Hashable, Sendable {
    case save(date: String)
    case delete(date: String)
}

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
    /// CloudKit의 Date는 밀리초까지만 저장하므로 시각 비교에 이만큼 여유를 둔다.
    static let timestampTolerance: TimeInterval = 0.001

    private let context: ModelContext
    private let fileStore: StampFileStore

    init(context: ModelContext, fileStore: StampFileStore = StampFileStore()) {
        self.context = context
        self.fileStore = fileStore
    }

    // MARK: 보낼 변경

    /// 아직 보내지 못한 변경 전부. 엔진 상태를 잃어도 이 목록으로 복구한다.
    func pendingChanges() throws -> [PendingStampChange] {
        let descriptor = FetchDescriptor<Stamp>(
            predicate: #Predicate { $0.needsUpload },
            sortBy: [SortDescriptor(\.date)]
        )
        return try context.fetch(descriptor).map { stamp in
            stamp.pendingDeletion ? .delete(date: stamp.date) : .save(date: stamp.date)
        }
    }

    /// 로컬에서 바뀐 날짜를 어떤 변경으로 보낼지. 행이 없거나 삭제 대기면 삭제.
    func pendingChange(for date: String) throws -> PendingStampChange {
        guard let stamp = try stamp(for: date), !stamp.pendingDeletion else {
            return .delete(date: date)
        }
        return .save(date: date)
    }

    /// 업로드할 값. 행이 없거나 삭제 대기면 nil(보낼 목록에서 뺀다).
    func uploadValues(for date: String) throws -> StampUploadValues? {
        guard let stamp = try stamp(for: date), !stamp.pendingDeletion else { return nil }
        return StampUploadValues(
            date: stamp.date,
            note: stamp.note,
            createdAt: stamp.createdAt,
            updatedAt: stamp.updatedAt,
            schemaVersion: stamp.schemaVersion,
            systemFields: stamp.systemFields,
            photoNeedsUpload: stamp.photoNeedsUpload,
            photoURL: fileStore.url(for: stamp.photoPath),
            thumbnailURL: fileStore.url(for: stamp.thumbnailPath)
        )
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

    // MARK: 보낸 결과

    /// 저장 성공. 보낸 뒤에 로컬이 또 바뀌었으면 `needsUpload`를 유지해 다시 보내게 한다.
    ///
    /// 늦게 도착한 옛 결과가 더 최신 시스템 필드를 덮어쓰지 않도록, 보낼 때 기준으로 삼은
    /// 시스템 필드가 지금 로컬 값과 같을 때만 반영한다. 다르면 아무것도 바꾸지 않는다.
    /// - Parameters:
    ///   - sentUpdatedAt: 서버가 돌려준 값이 아니라 **보낼 때 넣은** `updatedAt`
    ///   - sentBaseSystemFields: 보낼 때 레코드를 만든 기준 `systemFields`(처음 올렸으면 nil)
    /// - Returns: 반영했으면 true, 옛 결과라 무시했으면 false
    @discardableResult
    func markSaved(
        date: String,
        systemFields: Data,
        sentUpdatedAt: Date,
        sentBaseSystemFields: Data?
    ) throws -> Bool {
        guard let stamp = try stamp(for: date), stamp.systemFields == sentBaseSystemFields else {
            return false
        }
        stamp.systemFields = systemFields
        let unchangedSinceSent = abs(stamp.updatedAt.timeIntervalSince(sentUpdatedAt)) < Self.timestampTolerance
        if !stamp.pendingDeletion && unchangedSinceSent {
            stamp.needsUpload = false
            stamp.photoNeedsUpload = false
        }
        try save()
        return true
    }

    /// 삭제 성공. 삭제 대기 행과 사진 파일을 지운다.
    /// 그사이 같은 날짜로 다시 만들었다면 서버에는 없으니 처음 올리는 것처럼 다시 보낸다.
    func markDeleted(date: String) throws {
        guard let stamp = try stamp(for: date) else { return }
        if stamp.pendingDeletion {
            try removeRowAndFiles(stamp)
        } else {
            stamp.systemFields = nil
            stamp.needsUpload = true
            stamp.photoNeedsUpload = true
            try save()
        }
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
