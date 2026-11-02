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
    private let retryList: ReceiveRetryList
    private let accountStore: SyncAccountStore
    private var engine: CKSyncEngine?
    private var container: CKContainer?
    private var database: CKDatabase?
    private var isRetryingReceives = false
    /// 다시 받기가 도는 중에 새로 요청됐는지. 끝난 뒤 한 번 더 돌린다(그사이 목록에 들어온 것이 다음 계기까지 묻히지 않게).
    private var receiveRetryRequestedWhileRunning = false

    /// 보낸 레코드의 결과를 받을 때 필요한 값. 결과 콜백에는 "보낼 때" 값이 없으므로 여기 기억해 둔다.
    private struct SentInfo {
        let updatedAt: Date
        let baseSystemFields: Data?
    }
    private var sentInfo: [CKRecord.ID: SentInfo] = [:]

    /// 보낼 값을 읽다 오류가 나서 이번 보내기에서 뺀 레코드. 보내기가 끝나면 다시 예약한다.
    private var deferredSaves: Set<CKRecord.ID> = []

    /// 보내기 진행 중 여부. "지금 보내기"가 진행 중인 보내기와 겹쳐 `sentInfo`를 덮어쓰지 않게 한다.
    private var sendProgress = SendProgress()

    /// 화면에 보낼 동기화 상태의 재료. 바뀔 때마다 `monitor.status`를 다시 정한다.
    private var statusState = SyncStatusState() {
        didSet { monitor.status = statusState.status }
    }

    /// 포그라운드 진입 한 번에 진입 처리를 한 번만 하게 한다.
    private var foregroundGate = ForegroundEntryGate()

    /// 첫 동기화가 끝나면 기억할 계정 지문(`SyncAccountEvaluation.fingerprintToStoreAfterSync`).
    private var accountToRememberAfterSync: String?

    init(
        applier: SyncChangeApplier,
        stateStore: SyncStateStore = SyncStateStore(),
        retryList: ReceiveRetryList = ReceiveRetryList(),
        accountStore: SyncAccountStore = SyncAccountStore(),
        monitor: SyncMonitor
    ) {
        self.applier = applier
        self.stateStore = stateStore
        self.retryList = retryList
        self.accountStore = accountStore
        self.monitor = monitor
    }

    private var log: SyncLog { monitor.log }

    /// 기억한 계정과 다른 Apple ID라 동기화를 멈췄는지. 멈춘 동안 보내지도, 받은 변경을 반영하지도 않는다.
    private var isPaused: Bool { statusState.isPausedForAccountChange }

    // MARK: 시작

    /// 계정을 먼저 확인하고 엔진을 만든다. 다른 계정이면 엔진이 받은 변경을 반영하거나 보내기 전에 멈춰 있어야 한다.
    func start() {
        guard container == nil else { return }
        let container = CKContainer(identifier: Self.containerIdentifier)
        self.container = container
        Task {
            await checkAccount(container)
            startEngine(container)
        }
    }

    private func startEngine(_ container: CKContainer) {
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

        let database = container.privateCloudDatabase
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: savedState,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        self.database = database
        statusState.isStarted = true

        if isPaused {
            // 다른 계정에 존을 만들거나 우표를 예약하지 않는다. 원래 계정으로 돌아오면 다시 넣는다.
            log.add("계정 변경됨, 보낼 변경 예약 안 함")
        } else {
            if savedState == nil {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: StampRecordMapper.zoneID))])
            }
            // needsUpload 기준으로 다시 넣는다. 엔진 상태를 잃었어도 보내지 못한 변경이 복구된다.
            enqueueAllPending(in: engine, logPrefix: "시작 시 보낼 변경")
        }
        logPendingSummary(engine)
        Task { await retryFailedReceives() }
    }

    /// 업로드 대기 우표를 모두 엔진에 넣고 개수를 남긴다. 읽기에 실패하면 엔진에 이미 있는 예약은 그대로 둔다.
    private func enqueueAllPending(in engine: CKSyncEngine, logPrefix: String) {
        do {
            let pending = try applier.pendingChanges()
            for change in pending {
                enqueue(change, in: engine)
            }
            log.add("\(logPrefix) \(pending.count)건")
        } catch {
            log.add("보낼 변경 읽기 실패: \(Self.describe(error))")
        }
    }

    // MARK: 계정

    /// 계정 상태를 확인해 상태를 정한다. 앱 시작과 포그라운드 진입 때 부른다.
    /// 로그에는 상태 이름만 남기고 계정 식별자·지문은 남기지 않는다(불변 규칙 8).
    private func checkAccount(_ container: CKContainer) async {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            log.add("iCloud 계정 조회 실패: \(Self.describe(error))")
            return
        }
        log.add(SyncDiagnostics.accountStatusLine(status))
        let condition = SyncAccountRules.condition(for: status)
        guard condition == .available else {
            setAccount(condition)
            return
        }
        do {
            let userID = try await container.userRecordID()
            applyIdentity(currentUser: userID, previousUser: nil)
        } catch {
            // 계정을 비교하지 못했다. 멈춤 여부는 그대로 두고, 바뀐 계정은 엔진이 알려 주는 전환으로 잡는다.
            log.add("iCloud 사용자 확인 실패, 계정 비교 건너뜀: \(Self.describe(error))")
            setAccount(.available)
        }
    }

    /// 지금 계정을 마지막으로 동기화한 계정과 비교해 멈추거나 재개한다.
    private func applyIdentity(currentUser: CKRecord.ID, previousUser: CKRecord.ID?) {
        let evaluation = SyncAccountRules.evaluate(
            current: SyncAccountRules.fingerprint(ofUserRecordName: currentUser.recordName),
            stored: accountStore.load(),
            previous: previousUser.map { SyncAccountRules.fingerprint(ofUserRecordName: $0.recordName) },
            engineHasHistory: engine != nil || hasSavedEngineState
        )
        if let fingerprint = evaluation.fingerprintToStore {
            rememberAccount(fingerprint)
        }
        accountToRememberAfterSync = evaluation.fingerprintToStoreAfterSync
        setPaused(evaluation.isDifferentAccount)
        setAccount(.available)
    }

    private var hasSavedEngineState: Bool {
        FileManager.default.fileExists(atPath: stateStore.fileURL.path(percentEncoded: false))
    }

    private func rememberAccount(_ fingerprint: String) {
        do {
            try accountStore.save(fingerprint)
        } catch {
            log.add("계정 기억 저장 실패: \(Self.describe(error))")
        }
    }

    /// 미뤄 둔 첫 계정 기억. 가져오기·보내기가 끝났는데 엔진이 계정 전환을 알리지 않았으면 지금 계정이 맞다.
    private func rememberAccountAfterSyncIfNeeded() {
        guard let fingerprint = accountToRememberAfterSync, !isPaused else { return }
        accountToRememberAfterSync = nil
        if accountStore.load() == nil {
            rememberAccount(fingerprint)
            log.add("동기화한 계정 기억함")
        }
    }

    private func setAccount(_ condition: SyncAccountCondition) {
        let previous = statusState.account
        statusState.account = condition
        // 꺼짐·일시 사용 불가에서 돌아오면 업로드 대기 우표를 다시 예약한다(엔진이 로그아웃 때 예약을 비웠을 수 있음).
        if condition == .available, previous == .signedOut || previous == .temporarilyUnavailable,
           !isPaused, let engine {
            enqueueAllPending(in: engine, logPrefix: "iCloud 사용 가능, 보낼 변경")
        }
    }

    private func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        statusState.isPausedForAccountChange = paused
        if paused {
            log.add("계정 변경됨, 동기화 멈춤")
            // 새 계정으로 보낼 예약을 비운다. 로컬의 업로드 대기 표시(needsUpload)는 그대로라 재개 때 다시 넣는다.
            if let engine {
                engine.state.remove(pendingRecordZoneChanges: engine.state.pendingRecordZoneChanges)
                engine.state.remove(pendingDatabaseChanges: engine.state.pendingDatabaseChanges)
            }
        } else {
            log.add("원래 계정으로 돌아옴, 동기화 재개")
            if let engine {
                enqueueAllPending(in: engine, logPrefix: "재개 시 보낼 변경")
            }
            Task { await retryFailedReceives() }
        }
    }

    // MARK: 포그라운드

    func appDidEnterBackground() {
        foregroundGate.didEnterBackground()
    }

    /// 화면이 활성이 됐다. 포그라운드 진입 한 번에 한 번만 계정을 다시 확인하고, 용량 부족이면 한 번 다시 보낸다.
    func appDidBecomeActive() {
        guard let container, engine != nil, foregroundGate.shouldHandleActivation() else { return }
        Task {
            await checkAccount(container)
            await retryAfterQuotaExceeded()
        }
    }

    /// "용량 부족" 상태에서 업로드 대기 우표를 한 번 다시 보낸다(설계 문서 5장). 성공하면 보낸 결과에서 상태가 풀린다.
    private func retryAfterQuotaExceeded() async {
        guard statusState.isQuotaExceeded, statusState.account == .available, !isPaused else { return }
        log.add("용량 부족, 포그라운드 진입으로 다시 보냄")
        await send()
    }

    /// 엔진 대기 목록의 개수만 남긴다(레코드 이름은 남기지 않음).
    private func logPendingSummary(_ engine: CKSyncEngine) {
        log.add(SyncDiagnostics.pendingSummary(
            recordZoneChanges: engine.state.pendingRecordZoneChanges,
            databaseChanges: engine.state.pendingDatabaseChanges
        ))
    }

    /// 시뮬레이터처럼 푸시를 잘 받지 못하는 환경을 위한 수동 가져오기.
    func fetchNow() async {
        guard let engine else { return }
        log.add("지금 가져오기 요청")
        guard !isPaused else {
            log.add("계정 변경됨, 가져오기 건너뜀")
            return
        }
        do {
            try await engine.fetchChanges()
        } catch {
            log.add("가져오기 실패: \(Self.describe(error))")
        }
    }

    /// 보내기를 직접 시작한다. 엔진 상태에서 예약이 빠졌어도 로컬에 보낼 것(needsUpload)이 있으면 다시 넣고 보낸다.
    /// 엔진이 없으면(테스트 실행 등) 아무것도 하지 않는다.
    func sendNow() async {
        guard engine != nil else { return }
        log.add("지금 보내기 요청")
        await send()
    }

    /// 업로드 대기 우표를 다시 예약하고 보낸다. "지금 보내기"와 용량 부족 다시 보내기가 쓴다.
    private func send() async {
        guard let engine else { return }
        guard !isPaused else {
            log.add("계정 변경됨, 보내기 건너뜀")
            return
        }
        guard sendProgress.beginManualSend() else {
            // 겹치면 같은 레코드의 보낸 정보가 덮어써진다. 다시 넣기·보내기를 하지 않는다.
            log.add("보내기 진행 중, 건너뜀")
            return
        }
        defer { sendProgress.endManualSend() }
        // 다시 넣지 못해도 엔진에 이미 있는 예약은 보낸다.
        enqueueAllPending(in: engine, logPrefix: "보낼 변경")
        logPendingSummary(engine)
        do {
            // 성공하면 보낸 결과 이벤트에서 "보냄: …" 요약 줄이 남는다.
            try await engine.sendChanges()
        } catch {
            log.add("보내기 실패: \(Self.describe(error))")
        }
    }

    // MARK: 로컬 변경

    /// `StampStore.onLocalChange`에서 부른다.
    func localStampChanged(date: String) {
        guard let engine else { return }
        // 멈춘 동안은 로컬에만 저장하고 업로드 대기(needsUpload)로 남긴다. 재개할 때 다시 넣는다.
        guard !isPaused else { return }
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
        let values: StampUploadValues?
        do {
            values = try StampRecordMapper.date(from: recordID).flatMap(applier.uploadValues(for:))
        } catch {
            // 일시적인 읽기 오류일 수 있으니 예약을 버리지 않는다. 이번 보내기에서만 빼 두었다가
            // 보내기가 끝나면 다시 예약한다(같은 보내기 안에서 곧바로 반복되지 않게).
            log.add("보낼 값 읽기 실패, 다음 보내기에 다시: \(Self.describe(error))")
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            deferredSaves.insert(recordID)
            return nil
        }
        guard let values else {
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
            statusState.isSyncing = true
            statusState.errorCode = nil
            log.add("가져오기 시작")
        case .didFetchChanges:
            statusState.isSyncing = false
            log.add("가져오기 끝")
            rememberAccountAfterSyncIfNeeded()
            Task { await retryFailedReceives() }
        case .willSendChanges(let will):
            statusState.isSyncing = true
            statusState.errorCode = nil
            sendProgress.engineWillSend()
            log.add(SyncDiagnostics.sendStartLine(will.context.reason))
        case .didSendChanges:
            statusState.isSyncing = false
            sendProgress.engineDidSend()
            log.add("보내기 끝")
            rememberAccountAfterSyncIfNeeded()
            if !deferredSaves.isEmpty {
                log.add("읽기 실패로 미룬 저장 \(deferredSaves.count)건 다시 예약")
                engine.state.add(pendingRecordZoneChanges: deferredSaves.map { .saveRecord($0) })
                deferredSaves.removeAll()
            }

        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            log.add("알 수 없는 엔진 이벤트")
        }
    }

    /// 로그아웃 → "iCloud 꺼짐". 로그인·계정 전환 → 기억한 계정과 비교해 같으면 정상(업로드 재개), 다르면 멈춤.
    /// 엔진은 로그아웃·전환 때 자기 예약을 비우므로, 계속 동기화할 때는 업로드 대기 우표를 다시 넣는다.
    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange, engine: CKSyncEngine) {
        switch change.changeType {
        case .signIn(let currentUser):
            log.add("계정 이벤트: 로그인")
            applyIdentity(currentUser: currentUser, previousUser: nil)
            if !isPaused { enqueueAllPending(in: engine, logPrefix: "로그인 후 보낼 변경") }
        case .signOut:
            log.add("계정 이벤트: 로그아웃")
            setAccount(.signedOut)
        case .switchAccounts(let previousUser, let currentUser):
            log.add("계정 이벤트: 계정 전환")
            applyIdentity(currentUser: currentUser, previousUser: previousUser)
            if !isPaused { enqueueAllPending(in: engine, logPrefix: "계정 전환 후 보낼 변경") }
        @unknown default:
            log.add("계정 이벤트: 알 수 없음")
        }
    }

    // MARK: 받은 변경

    private func applyFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        guard !isPaused else {
            // 다른 계정의 데이터가 로컬과 섞이지 않게 한다. 원래 계정으로 돌아오면 엔진이 처음부터 다시 받는다.
            log.add("계정 변경됨, 받은 변경 반영 안 함: 변경 \(changes.modifications.count), 삭제 \(changes.deletions.count)")
            return
        }
        var inserted = 0, updated = 0, conflicts = 0, skippedDeletion = 0, deleted = 0, failed = 0, retryLater = 0
        var applied: [String] = []

        for modification in changes.modifications {
            let record = modification.record
            guard record.recordID.zoneID == StampRecordMapper.zoneID else { continue }
            do {
                let received = try StampRecordMapper.receivedStamp(from: record)
                if received.schemaVersion > Stamp.currentSchemaVersion {
                    log.add("더 높은 schemaVersion=\(received.schemaVersion) 받음, 아는 필드만 반영")
                }
                // 사진 임시 파일은 이 콜백 안에서만 유효하므로 여기서 바로 복사한다.
                let outcome = try applier.applyReceived(received)
                switch outcome {
                case .inserted: inserted += 1
                case .updated: updated += 1
                case .conflictServerWon, .conflictLocalWon: conflicts += 1
                case .skippedPendingDeletion: skippedDeletion += 1
                case .skippedStaleResult: break  // 보낸 결과 판정에서만 나온다
                }
                followUpReceive(outcome, recordID: record.recordID)
                applied.append(record.recordID.recordName)
            } catch let error as StampRecordError {
                // 형식이 잘못된 레코드는 다시 받아도 같으므로 건너뛴다(합의된 동작).
                failed += 1
                log.add("받은 레코드 건너뜀: \(Self.describe(error))")
            } catch {
                // 저장 공간·DB 오류처럼 다시 하면 될 수 있는 실패. 엔진은 다시 보내 주지 않으므로 따로 다시 받는다.
                retryLater += 1
                markForRetry(record.recordID, error: error)
            }
        }

        for deletion in changes.deletions where deletion.recordType == StampRecordMapper.recordType {
            guard let date = StampRecordMapper.date(from: deletion.recordID) else { continue }
            do {
                if try applier.applyServerDeletion(date: date) { deleted += 1 }
                applied.append(deletion.recordID.recordName)
            } catch {
                // 다시 받을 때 서버에 없다고 나오면 그때 삭제를 반영한다.
                retryLater += 1
                markForRetry(deletion.recordID, error: error)
            }
        }

        // 다시 받기 목록에 있던 것이 정상으로 반영됐으면 목록에서 뺀다.
        try? retryList.remove(applied)
        log.add(
            "받음: 추가 \(inserted), 갱신 \(updated), 충돌 \(conflicts), 삭제 \(deleted), "
                + "건너뜀(삭제 대기 \(skippedDeletion)), "
                + "형식 오류 \(failed), 다시 받기 \(retryLater)"
        )
    }

    /// 받기 충돌 결과에 맞게 엔진의 보낼 목록을 맞춘다. 로그에는 상태만 남긴다(날짜·내용 금지).
    private func followUpReceive(_ outcome: ReceiveOutcome, recordID: CKRecord.ID) {
        switch outcome {
        case .conflictServerWon:
            log.add("받기 충돌: 서버 채택")
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .conflictLocalWon(let resendsPhoto):
            log.add(resendsPhoto ? "받기 충돌: 로컬 채택, 사진도 다시 보냄" : "받기 충돌: 로컬 채택")
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .inserted, .updated, .skippedPendingDeletion, .skippedStaleResult:
            break
        }
    }

    private func markForRetry(_ recordID: CKRecord.ID, error: any Error) {
        log.add("받은 변경 반영 실패, 다시 받기 목록에 추가: \(Self.describe(error))")
        do {
            try retryList.add(recordID.recordName)
        } catch {
            log.add("다시 받기 목록 저장 실패: \(Self.describe(error))")
        }
    }

    /// 다시 받기 목록에 넣고 다음 계기를 기다리지 않고 바로 다시 받는다. 보내기 충돌을 처리하지 못했을 때 쓴다.
    private func markForRetryAndStart(_ recordID: CKRecord.ID, error: any Error) {
        markForRetry(recordID, error: error)
        Task { await retryFailedReceives() }
    }

    /// 반영에 실패했던 레코드만 iCloud에서 직접 다시 받아 반영한다. 앱 시작, 가져오기 끝, 보내기 충돌 처리 실패 때 부른다.
    func retryFailedReceives() async {
        guard let database else { return }
        // 멈춘 동안 다시 받으면 새 계정에서 받게 된다. 목록은 남겨 두고 재개 때 다시 받는다.
        guard !isPaused else { return }
        guard !isRetryingReceives else {
            receiveRetryRequestedWhileRunning = true
            return
        }
        let names = retryList.names()
        guard !names.isEmpty else { return }
        isRetryingReceives = true
        defer {
            isRetryingReceives = false
            // 도는 중에 들어온 요청은 한 번만 이어서 처리한다. 실패해 남은 것은 요청을 만들지 않으므로 반복되지 않는다.
            if receiveRetryRequestedWhileRunning {
                receiveRetryRequestedWhileRunning = false
                Task { await retryFailedReceives() }
            }
        }

        log.add("반영 실패 \(names.count)건 다시 받기")
        let ids = names.map { CKRecord.ID(recordName: $0, zoneID: StampRecordMapper.zoneID) }
        let results: [CKRecord.ID: Result<CKRecord, any Error>]
        do {
            results = try await database.records(for: ids)
        } catch {
            log.add("다시 받기 실패, 다음에 다시: \(Self.describe(error))")
            return
        }

        var finished: [String] = []
        var recovered = 0, deletedOnServer = 0, invalid = 0, remaining = 0
        for (id, result) in results {
            switch result {
            case .success(let record):
                do {
                    // 사진 임시 파일이 사라지기 전에 바로 반영(복사)한다.
                    let outcome = try applier.applyReceived(try StampRecordMapper.receivedStamp(from: record))
                    followUpReceive(outcome, recordID: id)
                    recovered += 1
                    finished.append(id.recordName)
                } catch is StampRecordError {
                    invalid += 1
                    finished.append(id.recordName)
                } catch {
                    remaining += 1
                }
            case .failure(let error):
                if (error as? CKError)?.code == .unknownItem {
                    // 서버에 없음 → 삭제 우선
                    if let date = StampRecordMapper.date(from: id) {
                        _ = try? applier.applyServerDeletion(date: date)
                    }
                    deletedOnServer += 1
                    finished.append(id.recordName)
                } else {
                    remaining += 1
                }
            }
        }
        do {
            try retryList.remove(finished)
        } catch {
            log.add("다시 받기 목록 저장 실패: \(Self.describe(error))")
        }
        log.add("다시 받기: 반영 \(recovered), 서버에 없음 \(deletedOnServer), 형식 오류 \(invalid), 남음 \(remaining)")
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
            markDeleted(id)
        }

        for failure in sent.failedRecordSaves {
            let id = failure.record.recordID
            let info = sentInfo.removeValue(forKey: id)
            handleFailedSave(id: id, error: failure.error, sentInfo: info, engine: engine)
        }

        for (id, error) in sent.failedRecordDeletes {
            handleFailedDelete(id: id, error: error)
        }

        // 용량 부족 실패가 없고 하나라도 올라갔으면 "용량 부족"을 푼다.
        let quotaFailures = sent.failedRecordSaves.filter { $0.error.code == .quotaExceeded }.count
            + sent.failedRecordDeletes.values.filter { $0.code == .quotaExceeded }.count
        statusState.recordSendResult(
            succeeded: sent.savedRecords.count + sent.deletedRecordIDs.count,
            quotaFailures: quotaFailures
        )

        log.add(
            "보냄: 저장 \(saved), 옛 결과 무시 \(ignored), 삭제 \(sent.deletedRecordIDs.count), "
                + "실패 \(sent.failedRecordSaves.count + sent.failedRecordDeletes.count)"
        )
    }

    private func handleFailedSave(id: CKRecord.ID, error: CKError, sentInfo: SentInfo?, engine: CKSyncEngine) {
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
            resolveSaveConflict(id: id, error: error, sentInfo: sentInfo, engine: engine)

        case .quotaExceeded:
            statusState.isQuotaExceeded = true
            log.add("저장 실패 quotaExceeded: 로컬 유지")

        case .notAuthenticated:
            setAccount(.signedOut)
            log.add("저장 실패 notAuthenticated: 로컬에만 저장")

        default:
            // 판단 분기에 없는 코드. 처리 방식은 정하지 않고 보고한다.
            statusState.errorCode = error.code.rawValue
            log.add("저장 실패(처리 방식 미정): \(Self.describe(error))")
        }
    }

    private func markDeleted(_ id: CKRecord.ID) {
        guard let date = StampRecordMapper.date(from: id) else { return }
        do {
            try applier.markDeleted(date: date)
        } catch {
            log.add("삭제 결과 반영 실패: \(Self.describe(error))")
        }
    }

    /// 삭제 실패. 로컬의 삭제 대기 행(pendingDeletion·needsUpload)은 지우지 않으므로 다시 보낼 때 다시 예약된다.
    private func handleFailedDelete(id: CKRecord.ID, error: CKError) {
        switch DeleteFailureAction.action(for: error.code) {
        case .keepPendingForRetry:
            log.add("삭제 실패(재시도 대기): \(Self.describe(error))")
        case .quotaExceeded:
            statusState.isQuotaExceeded = true
            log.add("삭제 실패 quotaExceeded: 삭제 대기 유지")
        case .signedOut:
            setAccount(.signedOut)
            log.add("삭제 실패 notAuthenticated: 삭제 대기 유지")
        case .treatAsDeleted:
            log.add("삭제 실패 unknownItem: 서버에 이미 없음, 삭제 완료로 처리")
            markDeleted(id)
        case .unhandled:
            log.add("삭제 실패(처리 방식 미정), 삭제 대기 유지: \(Self.describe(error))")
        }
    }

    /// `updatedAt`이 늦은 쪽을 남긴다. 로그에는 상태만 남긴다(날짜·내용·레코드 이름 금지).
    private func resolveSaveConflict(id: CKRecord.ID, error: CKError, sentInfo: SentInfo?, engine: CKSyncEngine) {
        guard let sentInfo else {
            // 보낼 때 기준을 모르면 옛 결과인지 가릴 수 없다. 판정하지 않고 다시 보내 새 결과로 판정한다.
            // 보낼 변경이 없으면 보낼 값이 nil이라 예약에서 빠진다.
            log.add("충돌 serverRecordChanged: 보낸 정보 없음, 다시 보냄")
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            return
        }
        // 오류에 서버 레코드가 없거나 읽을 수 없으면(사진 Asset이 빠진 경우 포함) 직접 다시 받아
        // 받기 충돌 규칙으로 처리한다. 다시 받아도 형식이 잘못됐으면 다시 받기에서 건너뛴다.
        guard let serverRecord = error.serverRecord,
              let server = try? StampRecordMapper.receivedStamp(from: serverRecord)
        else {
            log.add("충돌 serverRecordChanged: 서버 레코드를 읽지 못함, 다시 받기")
            markForRetryAndStart(id, error: error)
            return
        }
        do {
            switch try applier.resolveSaveConflict(server: server, sentBaseSystemFields: sentInfo.baseSystemFields) {
            case .conflictLocalWon(let resendsPhoto):
                log.add(resendsPhoto
                    ? "충돌 serverRecordChanged: 로컬 채택, 사진도 다시 보냄"
                    : "충돌 serverRecordChanged: 로컬 채택")
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            case .conflictServerWon, .updated, .inserted:
                log.add("충돌 serverRecordChanged: 서버 채택")
                engine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            case .skippedPendingDeletion:
                log.add("충돌 serverRecordChanged: 로컬 삭제 대기, 삭제 우선")
            case .skippedStaleResult:
                // 로컬이 이미 더 새 상태. 보낼 변경이 남아 있으면 지금 기준으로 다시 보내고, 없으면 예약에서 빠진다.
                log.add("충돌 serverRecordChanged: 옛 결과, 반영 안 함")
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            }
        } catch {
            // 사진 복사·저장 실패처럼 다시 하면 될 수 있는 실패. 바로 다시 받아 받기 충돌 규칙으로 처리한다.
            // 다시 받기에서도 반영에 실패하면 목록에 남기만 하고 보내기를 예약하지 않으므로 반복되지 않는다.
            markForRetryAndStart(id, error: error)
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

// MARK: - 보내기 묶음 로그

extension StampSyncEngine {
    /// 엔진이 보낼 레코드 묶음을 요청했다. 여기까지 왔는지로 우리 코드에서 멈췄는지 가린다.
    fileprivate func logBatchRequest() {
        log.add("보낼 묶음 요청 받음")
    }

    /// 계정 변경으로 멈췄으면 로그를 남기고 true.
    fileprivate func isSendingPaused() -> Bool {
        guard isPaused else { return false }
        log.add("계정 변경됨, 보낼 묶음 없음")
        return true
    }

    fileprivate func logBatch(_ batch: CKSyncEngine.RecordZoneChangeBatch?) {
        log.add(SyncDiagnostics.batchSummary(
            saves: batch?.recordsToSave.count ?? 0,
            deletes: batch?.recordIDsToDelete.count ?? 0
        ))
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
        await logBatchRequest()
        guard await !isSendingPaused() else {
            // 멈춘 동안은 어떤 우표도 보내지 않는다(새 계정에 올라가지 않게).
            return nil
        }
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else {
            await logBatch(nil)
            return nil
        }
        let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.recordToSave(recordID, engine: syncEngine)
        }
        await logBatch(batch)
        return batch
    }
}
