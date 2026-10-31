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
    let modelContainer: ModelContainer = {
        let schema = Schema([Stamp.self])
        // iCloud 권한이 있어도 SwiftData가 CloudKit 자동 동기화를 켜지 않게 반드시 끈다.
        // 동기화는 Sync/의 CKSyncEngine만 담당한다.
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("ModelContainer 생성 실패: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            SyncSpikeView()
        }
        .modelContainer(modelContainer)
    }
}
