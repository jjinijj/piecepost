import CloudKit
import Foundation

/// 업로드할 우표 값. 메인 스레드의 `Stamp`에서 뽑아 동기화 엔진(백그라운드)으로 넘긴다.
nonisolated struct StampUploadValues: Sendable {
    let date: String
    let note: String
    let createdAt: Date
    let updatedAt: Date
    let schemaVersion: Int
    let systemFields: Data?
    let photoNeedsUpload: Bool
    let photoURL: URL
    let thumbnailURL: URL
}

/// 받은 레코드에서 꺼낸 값. 사진 URL은 CloudKit 임시 파일이므로 받는 즉시 앱 폴더로 복사해야 한다.
nonisolated struct ReceivedStamp: Sendable, Equatable {
    let date: String
    let note: String
    let createdAt: Date
    let updatedAt: Date
    /// 이 앱보다 높은 값이어도 아는 필드만 반영한다. 기록은 호출하는 쪽에서 남긴다.
    let schemaVersion: Int
    let photoFileURL: URL
    let thumbnailFileURL: URL
    let systemFields: Data
}

/// 오류에는 필드 이름만 담는다. 레코드 내용은 담지 않는다(진단 로그 규칙).
nonisolated enum StampRecordError: Error, Equatable {
    case wrongRecordType
    case invalidRecordName
    case dateMismatch
    case missingField(String)
}

/// `Stamp` ↔ `CKRecord` 변환. 레코드 형식은 docs/system-design.md 3.1과 똑같이 쓴다.
/// 필드 이름·타입은 운영 스키마 배포 후 바꿀 수 없으므로 이 파일에서만 정의한다.
nonisolated enum StampRecordMapper {
    static let recordType = "Stamp"
    static let zoneName = "Stamps"
    static let recordNamePrefix = "stamp-"

    enum Field {
        static let date = "date"                    // String
        static let note = "note"                    // String
        static let photo = "photo"                  // Asset
        static let thumbnail = "thumbnail"          // Asset
        static let createdAt = "createdAt"          // Date/Time
        static let updatedAt = "updatedAt"          // Date/Time
        static let schemaVersion = "schemaVersion"  // Int(64)
    }

    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    static func recordName(for date: String) -> String {
        recordNamePrefix + date
    }

    static func recordID(for date: String) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName(for: date), zoneID: zoneID)
    }

    /// `stamp-YYYY-MM-DD` 형식이 아니거나 없는 날짜면 nil.
    static func date(from recordID: CKRecord.ID) -> String? {
        let name = recordID.recordName
        guard name.hasPrefix(recordNamePrefix) else { return nil }
        let date = String(name.dropFirst(recordNamePrefix.count))
        return StampDate.isValid(date) ? date : nil
    }

    // MARK: 보내기

    /// 서버에 올라간 적이 없거나 사진도 올려야 하면 필드 전부를, 아니면 `note`·`updatedAt`만 넣는다.
    /// 시스템 필드로 복원한 레코드는 값이 비어 있어 넣은 필드만 서버로 간다(기록만 수정 시 사진 재업로드 방지).
    static func record(from values: StampUploadValues) -> CKRecord {
        let expectedID = recordID(for: values.date)
        let restored = values.systemFields
            .flatMap(record(fromSystemFields:))
            .flatMap { $0.recordID == expectedID ? $0 : nil }
        let record = restored ?? CKRecord(recordType: recordType, recordID: expectedID)
        let includesAllFields = restored == nil || values.photoNeedsUpload

        record[Field.note] = values.note
        record[Field.updatedAt] = values.updatedAt
        if includesAllFields {
            record[Field.date] = values.date
            record[Field.createdAt] = values.createdAt
            record[Field.schemaVersion] = Int64(values.schemaVersion)
            record[Field.photo] = CKAsset(fileURL: values.photoURL)
            record[Field.thumbnail] = CKAsset(fileURL: values.thumbnailURL)
        }
        return record
    }

    // MARK: 받기

    static func receivedStamp(from record: CKRecord) throws -> ReceivedStamp {
        guard record.recordType == recordType else { throw StampRecordError.wrongRecordType }
        guard let nameDate = date(from: record.recordID) else { throw StampRecordError.invalidRecordName }
        guard let date = record[Field.date] as? String else { throw StampRecordError.missingField(Field.date) }
        guard date == nameDate else { throw StampRecordError.dateMismatch }

        guard let createdAt = record[Field.createdAt] as? Date else {
            throw StampRecordError.missingField(Field.createdAt)
        }
        guard let updatedAt = record[Field.updatedAt] as? Date else {
            throw StampRecordError.missingField(Field.updatedAt)
        }
        guard let schemaVersion = record[Field.schemaVersion] as? Int64 else {
            throw StampRecordError.missingField(Field.schemaVersion)
        }
        guard let photoURL = (record[Field.photo] as? CKAsset)?.fileURL else {
            throw StampRecordError.missingField(Field.photo)
        }
        guard let thumbnailURL = (record[Field.thumbnail] as? CKAsset)?.fileURL else {
            throw StampRecordError.missingField(Field.thumbnail)
        }

        return ReceivedStamp(
            date: date,
            // 기록은 선택 입력이라 없으면 빈 문자열. 다른 기기 값이어도 로컬 규칙대로 다시 정리한다.
            note: StampNote.normalize(record[Field.note] as? String ?? ""),
            createdAt: createdAt,
            updatedAt: updatedAt,
            schemaVersion: Int(schemaVersion),
            photoFileURL: photoURL,
            thumbnailFileURL: thumbnailURL,
            systemFields: encodeSystemFields(of: record)
        )
    }

    // MARK: 시스템 필드

    static func encodeSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
