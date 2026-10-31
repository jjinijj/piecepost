# 조각엽서 시스템 설계 요약 (v0.1, 2026-10-31)

원본: Claude 문서 "조각엽서(PiecePost) 시스템 설계 v0.1". 이 파일은 구현용 요약이며, 원본과 다른 점을 발견하면 수정하지 말고 질문할 것.

## 1. 결정 요약

| 영역 | 결정 |
| --- | --- |
| 플랫폼 | iOS(아이폰) 전용 |
| 우표 저장 | 기기 로컬(SwiftData, 로컬 전용)이 기준. CloudKit private DB와 CKSyncEngine으로 동기화 |
| 인증 | 없음. 앱 안 로그인·계정 없음 |
| 사진 | 원본 미저장. 1:1·1200px·HEIC 0.8 + 썸네일 300px |
| 운영 서버 | Supabase 1개를 진의 앱 세 개가 공유. 업데이트 권장·강제, 공지 |
| 로그 | 기기 내 진단 로그를 문의 메일에 첨부. 외부 로그 서비스 없음 |
| 수익화 | MVP 없음 |
| 화면 | S01 달력 홈, S02 생성·수정, S03 미리보기·상세, S04 설정. 하단 탭 없음. 저장 후 홈 복귀 |

## 2. 구조

- 화면(S01~S04) ↔ 로컬 저장소(SwiftData + 사진 파일) ↔ 동기화 엔진(CKSyncEngine) ↔ CloudKit private DB
- 운영 설정 클라이언트 → Supabase `get_config` (실패해도 앱 동작)
- S04 → 정적 웹 페이지(개인정보 처리방침·이용약관), 문의 메일(진단 로그 첨부)

## 3. 데이터 모델과 동기화

### 3.1 CloudKit 레코드 `Stamp`
- 위치: private DB, 커스텀 존 `Stamps`
- 레코드 이름: `stamp-YYYY-MM-DD`. 같은 날짜는 항상 같은 레코드라 중복 생성 불가

| 필드 | CloudKit 타입 | 설명 |
| --- | --- | --- |
| date | String | `YYYY-MM-DD`. 사용자가 달력에서 고른 날짜(과거·미래 제한 없음). 생성 후 수정 불가 |
| note | String | 선택 입력, 최대 50자(String.count), 줄바꿈 불가, 앞뒤 공백 제거 |
| photo | Asset | 자른 이미지(1:1, 1200px, HEIC 0.8) |
| thumbnail | Asset | 300px |
| createdAt | Date/Time | 최초 저장 시각 |
| updatedAt | Date/Time | 마지막 수정 시각. 충돌 판단에 사용 |
| schemaVersion | Int(64) | 레코드 형식 버전, 초깃값 1 |

- CloudKit 인덱스: date에 queryable만(디버깅용). 월 조회는 로컬에서 처리
- 출시 전 개발 스키마를 운영으로 배포해야 함. 배포 후 필드 삭제·이름 변경·타입 변경 불가

### 3.2 로컬 모델(SwiftData)

| 필드 | 설명 |
| --- | --- |
| date | 기본 키. `@Attribute(.unique)` 사용 가능(CloudKit 자동 동기화를 끄므로) |
| note, createdAt, updatedAt, schemaVersion | CloudKit 필드와 동일 |
| photoPath, thumbnailPath | 앱 컨테이너 내 파일 경로 |
| systemFields | 마지막으로 받은 CKRecord 시스템 필드(인코딩된 Data) |
| needsUpload | iCloud에 아직 올리지 못한 변경 여부 |
| photoNeedsUpload | 다음 업로드에 photo·thumbnail Asset을 포함해야 하는지. 기록만 수정하면 false 유지(2026-10-31 추가) |
| pendingDeletion | 삭제 요청 후 업로드 대기 여부. SwiftData `PersistentModel.isDeleted`와 이름이 겹쳐 원본의 isDeleted 대신 씀(2026-10-31 변경) |

### 3.3 충돌 규칙
- 업로드 시 `serverRecordChanged` → `updatedAt`이 늦은 쪽을 남김
- 삭제와 수정이 충돌하면 삭제 우선
- 밀린 쪽 내용 보관·안내 여부: 미결정(질문할 것)

## 4. 사진 처리 순서
1. PhotosPicker로 선택
2. 원본 해상도에서 1:1로 자르기
3. 1200px로 한 번 리사이즈
4. HEIC 품질 0.8로 한 번 인코딩
5. 3번 결과에서 300px 썸네일 생성
6. 기기에 파일로 저장 후 Asset으로 업로드

- 기록만 수정하면 사진을 다시 업로드하지 않음
- 수정 화면에서 다시 자르기: "사진 바꾸기"로 앨범에서 다시 고르게 하는 안이 제안됨. "자르기" 버튼 처리는 미결정

## 5. iCloud 상태별 동작

| 상태 | 감지 | 앱 동작 | 안내 |
| --- | --- | --- | --- |
| 정상 | 계정 available | 백그라운드 동기화 | S04 "iCloud에 백업됨" |
| 오프라인 | 네트워크 오류 | 로컬 저장, 연결되면 업로드 | 없음 |
| iCloud 꺼짐·로그아웃·제한 | noAccount, restricted | 로컬에만 저장, 켜지면 업로드 | 홈 배너(닫기 가능) + S04 |
| 용량 부족 | quotaExceeded | 업로드 보류, 포그라운드 진입 시 재시도 | 홈 배너 + S04 |
| 첫 동기화 | 로컬 비어 있고 첫 가져오기 중 | 받은 우표부터 표시 | 홈에 "가져오는 중", "우표 없는 월"로 보이지 않게 |
| iCloud 계정 변경 | CKAccountChanged | 제안: 업로드 완료분 삭제 후 새 계정 데이터 받기 | 미업로드분 처리 미결정(질문할 것) |

- 기록 전부 지우기(S04): 확인 창 2회 → 존 `Stamps` 삭제 + 로컬 데이터·사진·로그 삭제

## 6. 운영 서버(Supabase)

- 앱은 `get_config(p_app_id, p_app_version)` RPC 하나만 호출. 테이블 직접 조회 금지
- 앱 ID: `piecepost`. 앱에는 publishable key만 넣음(service role 금지)
- 호출: 앱 실행 + 포그라운드 복귀 시, 마지막 성공 후 6시간 안이면 생략. 타임아웃 3초
- 실패: 마지막 응답 캐시 사용, 캐시도 없으면 기본값(강제 없음, 공지 없음)
- 강제 업데이트: 현재 버전 < minSupportedVersion → 전체 화면 + App Store 버튼, 닫기 없음
- 권장 업데이트: 현재 버전 < recommendedVersion → 안내 창, 같은 버전에 대해 한 번만
- 공지: 처음 보는 공지 id만 홈 진입 시 시트로 표시
- 우선순위: 강제 > 권장 > 공지, 하나만 표시

응답 형식:
```json
{
  "minSupportedVersion": "1.0.0",
  "recommendedVersion": "1.0.2",
  "flags": {},
  "notices": [{ "id": "uuid", "level": "info", "title": "...", "body": "..." }],
  "otherApps": [{ "id": "...", "name": "...", "appStoreId": "...", "iconUrl": "..." }]
}
```

SQL(테이블·RLS·RPC): `supabase/ops_schema.sql`. Supabase 프로젝트에 적용하는 작업은 사용자 확인 후에만 진행할 것(세 앱이 공유하는 운영 DB).

## 7. 진단 로그
- 남김: 동기화 이벤트, CloudKit 오류 코드, iCloud 계정 상태, 앱·iOS 버전, 기기 모델, MetricKit 진단 요약
- 남기지 않음: 기록 내용, 사진, 날짜별 기록 여부
- 파일 크기 상한 두고 오래된 항목부터 삭제(상한 값 미결정)
- 문의하기: 메일 작성 화면 + 로그 첨부. 메일 계정이 없으면 주소 복사 + 로그 공유 시트

## 8. 화면 변경(확정 화면 대비)
- 추가: 홈 iCloud 배너, 첫 동기화 표시, S04 동기화 상태·기록 전부 지우기·로그 첨부 문의, 강제 업데이트 화면, 권장 업데이트 창, 공지 시트
- 제거: 월 데이터 로딩, 서버 오류·재시도, 업로드·저장 실패
- 변경: S02·S03 사진 칸 1:1
