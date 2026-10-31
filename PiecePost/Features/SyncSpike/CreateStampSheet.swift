import PhotosUI
import SwiftUI
import UIKit

/// 우표 만들기: 날짜 + 사진 + 기록.
/// PhotosPicker는 고른 사진만 앱에 넘겨주므로 사진 보관함 권한을 요청하지 않는다.
struct CreateStampSheet: View {
    let store: StampStore

    @Environment(\.dismiss) private var dismiss

    @State private var day = Date.now
    @State private var note = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: ProcessedPhoto?
    @State private var preview: UIImage?
    @State private var processingSummary: String?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // 과거·미래 제한 없음(docs/system-design.md 3.1)
                    DatePicker("날짜", selection: $day, displayedComponents: .date)
                }

                Section("사진") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photo == nil ? "사진 고르기" : "사진 다시 고르기", systemImage: "photo.on.rectangle")
                    }
                    if isProcessing {
                        ProgressView("사진 처리 중…")
                    }
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if let processingSummary {
                        Text(processingSummary)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Section("기록") {
                    NoteField(note: $note)
                }
            }
            .navigationTitle("우표 만들기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .disabled(photo == nil || isProcessing)
                }
            }
            .task(id: pickerItem) {
                await processPickedPhoto()
            }
            .alert("알림", isPresented: isShowingError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func processPickedPhoto() async {
        guard let pickerItem else { return }
        photo = nil
        preview = nil
        processingSummary = nil
        isProcessing = true
        defer { isProcessing = false }

        do {
            guard let original = try await pickerItem.loadTransferable(type: Data.self) else {
                errorMessage = "사진을 불러오지 못했어요."
                return
            }
            let clock = ContinuousClock()
            let start = clock.now
            let result = try await PhotoProcessor.process(original)
            let elapsed = clock.now - start
            // 처리 중에 다른 사진을 고르면 이전 결과는 버린다.
            try Task.checkCancellation()

            let image = UIImage(data: result.photo)
            photo = result
            preview = image
            processingSummary = Self.summary(
                elapsed: elapsed,
                originalBytes: original.count,
                result: result,
                pixelWidth: image.map { Int($0.size.width * $0.scale) }
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "사진을 처리하지 못했어요."
        }
    }

    private func save() {
        guard let photo else { return }
        do {
            try store.create(date: StampDate.string(from: day), note: note, photo: photo)
            dismiss()
        } catch StampStoreError.alreadyExists {
            errorMessage = "이미 우표가 있는 날짜예요."
        } catch {
            errorMessage = "저장하지 못했어요. 다시 시도해 주세요."
        }
    }

    /// 실기기 확인용. 처리 시간은 측정값, 용량은 실제 결과 크기.
    private static func summary(
        elapsed: Duration,
        originalBytes: Int,
        result: ProcessedPhoto,
        pixelWidth: Int?
    ) -> String {
        let seconds = String(format: "%.2f초", elapsed / .seconds(1))
        let size = pixelWidth.map { "\($0)×\($0)" } ?? "크기 알 수 없음"
        return "처리 \(seconds) · 원본 \(bytes(originalBytes)) → 사진 \(size) \(bytes(result.photo.count)) · 썸네일 \(bytes(result.thumbnail.count))"
    }

    private static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
