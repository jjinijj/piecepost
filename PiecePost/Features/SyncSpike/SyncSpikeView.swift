import SwiftUI
import SwiftData

/// 동기화 시험 화면. 1단계에서는 로컬 우표 목록만 보여준다(만들기·수정·삭제는 3단계).
struct SyncSpikeView: View {
    @Query(
        filter: #Predicate<Stamp> { !$0.pendingDeletion },
        sort: \Stamp.date,
        order: .reverse
    )
    private var stamps: [Stamp]

    var body: some View {
        NavigationStack {
            List(stamps) { stamp in
                VStack(alignment: .leading, spacing: 4) {
                    Text(stamp.date)
                        .font(.headline)
                    if !stamp.note.isEmpty {
                        Text(stamp.note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if stamps.isEmpty {
                    ContentUnavailableView("우표 없음", systemImage: "envelope")
                }
            }
            .navigationTitle("동기화 시험")
        }
    }
}

#Preview {
    SyncSpikeView()
        .modelContainer(for: Stamp.self, inMemory: true)
}
