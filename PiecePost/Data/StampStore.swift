import Foundation
import SwiftData

enum StampStoreError: Error, Equatable {
    case invalidDate
    case missingPhoto
    case alreadyExists
    case notFound
}

/// 화면이 우표를 쓰는 유일한 창구. 로컬 저장소만 다루고, 바뀐 날짜는 `onLocalChange`로 알린다.
/// CloudKit 업로드는 Sync/가 이 알림을 받아 처리한다.
final class StampStore {
    private let context: ModelContext
    private let onLocalChange: (String) -> Void

    init(context: ModelContext, onLocalChange: @escaping (String) -> Void = { _ in }) {
        self.context = context
        self.onLocalChange = onLocalChange
    }

    /// 삭제 대기 중인 것을 뺀 우표, 날짜 내림차순.
    func visibleStamps() throws -> [Stamp] {
        let descriptor = FetchDescriptor<Stamp>(
            predicate: #Predicate { !$0.pendingDeletion },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// 삭제 대기 중인 것까지 포함해 날짜로 찾는다.
    func stamp(for date: String) throws -> Stamp? {
        var descriptor = FetchDescriptor<Stamp>(predicate: #Predicate { $0.date == date })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func create(
        date: String,
        note: String,
        photoPath: String,
        thumbnailPath: String,
        now: Date = .now
    ) throws -> Stamp {
        guard StampDate.isValid(date) else { throw StampStoreError.invalidDate }
        guard !photoPath.isEmpty, !thumbnailPath.isEmpty else { throw StampStoreError.missingPhoto }

        let normalizedNote = StampNote.normalize(note)
        let result: Stamp
        // unique 속성이 겹치면 SwiftData가 오류 없이 덮어쓰므로 직접 먼저 확인한다.
        if let existing = try stamp(for: date) {
            guard existing.pendingDeletion else { throw StampStoreError.alreadyExists }
            // 삭제 대기 중인 날짜에 다시 만들면 systemFields를 유지해 서버에서 수정으로 처리되게 한다.
            existing.note = normalizedNote
            existing.photoPath = photoPath
            existing.thumbnailPath = thumbnailPath
            existing.createdAt = now
            existing.updatedAt = now
            existing.schemaVersion = Stamp.currentSchemaVersion
            existing.pendingDeletion = false
            existing.needsUpload = true
            existing.photoNeedsUpload = true
            result = existing
        } else {
            result = Stamp(
                date: date,
                note: normalizedNote,
                photoPath: photoPath,
                thumbnailPath: thumbnailPath,
                createdAt: now,
                updatedAt: now,
                needsUpload: true,
                photoNeedsUpload: true
            )
            context.insert(result)
        }

        try save()
        onLocalChange(date)
        return result
    }

    /// 기록만 바꾼다. 사진 관련 필드와 `photoNeedsUpload`는 건드리지 않는다.
    func updateNote(date: String, note: String, now: Date = .now) throws {
        guard let stamp = try stamp(for: date), !stamp.pendingDeletion else {
            throw StampStoreError.notFound
        }
        let normalizedNote = StampNote.normalize(note)
        guard normalizedNote != stamp.note else { return }

        stamp.note = normalizedNote
        stamp.updatedAt = now
        stamp.needsUpload = true

        try save()
        onLocalChange(date)
    }

    /// 서버에 올라간 적이 없으면 바로 지우고, 있으면 삭제 대기로 표시한다.
    func delete(date: String) throws {
        guard let stamp = try stamp(for: date), !stamp.pendingDeletion else {
            throw StampStoreError.notFound
        }
        if stamp.systemFields == nil {
            context.delete(stamp)
        } else {
            stamp.pendingDeletion = true
            stamp.needsUpload = true
        }

        try save()
        onLocalChange(date)
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
