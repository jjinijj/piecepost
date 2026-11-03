/// 설정 화면 "iCloud 백업" 구역에 보여 줄 동기화 상태 문구.
/// 화면 밖에서 `SyncStatus`만 보고 만들어 단위 테스트로 확인한다(기획서 settings-skeleton 완료 기준 4).
/// 시험 화면용 `SyncStatus.label`과는 따로 둔다.
struct SyncStatusText: Equatable {
    let title: String
    /// 설명이 없는 상태는 nil. 화면에서 줄을 그리지 않는다.
    let detail: String?
    /// SF Symbols 이름
    let systemImage: String

    init(title: String, detail: String? = nil, systemImage: String) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }

    init(_ status: SyncStatus) {
        switch status {
        case .idle:
            self.init(title: "iCloud에 백업됨", systemImage: "checkmark.icloud")
        case .syncing:
            self.init(title: "백업하는 중", systemImage: "arrow.triangle.2.circlepath.icloud")
        case .notStarted:
            self.init(title: "확인하는 중", systemImage: "icloud")
        case .iCloudUnavailable:
            self.init(
                title: "iCloud 꺼짐",
                detail: "기기에만 저장돼요. iCloud에 로그인하면 백업돼요.",
                systemImage: "xmark.icloud"
            )
        case .iCloudTemporarilyUnavailable:
            self.init(
                title: "iCloud 일시 사용 불가",
                detail: "기기에 저장해 두고 잠시 뒤 다시 백업해요.",
                systemImage: "exclamationmark.icloud"
            )
        case .accountChanged:
            self.init(
                title: "계정 변경됨",
                detail: "처음 백업한 iCloud 계정이 아니라 백업을 멈췄어요. 원래 계정으로 돌아오면 이어서 해요.",
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
        case .quotaExceeded:
            self.init(
                title: "iCloud 용량 부족",
                detail: "기기에는 저장돼 있어요. iCloud 공간을 확보하면 다시 백업해요.",
                systemImage: "exclamationmark.icloud"
            )
        case .error(let code):
            self.init(title: "백업 오류", detail: "오류 코드 \(code)", systemImage: "exclamationmark.triangle")
        }
    }
}
