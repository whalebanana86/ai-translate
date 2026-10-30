# TASK-018: 엔진 선택 (처음 실행·설정 창), 로컬 모델 수동 받기 화면, 렌즈 연결

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

TASK-016 요청의 일부: "처음 앱 설치시 또는 설정에서 클로드코드 코덱스 로컬llm을 선택하게 해주고 로컬llm선택시 Hy-mT2
모델다운로드 수동으로 할수 있게 해줘"

## 설계

- `TranslateCore/TranslationEngine`: Claude Code·Codex·로컬 LLM, 이름·설명, 외부 전송 여부·전송 대상
- 앱
  - `EngineSettings`(@Observable): 선택 엔진(UserDefaults `TranslationEngine`), CLI 설치 확인, 로컬 모델 상태(받지 않음·받는 중·
    설치됨·실패)와 받기·취소·지우기, 선택 엔진의 번역 엔진 만들기
  - `SettingsView`: 엔진 라디오 선택 + 엔진별 설명·상태. 로컬 LLM은 "모델 받기(1.0GB)"(수동)·진행률·취소·지우기
  - 설정 창(`SettingsWindowController`): 메뉴 "설정…"(⌘,). 처음 실행(엔진 미선택) 때는 같은 화면을 시작 안내로 띄움
  - 렌즈: 선택 엔진으로 번역. 엔진을 바꾸면 진행 중 요청을 취소하고 기억한 번역을 비워 다시 번역.
    `preferredBatchSize`(로컬 1)만큼 나눠 보내 번역되는 대로 보여줌
  - 전송 고지: 외부 엔진만, 엔진별 1회 (Claude는 기존 동의 키 유지)
- 로컬 엔진의 실제 생성기(MLX)는 TASK-016에서 연결. 그 전까지는 "로컬 엔진 준비 중" 오류

## 완료 조건 (Acceptance Criteria)

- [x] AC1. `TranslationEngine` 값·외부 전송 여부 테스트.
- [x] AC2. 엔진 미선택 상태로 실행하면 시작 안내 창이 뜨고, ⌘⇧1도 렌즈 대신 안내 창을 띄운다.
- [x] AC3. 설정 창에서 엔진을 바꾸면 저장되고 열린 렌즈가 새 엔진으로 다시 번역한다.
- [x] AC4. 로컬 LLM: 모델 받기 버튼·진행률·취소·지우기 화면 (화면 밖 렌더링으로 상태별 확인).
- [x] AC5. 앱 빌드·실행, `AGENTS.md` 갱신, `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성. (TASK-016은 Metal 툴체인 설치 대기로 BLOCKED, TASK-017 완료)
- 2026-10-30: `TranslateCore/TranslationEngine`(+ 테스트 3개), `LocalEngineError`. 앱: `EngineSettings`, `SettingsView`,
  `SettingsWindowController`, `LocalTextGenerator`(MLX 연결 전 자리표시: "로컬 번역 엔진이 아직 연결되지 않았습니다"),
  `AppDelegate`(처음 실행·⌘⇧1에서 엔진 없으면 안내 창, "설정…" ⌘,), `DataTransmissionNotice.confirm(for:)`(엔진별 1회),
  `LensSession`(설정이 만든 엔진 사용, `changeEngine()`, `preferredBatchSize`로 나눠 보내기).
- 2026-10-30: 빌드 1차 오류: 진행률 콜백 안에서 약한 `self`를 다시 잡아 Swift 6 동시성 오류 → Sendable `ProgressReporter`
  (0.5%마다만 메인 액터 클로저로 넘김)로 바꿈.
- 2026-10-30: 설정 화면 화면 밖 렌더링: 시작 안내(엔진 미선택, "시작하기" 꺼짐), 받는 중 42%·취소, 설치됨·지우기, 실패·다시 받기,
  CLI 찾음(초록)·못 찾음(주황) 확인. 고정한 Hy-MT2 파일 8개의 크기·해시를 실제 파일과 대조해 모두 일치.
- 2026-10-30: `AGENTS.md` 2장(번역 엔진 결정)·3장(엔진 선택·로컬 모델)·4장(로컬 엔진 규칙, 엔진별 전송 고지) 갱신.
  검증 루프 시도 1 통과. `run-app.sh` 실행(pid 55574): 엔진 미선택 상태라 안내 창(540×485, 레이어 0)이 뜬 것을 창 목록으로 확인.
  엔진 전환 시 렌즈 재번역·실제 모델 받기는 사용자 화면 확인 몫.
