/// 기록 전부 지우기와 겹친 보내기·받기 결과를 반영해도 되는지 가른다.
///
/// 지우는 동안 온 결과는 반영하지 않고(실패하면 다시 받기·업로드 대기로 복구), 성공한 지우기보다 먼저 시작한
/// 작업의 결과는 버린다. 그대로 반영하면 지운 우표가 다시 들어오거나 지운 존을 다시 만들 수 있다.
/// 작업을 시작할 때 `token`을 받아 두었다가 결과가 오면 `gate(startedAt:)`로 묻는다.
struct EraseFence: Equatable {
    enum Gate: Equatable {
        /// 평소대로 반영한다
        case apply
        /// 지우는 중. 반영하지 않고, 지우기가 실패하면 복구할 수 있게 남겨 둔다
        case hold
        /// 성공한 지우기보다 먼저 시작한 작업. 지운 데이터의 결과이므로 버린다
        case drop
    }

    private(set) var isErasing = false
    private var epoch = 0
    /// 마지막으로 성공한 지우기가 끝난 시점. 없으면 nil
    private var erasedAt: Int?

    /// 작업을 시작할 때 받아 둘 값.
    var token: Int { epoch }

    mutating func begin() {
        isErasing = true
        epoch += 1
    }

    mutating func end(erased: Bool) {
        isErasing = false
        epoch += 1
        if erased { erasedAt = epoch }
    }

    func gate(startedAt: Int) -> Gate {
        if isErasing { return .hold }
        if let erasedAt, startedAt < erasedAt { return .drop }
        return .apply
    }
}
