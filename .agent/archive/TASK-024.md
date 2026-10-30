# TASK-024: 로컬 번역을 생성되는 대로 표시

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

TASK-019 개선 방안 5번. 근거: 로컬 문단당 83ms~2.5초, 긴 문단은 다 끝날 때까지 아무것도 안 보임.

## 설계

- `TextGenerating.generate(prompt:maxTokens:onPartial:)`: 지금까지 생성한 글을 넘긴다 (기존 호출은 확장으로 유지)
- `TranslationProvider.translate(_:onPartial:)`(기본은 무시하고 보통 번역), 로컬 엔진은 (문단 번호, 정리한 중간 글)을 넘긴다
- `RegionTranslator.translate(_:to:onPartial:)`: 문단 번호를 원문 문단으로 바꿔 넘긴다 (번역 안 하는 문단 건너뜀)
- `LensSession`: 중간 글을 원문별로 들고 있다가 대기 문단 자리에 그린다. 화면 갱신은 0.05초에 한 번까지.
  최종 번역이 기억에 들어가면 중간 글을 버린다 (늦게 온 중간 글은 무시)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 로컬 엔진·RegionTranslator 중간 글 전달 테스트.
- [x] AC2. 렌즈 적용, 앱 빌드.
- [x] AC3. `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성.
- 2026-10-30: `TextGenerating.generate(…onPartial:)`, `TranslationProvider.translate(_:onPartial:)`(기본 무시),
  `LocalTranslationProvider`·`RegionTranslator` 중간 글 전달 + 테스트 2개, MLX 생성기가 조각마다 지금까지 글을 넘김.
  `LensSession`: `partials`, `showPartial`(요청 번호·언어·이미 끝난 번역 확인, 0.05초 간격), 대기 문단 자리에 중간 글.
  검증 루프 1차 실패: 테스트 기대값 계산 실수("변경 사항 저장" 앞 절반은 "변경 사") → 기대값만 바로잡아 2차 통과.
