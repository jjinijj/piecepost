/// 전부 지우는 동안(`EraseFence` hold) 받은 레코드 **수정**의 이름(기획서 settings-erase-records 결정 4·8, 왕복 2).
///
/// 지우는 동안 받은 변경은 반영하지 않고 다시 받기 목록에 넣는다. 지우기가 성공하면 그 목록을 비우는데,
/// 엔진의 변경 토큰은 이미 그 가져오기를 지나갔으므로 같이 섞인 다른 기기의 정상 수정(목록을 얻은 뒤 올라온 우표 등)을
/// 영영 받지 못하게 된다. 그래서 수정 이름만 따로 남겨 두었다가, 성공해 로컬을 지운 뒤 다시 받기 목록에 다시 넣는다.
/// 삭제(이 기기가 한 삭제 포함)는 남기지 않는다. 지우기가 실패하면 다시 받기 목록에 이미 모두 있으므로 따로 할 일이 없다.
struct HeldFetchedModifications: Equatable {
    private(set) var names: [String] = []

    /// 받은 수정의 레코드 이름. 같은 이름은 한 번만 남긴다.
    mutating func hold(modified: [String]) {
        for name in modified where !names.contains(name) {
            names.append(name)
        }
    }

    /// 지우기가 끝났다. 남긴 이름을 비운다.
    /// - Parameter erased: 서버 레코드를 다 지웠는지
    /// - Returns: 로컬을 지운 뒤 다시 받을 이름. 실패면 빈 배열(다시 받기 목록에 이미 있음)
    mutating func release(erased: Bool) -> [String] {
        defer { names.removeAll() }
        return erased ? names : []
    }
}
