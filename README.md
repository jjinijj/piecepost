# 조각엽서 (PiecePost)

하루 한 장, 사진과 짧은 기록으로 우표를 만들어 달력에 붙이는 iOS 앱.

자체 서버나 로그인 없이 기기 로컬 저장소와 사용자의 iCloud(CloudKit)로 동작합니다.

## 상태

개발 중. 지금은 CKSyncEngine 동기화 시험(스파이크)을 단계별로 진행하고 있습니다.

| 단계 | 내용 | 상태 |
| --- | --- | --- |
| 1 | 로컬 우표 모델과 저장소 | 완료 |
| 2 | 사진 처리(1:1, 1200px, HEIC) | 예정 |
| 3 | 시험 화면 | 예정 |
| 4 | Stamp ↔ CKRecord 변환 | 예정 |
| 5 | CKSyncEngine 연결 | 예정 |

## 기술 스택

- Swift, SwiftUI (iOS 26.5 이상)
- SwiftData: 로컬 전용, CloudKit 자동 동기화 끔
- CloudKit `CKSyncEngine`: private DB, 커스텀 존 `Stamps`
- PhotosUI `PhotosPicker`
- 외부 패키지 없음

## 구조

```
PiecePost/
  App/                 앱 진입점
  Data/                SwiftData 모델, 날짜·기록 규칙, 로컬 저장소
  Sync/                CloudKit 동기화 (화면에서 CloudKit을 직접 부르지 않음)
  Media/               사진 처리
  Features/SyncSpike/  동기화 시험 화면
PiecePostTests/        단위 테스트 (Swift Testing)
docs/                  설계 요약과 작업 문서
```

## 빌드와 테스트

Xcode 26 이상이 필요합니다.

```sh
xcrun simctl list devices available
xcodebuild test -scheme PiecePost -destination 'platform=iOS Simulator,name=<기기 이름>'
```

iCloud 동기화를 실제로 확인하려면 iCloud에 로그인한 기기와 CloudKit 컨테이너 권한이 있는 개발자 계정이 필요합니다.

## 문서

- [`docs/system-design.md`](docs/system-design.md): 데이터 모델, 동기화, 사진, iCloud 상태별 동작
- [`docs/tasks/01-sync-spike.md`](docs/tasks/01-sync-spike.md): 동기화 시험 범위와 수동 확인 항목

## 라이선스

라이선스를 부여하지 않습니다. Copyright © 2026 jjinijj. All rights reserved.
코드를 열람할 수는 있지만, 허락 없이 사용·수정·배포할 수 없습니다.
