import CloudKit

/// 서버에서 존 `Stamps`가 지워졌다는 알림(`fetchedDatabaseChanges`의 deletions)을 받았을 때 할 일.
/// 기획서 settings-erase-records 결정 5: 앱은 존을 지우지 않는다. iOS 설정 > iCloud 저장 공간에서 앱 데이터를 지운 경우(`purged`)
/// 등을 위해 남긴다. `deleted`·`purged` 면 이 기기도 지운다.
enum ZoneDeletionAction: Equatable {
    /// `deleted`·`purged`. 로컬 우표·사진을 모두 지운다(업로드 대기 포함, 삭제 우선)
    case eraseLocal
    /// `encryptedDataReset`과 그 밖의 이유. 로그만 남기고 로컬은 유지한다
    case keepLocal
    /// 계정 변경으로 동기화를 멈춘 상태. 받은 변경을 반영하지 않는 규칙대로 아무것도 하지 않는다
    case ignoreWhilePaused

    static func action(for reason: CKDatabase.DatabaseChange.Deletion.Reason, isPaused: Bool) -> ZoneDeletionAction {
        guard !isPaused else { return .ignoreWhilePaused }
        switch reason {
        case .deleted, .purged: return .eraseLocal
        case .encryptedDataReset: return .keepLocal
        @unknown default: return .keepLocal
        }
    }
}
