# TASK-053: 설정에서 Claude·Codex 모델 고르기

- 상태: COMPLETED
- 생성일: 2026-11-02

## 요청

사용자: "설정에서 클로드랑 코덱스 선택시 모델도 선택하게 해줘"

## 확인

- Claude Code 2.1.316 `--model`: 최신 모델 별칭('fable', 'opus', 'sonnet')이나 전체 이름. 앱은 지금 'haiku' 고정
  (현재 세대: Haiku 5.5, Sonnet 5.5, Opus 5.5, Fable 5.1). 없는 모델은 이미 오류 문구로 보여준다(ClaudeCodeProviderTests)
- Codex CLI 0.155.0 `-m, --model`. 앱은 지금 모델을 넘기지 않아 Codex 기본 모델을 쓴다(`--ignore-user-config`). 고를 수 있는 모델은
  계정·버전마다 달라 Codex가 받아 두는 `~/.codex/models_cache.json`(models[].slug/display_name/description/visibility/priority)에 있다.
  목록에 보이는 모델(visibility "list")은 모두 추론 강도 "low"를 지원한다(앱이 넘기는 값)

## 설계

- TranslateCore: `EngineModel`(CLI에 넘기는 이름, 표시 이름, 설명). Claude는 별칭 4개 고정 목록(Haiku 기본), Codex는 캐시 파일을
  읽은 목록 + "기본값"(모델을 넘기지 않음). 캐시를 읽지 못하면 기본값만
- `CodexProvider(model:)`: 모델이 있으면 `-m <모델>`. Claude는 Haiku가 아니면 시간 제한 180초(측정 안 함: Haiku 60초 기준보다 느림)
- 번역 기억 파일을 모델별로: 기본 모델(Claude Haiku, Codex 기본값)은 지금 파일(`<엔진>.json`)을 그대로 쓰고, 다른 모델은
  `<엔진>-<모델>.json`. 모델을 바꿨을 때 전 모델 번역이 그대로 나오지 않게
- 설정: Claude·Codex 카드 안에 모델 고르기(UserDefaults `ClaudeModel`, `CodexModel`). 고른 엔진의 모델을 바꾸면 엔진을 바꿀 때처럼
  열린 렌즈가 진행 중 요청을 취소하고 그 모델의 번역 기억으로 다시 번역한다

## 완료 조건 (Acceptance Criteria)

- [x] AC1. Codex는 모델이 있을 때만 `-m`, Claude는 고른 별칭을 `--model`로 (테스트).
- [x] AC2. Codex 캐시에서 보이는 모델만 우선순위 순서로, 깨진 파일은 빈 목록 (테스트).
- [x] AC3. 번역 기억: 기본 모델은 기존 파일, 다른 모델은 모델별 파일 (테스트).
- [x] AC4. 설정 화면 모델 고르기, 렌즈 다시 번역. 화면 밖 렌더링으로 확인. `AGENTS.md` 갱신, `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-11-02: TASK 생성.
- 2026-11-02: `EngineModel`·`ClaudeCodeProvider.models/timeout(for:)`·`CodexModelCatalog`, `CodexProvider(model:)`(`--model`),
  `TranslationMemoryStore` 모델별 파일, `EngineSettings`(모델 저장·엔진+모델로 번역 엔진 캐시·고른 엔진 모델 변경 시 렌즈 다시 번역),
  렌즈 기억 엔진·모델별, 설정 카드 모델 고르기. 테스트 4개 추가(전체 215개). 테스트 하나는 Claude 엔진 저장 이름을 "claudeCode"로
  잘못 짐작해 실패 → 실제 이름 "claude-code"로 기대값을 고침. 화면 밖 렌더링: Claude Opus·Codex GPT-6-Luna 선택과 설명 확인
  (Codex 목록은 이 Mac 캐시에서 8개). 검증 루프 시도 1 통과. 실제 Opus·Fable·Codex 모델 번역은 호출하지 않음(요금제 사용량)
