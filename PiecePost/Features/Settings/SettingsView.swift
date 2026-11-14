import SwiftData
import SwiftUI

/// S04 설정 화면. iCloud 백업 상태, 기록 전부 지우기, 약관 링크 자리, 앱 버전.
/// 동기화 상태는 `SyncMonitor`만, 우표 수는 로컬 저장소만 읽는다. CloudKit은 부르지 않고
/// 지우기는 `eraseAll`(Sync/의 엔진)에 맡긴다(불변 규칙 4).
struct SettingsView: View {
    let monitor: SyncMonitor
    /// iCloud의 우표 레코드를 전부 지우고 성공하면 로컬을 지운다
    let eraseAll: () async -> EraseAllResult

    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Stamp> { !$0.pendingDeletion })
    private var visibleStamps: [Stamp]

    @State private var isConfirmingFirst = false
    @State private var isConfirmingSecond = false
    @State private var isErasing = false
    @State private var isShowingEraseFailure = false
    @State private var isShowingPartialErase = false
    /// 첫 확인 창을 띄울 때 센 우표 수. 확인 창이 떠 있는 동안 받은 변경으로 문구가 바뀌지 않게 한다.
    @State private var confirmingCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section("iCloud 백업") {
                    SyncStatusRow(text: SyncStatusText(monitor.status))
                }

                Section("데이터") {
                    eraseAllRow
                }

                Section("정보") {
                    ForEach(LegalLinks.visibleItems) { item in
                        // 정적 웹 페이지라 Safari로 연다.
                        Link(destination: item.url) {
                            HStack {
                                Text(item.title)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    LabeledContent("버전", value: AppVersion.current)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                    // 지우는 중에 닫으면 실패 안내를 볼 수 없다.
                    .disabled(isErasing)
                }
            }
            .interactiveDismissDisabled(isErasing)
            .alert("기록을 전부 지울까요?", isPresented: $isConfirmingFirst) {
                Button("취소", role: .cancel) {}
                Button("계속") {
                    isConfirmingSecond = true
                }
            } message: {
                Text("우표 \(confirmingCount)장과 사진이 이 기기와 iCloud, 같은 iCloud를 쓰는 다른 기기에서 모두 지워져요. 다른 기기에서 아직 올리지 않은 기록은 남을 수 있어요.")
            }
            .alert("정말 지울까요?", isPresented: $isConfirmingSecond) {
                Button("취소", role: .cancel) {}
                Button("전부 지우기", role: .destructive) {
                    erase()
                }
            } message: {
                Text("지운 기록은 되돌릴 수 없어요.")
            }
            .alert("지우지 못했어요.", isPresented: $isShowingEraseFailure) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("인터넷 연결을 확인하고 다시 해 주세요.")
            }
            .alert("iCloud에서 일부만 지웠어요.", isPresented: $isShowingPartialErase) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("인터넷 연결을 확인하고 다시 해 주세요.")
            }
        }
    }

    @ViewBuilder
    private var eraseAllRow: some View {
        if isErasing {
            HStack(spacing: 8) {
                ProgressView()
                Text("지우는 중")
                    .foregroundStyle(.secondary)
            }
        } else {
            let availability = EraseAllAvailability(
                status: monitor.status,
                visibleStampCount: visibleStamps.count
            )
            // destructive 역할이라 빨간 글자로 보이고, 비활성이면 흐려진다.
            Button("기록 전부 지우기", role: .destructive) {
                confirmingCount = visibleStamps.count
                isConfirmingFirst = true
            }
            .disabled(!availability.isEnabled)
            if let reason = availability.reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("eraseAllDisabledReason")
            }
        }
    }

    private func erase() {
        guard !isErasing else { return }
        isErasing = true
        Task {
            let result = await eraseAll()
            isErasing = false
            switch result {
            case .erased:
                // 시험 화면(빈 목록)으로 돌아간다.
                dismiss()
            case .partial:
                isShowingPartialErase = true
            case .failed:
                isShowingEraseFailure = true
            }
        }
    }
}

private struct SyncStatusRow: View {
    let text: SyncStatusText

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: text.systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(text.title)
                    .accessibilityIdentifier("syncStatusTitle")
                if let detail = text.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
