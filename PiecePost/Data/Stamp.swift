import Foundation
import SwiftData

/// 우표 한 장의 로컬 기록. 필드는 docs/system-design.md 3.2를 따른다.
@Model
final class Stamp {
    static let currentSchemaVersion = 1

    /// "YYYY-MM-DD". 기본 키이자 CloudKit 레코드 이름(`stamp-` + date)의 재료. 생성 후 바꾸지 않는다.
    @Attribute(.unique) var date: String
    var note: String
    /// 앱 폴더 기준 상대 경로. 재설치·업데이트 시 컨테이너 절대 경로가 바뀌기 때문.
    var photoPath: String
    var thumbnailPath: String
    var createdAt: Date
    var updatedAt: Date
    var schemaVersion: Int
    /// 마지막으로 받은 CKRecord 시스템 필드. 서버에 올라간 적이 없으면 nil.
    var systemFields: Data?
    /// iCloud에 아직 올리지 못한 변경이 있는지.
    var needsUpload: Bool
    /// 다음 업로드에 photo·thumbnail Asset을 포함해야 하는지. 기록만 수정할 때는 false로 남는다.
    var photoNeedsUpload: Bool
    /// 삭제 요청 후 업로드 대기 중인지. `PersistentModel.isDeleted`와 이름이 겹쳐 3.2의 isDeleted 대신 쓴다.
    var pendingDeletion: Bool

    init(
        date: String,
        note: String,
        photoPath: String,
        thumbnailPath: String,
        createdAt: Date,
        updatedAt: Date,
        schemaVersion: Int = Stamp.currentSchemaVersion,
        systemFields: Data? = nil,
        needsUpload: Bool,
        photoNeedsUpload: Bool,
        pendingDeletion: Bool = false
    ) {
        self.date = date
        self.note = note
        self.photoPath = photoPath
        self.thumbnailPath = thumbnailPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
        self.systemFields = systemFields
        self.needsUpload = needsUpload
        self.photoNeedsUpload = photoNeedsUpload
        self.pendingDeletion = pendingDeletion
    }
}
