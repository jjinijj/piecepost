import SwiftUI
import SwiftData

/// 동기화 시험 화면. 우표 목록·만들기·기록 수정·삭제.
/// 쓰기는 `StampStore`로만 하고, 목록은 같은 로컬 저장소를 `@Query`로 읽는다. CloudKit은 부르지 않는다.
struct SyncSpikeView: View {
    let store: StampStore

    @Query(
        filter: #Predicate<Stamp> { !$0.pendingDeletion },
        sort: \Stamp.date,
        order: .reverse
    )
    private var stamps: [Stamp]

    @State private var isCreating = false
    @State private var editingStamp: Stamp?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // PR 5(동기화 엔진)에서 실제 상태로 바꾼다.
                    LabeledContent("동기화", value: "연결 전")
                }

                Section("우표 \(stamps.count)장") {
                    ForEach(stamps) { stamp in
                        Button {
                            editingStamp = stamp
                        } label: {
                            StampRow(stamp: stamp, thumbnailURL: store.fileURL(for: stamp.thumbnailPath))
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete(perform: delete)
                }
            }
            .overlay {
                if stamps.isEmpty {
                    ContentUnavailableView("우표 없음", systemImage: "envelope", description: Text("+ 버튼으로 만들어 보세요."))
                }
            }
            .navigationTitle("동기화 시험")
            .toolbar {
                Button("만들기", systemImage: "plus") {
                    isCreating = true
                }
            }
            .sheet(isPresented: $isCreating) {
                CreateStampSheet(store: store)
            }
            .sheet(item: $editingStamp) { stamp in
                EditNoteSheet(store: store, stamp: stamp)
            }
            .alert("삭제하지 못했어요", isPresented: isShowingError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// 시험 화면이라 확인 창 없이 바로 지운다.
    private func delete(at offsets: IndexSet) {
        let dates = offsets.map { stamps[$0].date }
        do {
            for date in dates {
                try store.delete(date: date)
            }
        } catch {
            errorMessage = "다시 시도해 주세요."
        }
    }
}

private struct StampRow: View {
    let stamp: Stamp
    let thumbnailURL: URL

    var body: some View {
        HStack(spacing: 12) {
            StampThumbnail(url: thumbnailURL)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(stamp.date)
                        .font(.headline)
                        .monospacedDigit()
                    if stamp.needsUpload {
                        Text("업로드 대기")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if !stamp.note.isEmpty {
                    Text(stamp.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Stamp.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
    SyncSpikeView(store: StampStore(context: container.mainContext))
        .modelContainer(container)
}
