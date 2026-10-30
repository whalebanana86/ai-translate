# TASK-020: 지나간 화면의 번역 요청 취소

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

사용자: "7번제외하고 차례대로 진행하고 인텔맥은 제외해 그리고 커밋하고 푸시해" (TASK-019 개선 방안 1번)
측정 근거: Claude가 지나간 화면의 16문단 요청(20.8초)을 마쳐야 새 화면을 번역해 화면 전체 번역까지 최대 63초.

## 설계

- 새로 인식한 화면에서, 진행 중인 요청의 문단 중 화면에 남은 것이 절반 미만이면 요청을 취소하고 새 화면부터 번역
  (`TranslationScheduling.shouldAbandon`, 테스트). CLI 엔진은 `ProcessExecutor`가 취소 시 프로세스를 끝냄
- 요청마다 번호를 붙여, 취소된 요청이 늦게 끝나도 새 요청 상태를 덮어쓰지 않게 함 (번역 결과는 기억에 저장)
- 번역 순서는 이미 화면 위부터 (`TextBlockGrouper` 문단 순서)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 판단 규칙 테스트 (모두 지나감·절반 미만 → 취소, 절반 이상 남음·요청 없음 → 유지).
- [x] AC2. 렌즈가 취소·새 요청을 처리하고 기록(취소 시 문단 수)을 남긴다. 앱 빌드.
- [x] AC3. `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성.
- 2026-10-30: `TranslationScheduling.shouldAbandon`(+ 테스트 3개), `LensSession`: 인식 직후 `abandonTranslationIfPassed()`,
  요청 번호(`translateGeneration`)로 늦게 끝난 요청이 상태를 덮어쓰지 않게(번역은 기억에 저장), 엔진·언어 변경도
  `cancelTranslation()`으로 통일. 검증 루프 시도 1 통과. 실제 효과는 다음 실사용 기록에서 확인.
