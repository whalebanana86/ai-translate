# TASK-027: Intel Mac에서 로컬 LLM 제외

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

사용자: "인텔맥은 제외해" (MLX는 Apple Silicon 전용이라 Intel Mac에서는 로컬 LLM을 쓸 수 없음)

## 설계

- `TranslationEngine.isSupported(onAppleSilicon:)`(테스트): 로컬은 Apple Silicon에서만
- 앱: 컴파일 시 `arch(arm64)`로 판단. Intel에서는 설정·시작 화면의 로컬 LLM을 끄고 이유를 보여주며, 저장된 선택이 로컬이면
  다시 고르게 한다. MLX 코드는 `#if arch(arm64)` 안에 둔다
- x86_64 빌드 가능 여부를 확인해, MLX가 Intel용으로 컴파일되지 않으면 그 사실과 선택지를 기록·보고

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 엔진 지원 판단 테스트.
- [x] AC2. 설정 화면에서 Intel이면 로컬 LLM이 꺼지고 이유가 보인다 (렌더링 확인).
- [x] AC3. x86_64 빌드 확인 결과 기록.
- [x] AC4. `AGENTS.md` 갱신, `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성.
- 2026-10-30: x86_64 빌드(`ARCHS=x86_64`) 성공(`AITranslate.debug.dylib`: x86_64) → MLX가 Intel용으로 컴파일은 되므로 앱 전체를
  Apple Silicon 전용으로 할 필요 없음. 시험 빌드 결과물(1.6GB) 삭제.
- 2026-10-30: `TranslationEngine.isSupported(onAppleSilicon:)`(+ 테스트), `LocalEngineError.unsupportedMac`,
  `EngineSettings.isAppleSilicon`(`#if arch(arm64)`), 저장된 선택이 지원 안 되면 nil(다시 고르게), 엔진 만들 때도 확인.
  설정 카드는 Intel이면 흐리게·선택 불가·이유 표시 (화면 밖 렌더링 확인). `AGENTS.md` 2장·3장 갱신. 검증 루프 시도 1 통과.
