# TASK-021: 로컬 모델 미리 불러오기·예열, 엔진 준비와 OCR 동시 진행

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

TASK-019 개선 방안 2번. 측정 근거: 첫 렌즈에서 엔진 준비(로컬 모델 불러오기) 1582ms가 OCR 앞에 줄을 서고,
첫 생성이 4309ms(GPU 커널 준비)로 첫 문단까지 약 6초.

## 설계

- `LocalTextGenerator.load`: 불러온 뒤 짧은 예열 생성(최대 4토큰)을 한 번 돌린다
- `EngineSettings.prepare()`: 선택된 엔진을 백그라운드에서 미리 만들어 기억. 앱 시작(엔진이 정해져 있으면)·엔진 변경·
  모델 받기 완료 때 호출. 같은 엔진을 동시에 두 번 만들지 않게 진행 중인 준비를 함께 기다린다
- `LensSession`: OCR은 엔진 없이 바로 하고(`TextRecognizer` 직접), 엔진 준비는 렌즈를 띄울 때 시작해 끝나면 번역을 시작.
  준비가 실패하면 상태에 보이고, 다음 화면 변화 때 다시 준비한다. 엔진 변경 중 늦게 끝난 준비는 버린다
- 로컬 엔진을 고른 동안은 앱이 모델(약 1.2GB)을 메모리에 둔다 (AGENTS.md에 기록)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 엔진 준비가 OCR을 막지 않고, 준비가 끝나면 번역이 시작된다 (코드·기록 확인).
- [x] AC2. 같은 엔진 준비가 겹치지 않는다. 엔진 변경 중 늦게 끝난 준비는 쓰지 않는다.
- [x] AC3. 앱 빌드·실행, `AGENTS.md` 갱신, `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-10-30: TASK 생성.
- 2026-10-30: `LocalTextGenerator.load` 예열 생성(4토큰), `EngineSettings.prepare()`·`makeProvider()`가 진행 중 준비를
  함께 기다림(`preparing`), 앱 시작·엔진 변경·모델 받기 완료 때 미리 준비. `LensSession`: OCR을 `TextRecognizer`로 바로 하고
  `prepareTranslator()`(렌즈 띄울 때 시작, 실패하면 다음 화면 변화 때 재시도, `engineGeneration`으로 엔진 변경 뒤 늦은 준비 버림),
  "엔진 준비" 시간은 별도 기록. `AGENTS.md` 갱신. 검증 루프 시도 1 통과, 앱 실행 정상(pid 74069, 새 오류 보고서 없음).
