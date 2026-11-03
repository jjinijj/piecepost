import SwiftUI

/// S04 설정 화면 골격. iCloud 백업 상태, 약관 링크 자리, 앱 버전.
/// 동기화 상태는 `SyncMonitor`만 읽는다. CloudKit은 부르지 않는다(불변 규칙 4).
struct SettingsView: View {
    let monitor: SyncMonitor

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("iCloud 백업") {
                    SyncStatusRow(text: SyncStatusText(monitor.status))
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
                }
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
