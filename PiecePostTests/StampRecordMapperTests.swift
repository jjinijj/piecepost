import CloudKit
import Foundation
import Testing
@testable import PiecePost

struct StampRecordMapperTests {
    private typealias Field = StampRecordMapper.Field

    private let created = Date(timeIntervalSince1970: 1_800_000_000)
    private let updated = Date(timeIntervalSince1970: 1_800_000_600)
    private let photoURL = URL.temporaryDirectory.appending(path: "mapper-photo.heic")
    private let thumbnailURL = URL.temporaryDirectory.appending(path: "mapper-thumb.heic")

    private func values(
        note: String = "맑음",
        systemFields: Data? = nil,
        photoNeedsUpload: Bool = true
    ) -> StampUploadValues {
        StampUploadValues(
            date: "2026-11-18",
            note: note,
            createdAt: created,
            updatedAt: updated,
            schemaVersion: 1,
            systemFields: systemFields,
            photoNeedsUpload: photoNeedsUpload,
            photoURL: photoURL,
            thumbnailURL: thumbnailURL
        )
    }

    /// 서버에서 받은 적이 있는 상태를 흉내 낸 시스템 필드.
    private func uploadedSystemFields() -> Data {
        let record = CKRecord(recordType: "Stamp", recordID: StampRecordMapper.recordID(for: "2026-11-18"))
        return StampRecordMapper.encodeSystemFields(of: record)
    }

    // MARK: 고정 값

    @Test func identifiersMatchDesign() {
        let id = StampRecordMapper.recordID(for: "2026-11-18")
        #expect(id.recordName == "stamp-2026-11-18")
        #expect(id.zoneID.zoneName == "Stamps")
        #expect(id.zoneID.ownerName == CKCurrentUserDefaultName)
        #expect(StampRecordMapper.recordType == "Stamp")
    }

    @Test(arguments: [
        ("stamp-2026-11-18", "2026-11-18"),
        ("stamp-2026-02-30", nil),
        ("stamp-2026-1-5", nil),
        ("2026-11-18", nil),
        ("Stamp-2026-11-18", nil),
    ] as [(String, String?)])
    func parsesDateFromRecordName(_ name: String, _ expected: String?) {
        let id = CKRecord.ID(recordName: name, zoneID: StampRecordMapper.zoneID)
        #expect(StampRecordMapper.date(from: id) == expected)
    }

    // MARK: 보내기

    @Test func firstUploadHasAllFieldsWithDesignTypes() throws {
        let record = StampRecordMapper.record(from: values(photoNeedsUpload: true))

        // docs/system-design.md 3.1 표와 같은 이름·타입이어야 한다.
        #expect(record.recordType == "Stamp")
        #expect(Set(record.allKeys()) == [
            "date", "note", "photo", "thumbnail", "createdAt", "updatedAt", "schemaVersion",
        ])
        #expect(record["date"] as? String == "2026-11-18")
        #expect(record["note"] as? String == "맑음")
        #expect(record["createdAt"] as? Date == created)
        #expect(record["updatedAt"] as? Date == updated)
        #expect((record["photo"] as? CKAsset)?.fileURL == photoURL)
        #expect((record["thumbnail"] as? CKAsset)?.fileURL == thumbnailURL)
        let version = try #require(record["schemaVersion"] as? NSNumber)
        #expect(String(cString: version.objCType) == "q")  // Int64
        #expect(version.int64Value == 1)
    }

    @Test func newRecordWithoutSystemFieldsAlwaysIncludesPhoto() {
        // photoNeedsUpload가 false여도 서버에 처음 올리는 거면 사진이 있어야 한다.
        let record = StampRecordMapper.record(from: values(systemFields: nil, photoNeedsUpload: false))
        #expect(Set(record.changedKeys()).isSuperset(of: ["photo", "thumbnail"]))
    }

    @Test func noteOnlyEditSendsOnlyNoteAndUpdatedAt() {
        let record = StampRecordMapper.record(
            from: values(note: "흐림", systemFields: uploadedSystemFields(), photoNeedsUpload: false)
        )
        #expect(Set(record.changedKeys()) == ["note", "updatedAt"])
        #expect(record["note"] as? String == "흐림")
        #expect(record.recordID.recordName == "stamp-2026-11-18")
    }

    @Test func photoChangeOnUploadedRecordSendsAllFields() {
        let record = StampRecordMapper.record(
            from: values(systemFields: uploadedSystemFields(), photoNeedsUpload: true)
        )
        #expect(Set(record.changedKeys()) == [
            "date", "note", "photo", "thumbnail", "createdAt", "updatedAt", "schemaVersion",
        ])
    }

    @Test func ignoresSystemFieldsOfAnotherRecord() {
        let other = CKRecord(recordType: "Stamp", recordID: StampRecordMapper.recordID(for: "2026-01-01"))
        let record = StampRecordMapper.record(
            from: values(systemFields: StampRecordMapper.encodeSystemFields(of: other), photoNeedsUpload: false)
        )
        #expect(record.recordID.recordName == "stamp-2026-11-18")
        #expect(Set(record.changedKeys()).contains("photo"))
    }

    @Test func ignoresCorruptSystemFields() {
        let record = StampRecordMapper.record(from: values(systemFields: Data([0, 1, 2]), photoNeedsUpload: false))
        #expect(record.recordID.recordName == "stamp-2026-11-18")
        #expect(record.allKeys().count == 7)
    }

    // MARK: 시스템 필드

    @Test func systemFieldsRoundTripKeepsIdentity() throws {
        let original = CKRecord(recordType: "Stamp", recordID: StampRecordMapper.recordID(for: "2026-11-18"))
        original["note"] = "들어가면 안 됨"
        let data = StampRecordMapper.encodeSystemFields(of: original)

        let restored = try #require(StampRecordMapper.record(fromSystemFields: data))
        #expect(restored.recordID == original.recordID)
        #expect(restored.recordType == "Stamp")
        #expect(restored.allKeys().isEmpty)
    }

    // MARK: 받기

    private func serverRecord(
        name: String = "stamp-2026-11-18",
        type: String = "Stamp",
        omitting omitted: Set<String> = [],
        overrides: [String: (any CKRecordValueProtocol)?] = [:]
    ) -> CKRecord {
        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: StampRecordMapper.zoneID))
        let fields: [String: any CKRecordValueProtocol] = [
            "date": "2026-11-18",
            "note": "맑음",
            "createdAt": created,
            "updatedAt": updated,
            "schemaVersion": Int64(1),
            "photo": CKAsset(fileURL: photoURL),
            "thumbnail": CKAsset(fileURL: thumbnailURL),
        ]
        for (key, value) in fields where !omitted.contains(key) {
            record[key] = value
        }
        for (key, value) in overrides {
            record[key] = value
        }
        return record
    }

    @Test func receivesValidRecord() throws {
        let received = try StampRecordMapper.receivedStamp(from: serverRecord())
        #expect(received.date == "2026-11-18")
        #expect(received.note == "맑음")
        #expect(received.createdAt == created)
        #expect(received.updatedAt == updated)
        #expect(received.schemaVersion == 1)
        #expect(received.photoFileURL == photoURL)
        #expect(received.thumbnailFileURL == thumbnailURL)
        #expect(StampRecordMapper.record(fromSystemFields: received.systemFields)?.recordID.recordName == "stamp-2026-11-18")
    }

    @Test func normalizesReceivedNote() throws {
        let tooLong = "  바다\n" + String(repeating: "가", count: 60)
        let received = try StampRecordMapper.receivedStamp(from: serverRecord(overrides: ["note": tooLong]))
        #expect(received.note.count == 50)
        #expect(received.note.hasPrefix("바다 가"))
    }

    @Test func missingNoteBecomesEmpty() throws {
        let received = try StampRecordMapper.receivedStamp(from: serverRecord(omitting: ["note"]))
        #expect(received.note == "")
    }

    @Test func keepsHigherSchemaVersion() throws {
        let received = try StampRecordMapper.receivedStamp(from: serverRecord(overrides: ["schemaVersion": Int64(2)]))
        #expect(received.schemaVersion == 2)
    }

    @Test func rejectsWrongRecordType() {
        #expect(throws: StampRecordError.wrongRecordType) {
            try StampRecordMapper.receivedStamp(from: serverRecord(type: "Other"))
        }
    }

    @Test(arguments: ["stamp-2026-02-30", "2026-11-18", "stamp-abc"])
    func rejectsInvalidRecordName(_ name: String) {
        #expect(throws: StampRecordError.invalidRecordName) {
            try StampRecordMapper.receivedStamp(from: serverRecord(name: name))
        }
    }

    @Test func rejectsDateNotMatchingRecordName() {
        #expect(throws: StampRecordError.dateMismatch) {
            try StampRecordMapper.receivedStamp(from: serverRecord(overrides: ["date": "2026-11-19"]))
        }
    }

    @Test(arguments: ["date", "createdAt", "updatedAt", "schemaVersion", "photo", "thumbnail"])
    func rejectsMissingRequiredField(_ field: String) {
        #expect(throws: StampRecordError.missingField(field)) {
            try StampRecordMapper.receivedStamp(from: serverRecord(omitting: [field]))
        }
    }

    @Test func rejectsWrongFieldType() {
        #expect(throws: StampRecordError.missingField("updatedAt")) {
            try StampRecordMapper.receivedStamp(from: serverRecord(overrides: ["updatedAt": "2026-11-18"]))
        }
    }
}
