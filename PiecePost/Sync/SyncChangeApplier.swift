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
    /// 로컬에 보낼 변경이 있었지만 받은 쪽 `updatedAt`이 늦어 받은 내용으로 바꿈. 로컬 변경은 버린다.
    case conflictServerWon
    /// 로컬에 보낼 변경이 있고 로컬이 이겨 유지함. 받은 시스템 필드만 저장하고 계속 보낸다.
    /// - resendsPhoto: 서버 사진이 로컬과 달라 다음 보내기에 사진도 넣는지
    case conflictLocalWon(resendsPhoto: Bool)
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

    /// 업로드할 값. 행이 없거나, 삭제 대기거나, 보낼 변경이 없으면 nil(보낼 목록에서 뺀다).
    /// 충돌로 서버 내용을 받아 보낼 변경이 없어진 우표가 엔진에 남아 있어도 다시 보내지 않게 한다.
    func uploadValues(for date: String) throws -> StampUploadValues? {
        guard let stamp = try stamp(for: date), !stamp.pendingDeletion, stamp.needsUpload else { return nil }
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
    ///
    /// 로컬에 보낼 변경이 있으면 `updatedAt`이 늦은 쪽을 남긴다. 받은 쪽이 늦으면 받은 내용으로 바꾸고
    /// 로컬 변경은 버린다. 로컬이 늦거나 같으면 로컬을 유지하고 받은 시스템 필드만 저장해,
    /// 다음 보내기가 최신 서버 레코드를 기준으로 하게 한다(`serverRecordChanged` 반복 방지).
    @discardableResult
    func applyReceived(_ received: ReceivedStamp) throws -> ReceiveOutcome {
        guard let existing = try stamp(for: received.date) else {
            try insert(received)
            return .inserted
        }
        if existing.pendingDeletion { return .skippedPendingDeletion }
        guard existing.needsUpload else {
            try replace(existing, with: received)
            return .updated
        }
        if Self.isLater(received.updatedAt, than: existing.updatedAt) {
            try replace(existing, with: received)
            return .conflictServerWon
        }
        return .conflictLocalWon(resendsPhoto: try keepLocal(existing, over: received))
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

    /// `a`가 `b`보다 늦은지. CloudKit이 밀리초까지만 저장하므로 그보다 작은 차이는 같은 시각으로 본다.
    private static func isLater(_ a: Date, than b: Date) -> Bool {
        a.timeIntervalSince(b) >= timestampTolerance
    }

    private func insert(_ received: ReceivedStamp) throws {
        let paths = try fileStore.importFiles(
            photoFrom: received.photoFileURL,
            thumbnailFrom: received.thumbnailFileURL
        )
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
        do {
            try save()
        } catch {
            fileStore.remove(paths.all)
            throw error
        }
    }

    /// 받은 내용으로 바꾸고 보낼 변경을 없앤다. 밀린 로컬 사진 파일은 저장이 끝나면 지운다.
    private func replace(_ stamp: Stamp, with received: ReceivedStamp) throws {
        let paths = try fileStore.importFiles(
            photoFrom: received.photoFileURL,
            thumbnailFrom: received.thumbnailFileURL
        )
        let replacedPaths = [stamp.photoPath, stamp.thumbnailPath]
        stamp.note = received.note
        stamp.photoPath = paths.photoPath
        stamp.thumbnailPath = paths.thumbnailPath
        stamp.createdAt = received.createdAt
        stamp.updatedAt = received.updatedAt
        stamp.schemaVersion = received.schemaVersion
        stamp.systemFields = received.systemFields
        stamp.needsUpload = false
        stamp.photoNeedsUpload = false
        do {
            try save()
        } catch {
            fileStore.remove(paths.all)
            throw error
        }
        fileStore.remove(replacedPaths)
    }

    /// 로컬 내용을 유지하고 서버 레코드의 시스템 필드만 저장한다. 받은 사진은 복사하지 않는다.
    /// 서버 사진이 로컬과 다르면 사진도 다시 보내게 해서, 서버에 밀린 쪽 사진과 이긴 쪽 기록이
    /// 섞여 남지 않게 한다. 같으면 기록만 보낸다(불변 규칙 5).
    /// - Returns: 사진도 다시 보내게 됐으면 true
    private func keepLocal(_ stamp: Stamp, over received: ReceivedStamp) throws -> Bool {
        stamp.systemFields = received.systemFields
        var resendsPhoto = false
        if !stamp.photoNeedsUpload && !hasSamePhoto(stamp, as: received) {
            stamp.photoNeedsUpload = true
            resendsPhoto = true
        }
        try save()
        return resendsPhoto
    }

    /// 파일 내용으로 비교한다. 어느 쪽이든 읽을 수 없으면 다르다고 본다(사진을 다시 보내는 쪽이 안전).
    private func hasSamePhoto(_ stamp: Stamp, as received: ReceivedStamp) -> Bool {
        FileManager.default.contentsEqual(
            atPath: fileStore.url(for: stamp.photoPath).path(percentEncoded: false),
            andPath: received.photoFileURL.path(percentEncoded: false)
        )
    }

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
