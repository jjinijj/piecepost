import SwiftUI

/// 기록 수정. 날짜와 사진은 바꾸지 않는다("자르기"·"사진 바꾸기" 처리는 미결정).
struct EditNoteSheet: View {
    let store: StampStore
    let stamp: Stamp

    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var errorMessage: String?

    init(store: StampStore, stamp: Stamp) {
        self.store = store
        self.stamp = stamp
        _note = State(initialValue: stamp.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("날짜", value: stamp.date)
                    StampThumbnail(url: store.fileURL(for: stamp.thumbnailPath), side: 120)
                        .frame(maxWidth: .infinity)
                }
                Section("기록") {
                    NoteField(note: $note)
                }
            }
            .navigationTitle("기록 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                }
            }
            .alert("저장하지 못했어요", isPresented: isShowingError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func save() {
        do {
            try store.updateNote(date: stamp.date, note: note)
            dismiss()
        } catch {
            errorMessage = "다시 시도해 주세요."
        }
    }
}
