# photo-test-failure (사진 회전 테스트 실패 원인 조사)

> pm-dev-pipeline 기획서(조사). PM 이 쓰고 개발자가 읽는다.

## 목표
`PhotoProcessorTests/appliesExifOrientationBeforeCropping` 이 코드 변경 없이 실패하기 시작한 원인을 찾는다. 앱 코드 문제인지, 테스트 코드 문제인지, 시뮬레이터 환경 문제인지 가리고, 고칠 방법을 **제안**한다.

## 배경 (PM 측정, 2026-11-02)
- 16:00 경 `8e219c3`(feature/sync-account-status) 전체 테스트 153/153 통과 (xcresult)
- 16:2x `9a1f666`(같은 브랜치 + develop 합침, 바뀐 파일은 AGENTS.md 한 줄) 전체 152/153. 실패 1건이 위 테스트
- 같은 테스트만(`-only-testing:PiecePostTests/PhotoProcessorTests`) 3번 다시 돌려도 3번 모두 실패
- `8e219c3` 에서 지금 다시 돌려도 실패 → 코드가 아니라 실행 환경이 달라졌을 가능성
- 실패 내용: `PhotoProcessorTests.swift:79·80·82` 세 지점의 색이 모두 `.other` (빨강도 파랑도 아님). 회전이 틀렸다면 빨강/파랑이 뒤바뀌어야 하는데, 색 판정 자체가 실패함
- 사진 처리 코드(`PiecePost/Media/PhotoProcessor.swift`)와 이 테스트는 PR #1(6876cfe) 이후 바뀐 적 없음
- 16:00~16:2x 사이 사용자가 iPhone 17 시뮬레이터에서 iCloud 로그아웃·재로그인을 했고, Xcode 로 앱을 Run 했음. 테스트는 `Clone 1 of iPhone 17` 에서 돎

## 완료 기준
1. 원인을 근거와 함께 적는다 (측정한 것과 추정한 것을 구분). 확정하지 못하면 "찾지 못함" 과 아직 안 본 것을 적는다
2. 같은 파일의 다른 색 판정 테스트는 왜 통과하는지 함께 설명한다
3. 고칠 방법을 제안한다 (앱 코드 / 테스트 코드 / 환경). 앱의 사진 처리 결과가 실제로 달라졌다면 불변 규칙 5(1:1, 1200px, HEIC 0.8, 썸네일 300px)에 영향이 있는지 적는다
4. **이번 조사에서는 커밋하지 않는다.** 고치는 것은 PM 판정·사용자 결정 뒤 별도 작업으로 한다
5. 결과를 작업 트리 또는 조사용 위치의 `docs/reviews/photo-test-failure.md` 에 적고 경로를 보낸다

## 범위 밖
- 시뮬레이터 초기화·삭제(`xcrun simctl erase` 등), 시뮬레이터 설정 변경. 필요하면 멈추고 PM 에게 보고
- `feature/sync-account-status` 브랜치 수정 (PM 이 만든 merge 커밋 9a1f666 이 로컬에 있음, 건드리지 말 것)
- 푸시·PR

## 참고
- 조사용으로는 `origin/develop`(df0ff10) 을 기준으로 별도 작업 트리를 만들어도 된다 (예: `.claude/worktrees/photo-test-failure`, 브랜치 `investigate/photo-test-failure`)
- CLAUDE.md 불변 규칙 5, 검증 절차

## 미결정
- 없음. 조사 중 결정이 필요하면 멈추고 보고

## 수정 (2026-11-02 사용자 결정: 안 A, 별도 작은 PR)
1. `origin/develop` 에서 `fix/heic-test-decode` 브랜치. 조사 작업 트리(`.claude/worktrees/photo-test-failure`)에서 `git switch -c fix/heic-test-decode origin/develop` 로 만들어도 됨
2. 조사 결과의 안 A 그대로: `PiecePostTests/PhotoProcessorTests.swift` 의 `DecodedImage` 가 `CGImageSourceCreateThumbnailAtIndex`(원본 크기, `FromImageAlways`, `ShouldCacheImmediately`)로 읽게 바꾼다. 왜 바꾸는지 짧은 주석(처음 하는 HEIC 디코딩이 검정으로 나오는 시뮬레이터 현상)
3. 앱 코드(`PiecePost/`)는 바꾸지 않는다. 썸네일 화면(`StampThumbnail`)도 이번에는 손대지 않는다(범위 밖 발견으로 보고만)
4. 커밋 하나(이 기획서 포함 여부: 이 문서는 조사·수정 기록이므로 첫 커밋에 `docs/specs/photo-test-failure.md` 도 담는다). 마지막 커밋이므로 전체(UI 포함) 테스트. 이 시뮬레이터 상태에서 사진 테스트가 통과하는지 xcresult 로 확인
5. 로컬 커밋까지만, 푸시·PR 금지, Co-Authored-By 금지
