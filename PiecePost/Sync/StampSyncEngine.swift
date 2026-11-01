import CloudKit
import Foundation
import SwiftData

/// CKSyncEngine과 로컬 저장소를 잇는다. CloudKit 접근은 이 파일과 Sync/ 안에서만 한다(불변 규칙 4).
///
/// 엔진 콜백은 백그라운드에서 오지만, 로컬 저장소는 화면과 같은 메인 스레드에서만 다룬다.
/// 그래서 콜백을 받으면 메인 스레드로 넘겨 `SyncChangeApplier`의 규칙을 부른다.
final class StampSyncEngine {
    static let containerIdentifier = "iCloud.com.sisjin.PiecePost"

    private let applier: SyncChangeApplier
    private let stateStore: SyncStateStore
    private let monitor: SyncMonitor
    private var engine: CKSyncEngine?

    /// 보낸 레코드의 결과를 받을 때 필요한 값. 결과 콜백에는 "보낼 때" 값이 없으므로 여기 기억해 둔다.
    private struct SentInfo {
        let updatedAt: Date
        let baseSystemFields: Data?
    }
    private var sentInfo: [CKRecord.ID: SentInfo] = [:]

    init(applier: SyncChangeApplier, stateStore: SyncStateStore = SyncStateStore(), monitor: SyncMonitor) {
        self.applier = applier
        self.stateStore = stateStore
        self.monitor = monitor
    }

    private var log: SyncLog { monitor.log }

    // MARK: 시작

    func start() {
        guard engine == nil else { return }

        let savedState: CKSyncEngine.State.Serialization?
        do {
            savedState = try stateStore.load(CKSyncEngine.State.Serialization.self)
        } catch {
            log.add("엔진 상태 파일 손상, 처음부터 시작")
            stateStore.clear()
            savedState = nil
        }
        log.add(savedState == nil ? "엔진 상태 없음, 처음부터 가져옴" : "엔진 상태 복원됨")

        let database = CKContainer(identifier: Self.containerIdentifier).privateCloudDatabase
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: savedState,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        if savedState == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: StampRecordMapper.zoneID))])
        }
        // needsUpload 기준으로 다시 넣는다. 엔진 상태를 잃었어도 보내지 못한 변경이 복구된다.
        do {
            let pending = try applier.pendingChanges()
            for change in pending {
                enqueue(change, in: engine)
            }
            log.add("시작 시 보낼 변경 \(pending.count)건")
        } catch {
            log.add("보낼 변경 읽기 실패: \(Self.describe(error))")
        }
    }

    /// 시뮬레이터처럼 푸시를 잘 받지 못하는 환경을 위한 수동 가져오기.
    func fetchNow() async {
        guard let engine else { return }
        log.add("지금 가져오기 요청")
        do {
            try await engine.fetchChanges()
        } catch {
            log.add("가져오기 실패: \(Self.describe(error))")
        }
    }

    // MARK: 로컬 변경

    /// `StampStore.onLocalChange`에서 부른다.
    func localStampChanged(date: String) {
        guard let engine else { return }
        do {
            enqueue(try applier.pendingChange(for: date), in: engine)
        } catch {
            log.add("로컬 변경 예약 실패: \(Self.describe(error))")
        }
    }

    private func enqueue(_ change: PendingStampChange, in engine: CKSyncEngine) {
        switch change {
        case .save(let date):
            let id = StampRecordMapper.recordID(for: date)
            // 같은 날짜의 삭제 예약을 빼서 순서가 꼬이지 않게 한다.
            engine.state.remove(pendingRecordZoneChanges: [.deleteRecord(id)])
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        case .delete(let date):
            let id = StampRecordMapper.recordID(for: date)
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
        }
    }

    // MARK: 보내기

    fileprivate func recordToSave(_ recordID: CKRecord.ID, engine: CKSyncEngine) -> CKRecord? {
        guard
            let date = StampRecordMapper.date(from: recordID),
            let values = try? applier.uploadValues(for: date)
        else {
            // 행이 없거나 삭제 대기면 보낼 것이 없다.
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
        let record = StampRecordMapper.record(from: values)
        sentInfo[recordID] = SentInfo(updatedAt: values.updatedAt, baseSystemFields: values.systemFields)
        log.add("보낼 레코드 changedKeys=\(record.changedKeys().sorted())")
        return record
    }

    // MARK: 이벤트

    fileprivate func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let update):
            do {
                try stateStore.save(update.stateSerialization)
            } catch {
                log.add("엔진 상태 저장 실패: \(Self.describe(error))")
            }

        case .accountChange(let change):
            handleAccountChange(change, engine: engine)

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == StampRecordMapper.zoneID {
                // 합의: 로그만 남기고 로컬은 유지한다.
                log.add("서버에서 존 삭제됨 reason=\(deletion.reason), 로컬 유지")
            }

        case .fetchedRecordZoneChanges(let changes):
            applyFetched(changes)

        case .sentDatabaseChanges(let sent):
            if !sent.savedZones.isEmpty {
                log.add("존 저장됨 \(sent.savedZones.count)개")
            }
            for failure in sent.failedZoneSaves {
                log.add("존 저장 실패: \(Self.describe(failure.error))")
            }

        case .sentRecordZoneChanges(let sent):
            applySent(sent, engine: engine)

        case .willFetchChanges:
            monitor.status = .syncing
            log.add("가져오기 시작")
        case .didFetchChanges:
            if monitor.status == .syncing { monitor.status = .idle }
            log.add("가져오기 끝")
        case .willSendChanges:
            monitor.status = .syncing
        case .didSendChanges:
            if monitor.status == .syncing { monitor.status = .idle }

        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            log.add("알 수 없는 엔진 이벤트")
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange, engine: CKSyncEngine) {
        // 계정 상태 처리는 다음 PR(계정 상태)에서 정리한다. 지금은 로그와 상태 표시만.
        switch change.changeType {
        case .signIn:
            log.add("계정 이벤트: 로그인")
            monitor.status = .idle
            if let pending = try? applier.pendingChanges() {
                for item in pending { enqueue(item, in: engine) }
            }
        case .signOut:
            log.add("계정 이벤트: 로그아웃")
            monitor.status = .iCloudUnavailable
        case .switchAccounts:
            log.add("계정 이벤트: 계정 전환")
            monitor.status = .iCloudUnavailable
        @unknown default:
            log.add("계정 이벤트: 알 수 없음")
        }
    }

    // MARK: 받은 변경

    private func applyFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        var inserted = 0, updated = 0, skippedPending = 0, skippedDeletion = 0, deleted = 0, failed = 0

        for modification in changes.modifications {
            let record = modification.record
            guard record.recordID.zoneID == StampRecordMapper.zoneID else { continue }
            do {
                let received = try StampRecordMapper.receivedStamp(from: record)
                if received.schemaVersion > Stamp.currentSchemaVersion {
                    log.add("더 높은 schemaVersion=\(received.schemaVersion) 받음, 아는 필드만 반영")
                }
                // 사진 임시 파일은 이 콜백 안에서만 유효하므로 여기서 바로 복사한다.
                switch try applier.applyReceived(received) {
                case .inserted: inserted += 1
                case .updated: updated += 1
                case .skippedLocalPending: skippedPending += 1
                case .skippedPendingDeletion: skippedDeletion += 1
                }
            } catch {
                failed += 1
                log.add("받은 레코드 건너뜀: \(Self.describe(error))")
            }
        }

        for deletion in changes.deletions where deletion.recordType == StampRecordMapper.recordType {
            guard let date = StampRecordMapper.date(from: deletion.recordID) else { continue }
            do {
                if try applier.applyServerDeletion(date: date) { deleted += 1 }
            } catch {
                failed += 1
                log.add("받은 삭제 반영 실패: \(Self.describe(error))")
            }
        }

        log.add(
            "받음: 추가 \(inserted), 갱신 \(updated), 삭제 \(deleted), "
                + "건너뜀(로컬 대기 \(skippedPending), 삭제 대기 \(skippedDeletion)), 실패 \(failed)"
        )
    }

    // MARK: 보낸 결과

    private func applySent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
        var saved = 0, ignored = 0
        for record in sent.savedRecords {
            let id = record.recordID
            guard let date = StampRecordMapper.date(from: id) else { continue }
            guard let info = sentInfo.removeValue(forKey: id) else {
                log.add("보낸 정보 없는 저장 결과, 반영 안 함")
                continue
            }
            do {
                let applied = try applier.markSaved(
                    date: date,
                    systemFields: StampRecordMapper.encodeSystemFields(of: record),
                    sentUpdatedAt: info.updatedAt,
                    sentBaseSystemFields: info.baseSystemFields
                )
                if applied { saved += 1 } else { ignored += 1 }
            } catch {
                log.add("저장 결과 반영 실패: \(Self.describe(error))")
            }
        }

        for id in sent.deletedRecordIDs {
            guard let date = StampRecordMapper.date(from: id) else { continue }
            do {
                try applier.markDeleted(date: date)
            } catch {
                log.add("삭제 결과 반영 실패: \(Self.describe(error))")
            }
        }

        for failure in sent.failedRecordSaves {
            let id = failure.record.recordID
            sentInfo.removeValue(forKey: id)
            handleFailedSave(id: id, error: failure.error, engine: engine)
        }

        for (_, error) in sent.failedRecordDeletes {
            // 처리 방식이 정해지지 않은 경우라 로그만 남긴다.
            log.add("삭제 실패: \(Self.describe(error))")
        }

        log.add(
            "보냄: 저장 \(saved), 옛 결과 무시 \(ignored), 삭제 \(sent.deletedRecordIDs.count), "
                + "실패 \(sent.failedRecordSaves.count + sent.failedRecordDeletes.count)"
        )
    }

    private func handleFailedSave(id: CKRecord.ID, error: CKError, engine: CKSyncEngine) {
        switch error.code {
        case .zoneNotFound:
            // 존을 만들고 다시 보낸다.
            log.add("저장 실패 zoneNotFound: 존 만들고 다시 보냄")
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: StampRecordMapper.zoneID))])
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])

        case .unknownItem:
            // 올렸는데 서버에 이미 없음 → 삭제 우선.
            log.add("저장 실패 unknownItem: 로컬도 삭제")
            if let date = StampRecordMapper.date(from: id) {
                _ = try? applier.applyServerDeletion(date: date)
            }

        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited:
            // needsUpload를 유지하고 재시도는 엔진에 맡긴다.
            log.add("저장 실패(재시도 대기): \(Self.describe(error))")

        case .serverRecordChanged:
            // 충돌 처리 PR에서 처리한다. needsUpload가 남아 있어 다음 실행 때 다시 시도된다.
            log.add("저장 실패 serverRecordChanged: 충돌 처리 미구현, 로그만")

        case .quotaExceeded:
            monitor.status = .quotaExceeded
            log.add("저장 실패 quotaExceeded: 로컬 유지")

        case .notAuthenticated:
            monitor.status = .iCloudUnavailable
            log.add("저장 실패 notAuthenticated: 로컬에만 저장")

        default:
            // 판단 분기에 없는 코드. 처리 방식은 정하지 않고 보고한다.
            monitor.status = .error(code: error.code.rawValue)
            log.add("저장 실패(처리 방식 미정): \(Self.describe(error))")
        }
    }

    // MARK: 로그용

    /// 오류 종류와 코드만 남긴다. 레코드 내용은 남기지 않는다.
    static func describe(_ error: any Error) -> String {
        if let ckError = error as? CKError {
            return "CKError \(ckError.code.rawValue)"
        }
        if let recordError = error as? StampRecordError {
            return "\(recordError)"
        }
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}

// MARK: - CKSyncEngineDelegate

extension StampSyncEngine: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event, engine: syncEngine)
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.recordToSave(recordID, engine: syncEngine)
        }
    }
}
