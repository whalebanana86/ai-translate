# TASK-017: Codex CLI 번역 엔진

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

TASK-016 요청의 일부: 엔진 선택에 Codex를 넣는다. AGENTS.md 4장에 계획된 실행 방식이 있으나 `--output-schema` 조합은 미검증.

## 설계

- `codex exec --skip-git-repo-check --ephemeral --ignore-user-config -s read-only -C <빈 임시 폴더>
  -c model_reasoning_effort="low" --output-schema <스키마 파일> -o <출력 파일> -`
- 프롬프트(표준 입력): 번역 지시(`TranslationPrompt.system`) + JSON 세그먼트. 출력 파일의 JSON을 스키마·개수 검증
- 실행은 `ProcessExecutor`, 위치는 `CLILocator`(설정 경로 → 알려진 위치(~/.volta/bin 등) → 로그인 셸)
- 오류(로그인 필요, 사용량 한도)는 Claude 엔진과 같은 분류
- 실제 호출 테스트는 `AITRANSLATE_LIVE_TESTS=1`일 때만

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 실제 Codex CLI로 조합을 검증하고 기록한다 (시간, 출력 형식, 지시문 그대로 번역).
- [x] AC2. 가짜 실행 파일로 인자·표준 입력·작업 폴더·출력 파일 읽기·오류 분류를 테스트한다.
- [x] AC3. 라이브 테스트(환경 변수로만) 추가.
- [x] AC4. `AGENTS.md` 갱신, `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성. codex-cli 0.155.0, `~/.volta/bin/codex`.
- 2026-10-30: 실측 2회(스크래치): 7.1~8.6초, 출력 파일에 스키마대로 JSON, 지시문 그대로 번역, "Al"→"AI", 줄바꿈 유지,
  작업 폴더에 파일 안 남김. stderr에 입력이 되풀이되고 "tokens used 14,494"가 찍힘.
- 2026-10-30: `CodexProvider`(인자는 긴 옵션 이름, 스키마·출력 파일은 작업 폴더 밖 `io` 폴더, 오류 분류는 stderr 끝 600자),
  `CLILocator.codexKnownLocations`, 로그인 힌트에 "codex login" 추가. 테스트 7개(가짜 codex) + 라이브 1개.
  테스트 고정값의 작은따옴표가 가짜 셸 스크립트를 깨뜨려 문구를 "You have hit"으로 바꿈(분류 기준 "usage limit"은 같음).
  110개 통과, 라이브 테스트 통과(6.6초). `AGENTS.md` 4장 Codex 갱신.
- 2026-10-30: 검증 루프 시도 1 통과 (1차 실행은 PROGRESS.md 현재 작업 줄에 TASK 번호가 두 개라 거부됨 → 줄 정리 후 실행). 앱 연결은 TASK-018.
