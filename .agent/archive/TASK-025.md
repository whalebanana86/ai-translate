# TASK-025: 렌즈 가장자리에 걸친(잘린) 문단은 나중에 번역

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

TASK-019 개선 방안 6번. 근거: 렌즈 위아래 끝에 걸친 문단은 스크롤할 때마다 보이는 부분(글)이 바뀌어 매번 새 문단으로
번역되고, 온전히 보이는 문단보다 먼저 번역 순서를 차지할 수 있다.

## 설계

- `LensGeometry.isCutOff(_:imageHeight:)`: 문단 영역이 캡처 이미지 위·아래 끝에서 `edgeMargin`(6px) 안이면 잘린 문단
- `TranslationScheduling.prioritized(_:isCutOff:)`: 온전한 문단을 먼저, 잘린 문단을 뒤로 (각각 순서 유지)
- 렌즈가 번역할 문단을 이 순서로 보낸다 (잘린 문단도 결국 번역한다)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 잘림 판단·순서 테스트.
- [x] AC2. 렌즈 적용, 앱 빌드.
- [x] AC3. `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성.
- 2026-10-30: `LensGeometry.isCutOff`·`edgeMargin`, `TranslationScheduling.prioritized` + 테스트 2개, 렌즈가 캡처 높이를 들고 번역 순서에 적용. 검증 루프 시도 1 통과.
