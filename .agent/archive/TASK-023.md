# TASK-023: Claude 요청 나누기 (새 화면은 위쪽 문단 먼저)

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

TASK-019 개선 방안 4번. 근거: Claude 요청당 7.6~20.8초(8~28문단을 한 번에), 새 화면의 첫 번역이 그만큼 늦게 보임.

## 설계

- `TranslationProvider.firstBatchSize`(기본 nil). Claude Code 3. Codex는 요청마다 7~9초 고정 비용이라 나누지 않음
- `TranslationScheduling.batch`(테스트): 엔진이 문단 수를 정했으면(로컬 1) 그만큼, 화면에 보이는 번역이 없으면(새 화면)
  첫 묶음 크기만큼, 그 밖에는 남은 문단 모두
- 대가: 새 화면마다 Claude 호출이 1번 → 2번 (요청당 고정 약 3초)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 묶음 결정 테스트.
- [x] AC2. 렌즈 적용, 앱 빌드.
- [x] AC3. `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성.
- 2026-10-30: `TranslationProvider.firstBatchSize`(Claude 3), `TranslationScheduling.batch`(+ 테스트 3개), 렌즈가 화면에
  보이는 번역 여부로 묶음 결정. 검증 루프 시도 1 통과.
