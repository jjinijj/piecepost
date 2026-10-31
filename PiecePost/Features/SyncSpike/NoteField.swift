import SwiftUI

/// 기록 입력 칸. 입력 중에 줄바꿈을 공백으로 바꾸고 50자를 넘지 않게 막는다.
struct NoteField: View {
    @Binding var note: String

    var body: some View {
        HStack {
            TextField("기록 (선택)", text: $note)
                .onChange(of: note) { _, newValue in
                    let limited = StampNote.limitInput(newValue)
                    if limited != newValue {
                        note = limited
                    }
                }
            Text("\(note.count)/\(StampNote.maxLength)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
