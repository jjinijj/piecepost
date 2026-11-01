# 조각엽서(PiecePost)

하루 한 장, 사진과 짧은 기록으로 우표를 만들어 달력에 붙이는 iOS 앱. 자체 서버·로그인 없이 기기 로컬 + 사용자 iCloud(CloudKit)로 동작함.

## 기술 스택
- 언어/UI: Swift, SwiftUI. 최소 지원 iOS 26.5 (프로젝트 `IPHONEOS_DEPLOYMENT_TARGET`과 같음. CKSyncEngine·SwiftData 자체는 17.0부터 지원)
- 로컬 저장: SwiftData, 로컬 전용(CloudKit 자동 동기화 끔)
- 동기화: CloudKit `CKSyncEngine`, private DB, 커스텀 존 `Stamps`
- 사진: PhotosUI `PhotosPicker`(PHPicker). 사진 보관함 전체 접근 권한 요청 금지
- 로그: OSLog + MetricKit. 문의 메일은 MessageUI
- 운영 서버 호출: `URLSession`으로 Supabase RPC 직접 호출
- 외부 패키지(SPM 포함) 추가 금지. 필요하다고 판단되면 추가하지 말고 이유를 적어 질문

## 코드 규칙
- 네이밍: 타입 PascalCase, 함수·변수 camelCase, 파일명 = 파일 안 주 타입 이름
- 폴더: `App/`, `Features/Calendar|StampEditor|StampDetail|Settings|SyncSpike/`, `Data/`, `Sync/`, `Media/`, `Ops/`, `Diagnostics/`. 새 최상위 폴더가 필요하면 질문
- 사용자에게 보이는 문구는 한국어. 코드 주석은 한국어 허용

### 반드시 지킬 불변 규칙
1. 우표 날짜는 `String`(`YYYY-MM-DD`)으로 저장함. `Date`로 저장하지 않음
   - ❌ `var date: Date`
   - ✅ `var date: String // "2026-11-18"` (변환은 `Data/StampDate.swift` 한 곳에서만. 날짜 판단은 `Calendar.current.timeZone`, 문자열은 그레고리력 고정 + `en_US_POSIX`. 기기 달력이 불교력·일본력이어도 연도가 바뀌지 않게 함)
2. CloudKit 레코드 이름은 `stamp-` + 날짜. 다른 형식 금지
   - ❌ `CKRecord.ID(recordName: UUID().uuidString, ...)`
   - ✅ `CKRecord.ID(recordName: "stamp-\(stamp.date)", zoneID: stampsZoneID)`
3. SwiftData 컨테이너는 CloudKit 자동 동기화를 반드시 끔. iCloud 권한이 있으면 기본값이 자동 동기화를 켤 수 있음
   - ❌ `ModelConfiguration()`
   - ✅ `ModelConfiguration(cloudKitDatabase: .none)`
4. 화면은 로컬 저장소만 읽음. View·ViewModel에서 CloudKit을 직접 호출하지 않음. CloudKit 접근은 `Sync/`에서만
5. 사진은 원본에서 한 번만 자르고(1:1) 줄이고(1200px) 압축(HEIC 0.8)함. 썸네일은 300px. 기록만 수정할 때 사진을 다시 인코딩·업로드하지 않음
6. 기록(note): 선택 입력, 최대 50자(`String.count` 기준), 줄바꿈 불가, 저장 시 앞뒤 공백 제거, 공백만 있으면 빈 문자열
7. CloudKit 필드 이름·타입은 `docs/system-design.md` 3.1 표와 똑같이 씀. 필드 추가·이름 변경이 필요하면 코드를 바꾸지 말고 질문(운영 스키마 배포 후 되돌릴 수 없음)
8. 진단 로그에 기록 내용·사진·날짜별 기록 여부를 남기지 않음. 상태와 오류 코드만 남김
   - ❌ `logger.info("saved note: \(note)")`
   - ✅ `logger.info("stamp saved, needsUpload=true")`
9. 운영 서버 실패는 앱 사용을 막지 않음. 예외는 캐시된 응답 기준 강제 업데이트 하나뿐

## 판단 분기
- CloudKit 오류가 `networkUnavailable`·`networkFailure`면 → `needsUpload` 유지, 재시도는 CKSyncEngine에 맡김
- `quotaExceeded`면 → 동기화 상태를 "용량 부족"으로 바꾸고 로컬 데이터는 유지
- `serverRecordChanged`면 → `updatedAt`이 늦은 쪽을 남김. 삭제와 수정이 충돌하면 삭제 우선
- `notAuthenticated` 또는 계정 상태 `noAccount`·`restricted`면 → "iCloud 꺼짐" 상태, 로컬에만 저장
- 위에 없는 오류 코드면 → 로그를 남기고, 처리 방식은 추측하지 말고 질문
- 아래 미결정 항목을 건드리는 구현이면 → 임의로 정하지 말고 멈추고 질문
  - 충돌 시 밀린 쪽 내용 보관·안내 여부
  - iCloud 계정 변경 시 미업로드 데이터 처리
  - 수정 모드의 "자르기" 버튼 처리
- 설계 문서와 요청이 다르거나 문서에 없는 결정이 필요하면 → 추측하지 말고 질문

## 검증 (모든 수정 후 필수)
1. 사용할 시뮬레이터 확인: `xcrun simctl list devices available`
2. 빌드·테스트: `xcodebuild test -scheme PiecePost -destination 'platform=iOS Simulator,name=<1번에서 확인한 기기 이름>'`
   - PR 안의 중간 커밋은 같은 명령에 `-only-testing:PiecePostTests`를 붙여 빌드와 단위 테스트만 확인함. PR의 마지막 커밋은 위 명령 그대로 UI 테스트까지 전체 실행
3. 실패하면 통과할 때까지 수정. 통과 전에는 완료 보고 금지
4. 동기화 관련 수정이면 → 자동 테스트로 확인할 수 없으므로 `docs/tasks/01-sync-spike.md`의 수동 확인 항목 중 해당하는 것을 보고에 체크리스트로 적음
5. 스킴 이름이 `PiecePost`가 아니면 → 실제 스킴 이름을 확인해 이 파일의 명령을 고치자고 제안

## 참조 문서
- 데이터 모델·동기화·사진·iCloud 상태·운영 서버 작업 시 → `docs/system-design.md`를 먼저 읽을 것
- 동기화 시험(첫 작업) 시 → `docs/tasks/01-sync-spike.md`를 먼저 읽을 것
