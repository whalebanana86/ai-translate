# TASK-075: 글과 코드가 어긋난 규칙 맞추기 (로컬 엔진 시간 제한, ProcessExecutor 예외, 전역 모니터 문장)

- 상태: COMPLETED
- 생성일: 2026-11-04

## 요청

"이 프로젝트에 글로만 있고 기계가 검사하지 않는 규칙이 있는지 조사해" → 조사 보고의 제안 1·2 중 "제안에서 1,2번만 진행해".
제안 1: 이미 글과 코드가 어긋난 세 곳을 정리한다.

## 조사에서 찾은 것

1. AGENTS.md 4장 "모든 엔진 호출에 시간 제한을 두고": 로컬 엔진(`LocalTranslationProvider`)에는 시간 제한이 없다.
   생성 길이 상한(`HyMTPrompt.maxTokens`, 최대 2048토큰)과 토큰마다 취소 확인만 있다. 요청은 동시에 하나라 생성이 멈추면 뒤 문단이
   번역되지 않는다
2. AGENTS.md 4장 "외부 프로세스는 `ProcessExecutor`로만 실행한다": `App/AppLanguageSettings.swift`의 다시 열기는 `Process()`를
   직접 쓴다. `docs/design/localization.md`에는 이 예외(앱이 끝난 뒤에도 남아 앱을 다시 연다)가 적혀 있어 문서끼리 맞지 않는다
3. AGENTS.md 3장 "`NSEvent` 전역 모니터는 손쉬운 사용 권한이 필요하므로 쓰지 않는다": 렌즈는 스크롤·클릭·`mouseMoved` 전역
   모니터를 쓴다(권한 불필요, capture.md). 권한이 필요한 것은 키 입력 모니터뿐이라 문장이 실제 규칙보다 넓다

## 결정

1. 로컬 엔진에도 문단마다 시간 제한을 둔다(글을 코드에 맞추지 않고 코드를 규칙에 맞춘다). 정상 생성을 끊지 않도록 생성 길이 상한에
   맞춰 넉넉하게: 10초 + 토큰 상한 × 0.1초(초당 10토큰 가정. M5 측정 초당 101~112토큰). "OK" 16.4초, 긴 문단(2048토큰) 214.8초.
   넘으면 `TranslationEngineError.timedOut`("번역 시간이 초과됐습니다. 다시 시도하세요.")
2. ProcessExecutor 문장에 다시 열기 예외를 적는다
3. 전역 모니터 문장을 키 입력 모니터로 좁히고, 마우스·스크롤 모니터는 권한 없이 쓴다고 적는다

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 로컬 엔진이 시간 제한 안에 끝나지 않으면 `timedOut`을 던지고 생성을 취소한다 (테스트)
- [x] AC2. 시간 제한은 생성 길이 상한에 맞춰 커진다 (테스트)
- [x] AC3. AGENTS.md 4장 ProcessExecutor 문장에 예외, 시간 제한 문장에 로컬 엔진이 있다. 3장 전역 모니터 문장이 키 입력으로 좁혀졌다
- [x] AC4. `docs/design/translation.md`에 로컬 엔진 시간 제한과 근거가 있다
- [x] AC5. `./scripts/auto-fix-loop.sh TASK-075` 통과

## 진행 기록

- 2026-11-04 작업 생성
- `LocalTranslationProvider`: 문단마다 `generate(within:)`(작업 그룹으로 생성과 대기를 겨루고, 먼저 끝난 쪽 결과, 나머지 취소).
  시간 제한은 `HyMTPrompt.timeLimit(for:)`, 테스트에서 바꿀 수 있게 내부 init으로 받는다
- 테스트: 끝나지 않는 생성기(60초 대기)에 0.2초 제한 → `timedOut`, 생성기가 취소를 받음, 5초 안에 끝남. "OK" 16.4초·5000자 214.8초
- AGENTS.md 3장 전역 모니터 문장, 4장 시간 제한·ProcessExecutor 문장. localization.md 다시 열기 예외 이유, translation.md 시간 제한
- 검증 루프: 시도 1 통과 (docs·typecheck·lint·build·test)
