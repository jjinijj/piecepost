/// 기록 전부 지우기 결과. 화면은 이 값으로 알림을 고른다(기획서 settings-erase-records 결정 3).
enum EraseAllResult: Equatable, Sendable {
    /// 서버와 이 기기에서 다 지웠다. 시트를 닫는다
    case erased
    /// 서버에서 일부만 지웠다. 이 기기는 지우지 않았다. "iCloud에서 일부만 지웠어요."
    case partial
    /// 하나도 못 지웠거나 시도하지 못했다. "지우지 못했어요."
    case failed
}
