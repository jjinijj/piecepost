//
//  PiecePostApp.swift
//  PiecePost
//
//  Created by JinHyoung Kim on 10/31/26.
//

import SwiftUI
import SwiftData

@main
struct PiecePostApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let modelContainer: ModelContainer
    let stampStore: StampStore
    let syncMonitor: SyncMonitor
    let syncEngine: StampSyncEngine?

    init() {
        let container = Self.makeModelContainer()
        let fileStore = StampFileStore()
        let monitor = SyncMonitor()
        // 테스트 중에는 CloudKit 개발 DB에 쓰지 않도록 엔진을 만들지 않는다.
        let engine: StampSyncEngine? = Self.isSyncDisabled ? nil : StampSyncEngine(
            applier: SyncChangeApplier(context: container.mainContext, fileStore: fileStore),
            monitor: monitor
        )

        modelContainer = container
        syncMonitor = monitor
        syncEngine = engine
        stampStore = StampStore(context: container.mainContext, fileStore: fileStore) { date in
            engine?.localStampChanged(date: date)
        }
        engine?.start()
    }

    var body: some Scene {
        WindowGroup {
            SyncSpikeView(store: stampStore)
        }
        .modelContainer(modelContainer)
    }

    /// 단위 테스트(앱 안에서 실행) 또는 UI 테스트(실행 인자로 알림) 중이면 true.
    private static var isSyncDisabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("-PiecePostDisableSync")
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([Stamp.self])
        // iCloud 권한이 있어도 SwiftData가 CloudKit 자동 동기화를 켜지 않게 반드시 끈다.
        // 동기화는 Sync/의 CKSyncEngine만 담당한다.
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("ModelContainer 생성 실패: \(error)")
        }
    }
}
