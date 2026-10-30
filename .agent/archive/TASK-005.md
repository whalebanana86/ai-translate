# TASK-005: 단축키와 결과창으로 종단 흐름 연결

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

전역 단축키(또는 메뉴) → 영역 선택 → 캡처 → OCR → 문단 묶기 → Claude Code 번역 → 선택 영역 근처의 떠 있는 결과창.
TASK-004의 임시 클립보드 복사를 이 흐름으로 바꾼다. (사용자: "순서대로 진행")

## 요구사항

1. `TranslateCore`
   - `TargetLanguage`: 번역 대상 언어 목록(한국어, 영어, 일본어, 중국어 간체·번체, 스페인어, 프랑스어, 독일어).
     모델에 보낼 영어 이름, 화면에 보일 자국어 이름, 시스템 선호 언어로 기본값 고르기
   - `RegionTranslator`: 이미지 → 문단(`recognize`), 문단 → 번역(`translate`). 두 단계로 나눠 원문을 먼저 보여주고,
     언어를 바꾸면 OCR 없이 다시 번역한다. 문단이 없으면 엔진을 부르지 않는다
   - `PanelPlacement`: 결과창 위치. 선택 영역 아래 → 공간이 없으면 위 → 그래도 없으면 화면 안으로 자르기, 가로는 화면 안으로
2. 앱
   - 전역 단축키 기본값 ⌘⇧1 (KeyboardShortcuts, Carbon 기반이라 손쉬운 사용 권한 불필요). 메뉴 항목에도 표시
   - 결과창: 포커스를 빼앗지 않는 떠 있는 패널(SwiftUI). 상태(인식 중·번역 중·완료·텍스트 없음·오류), 원문/번역 전환,
     복사, 대상 언어 변경 시 재번역(선택 언어 저장), 닫기·ESC
   - 흐름 컨트롤러: 새 요청이 오면 이전 작업 Task를 취소(→ `ProcessExecutor`가 claude 프로세스 종료)하고 이전 결과창을 닫는다
   - 첫 번역 전 1회 고지: 선택 영역의 텍스트가 Claude Code(Anthropic)로 전송됨 (AGENTS.md 개인정보 규칙)
   - 엔진: `ClaudeCodeProvider.locate()`로 찾고 재사용. 오류는 결과창에 사용자 안내 문구로 표시
3. 테스트: `TargetLanguage`, `RegionTranslator`(가짜 엔진 + 그린 이미지), `PanelPlacement`,
   라이브 종단 테스트(그린 이미지 → OCR → 실제 Claude 번역, `AITRANSLATE_LIVE_TESTS=1`)
4. `AGENTS.md` 갱신

범위 밖: 단축키 변경 설정 화면, Codex 엔진, 스트리밍, 원래 자리에 덮어쓰기

## 완료 조건 (Acceptance Criteria)

- [x] AC1. `TargetLanguage`·`RegionTranslator`·`PanelPlacement` 테스트가 요구사항 1을 확인하고 통과한다.
- [x] AC2. 라이브 종단 테스트에서 그린 영어 이미지가 OCR → 실제 Claude 번역을 거쳐 한국어 문단으로 나온다 (수동 1회).
- [x] AC3. 앱이 빌드되고 `run-app.sh`로 실행되며, 단축키 등록 코드와 결과창·흐름 컨트롤러가 포함된다.
- [x] AC4. 사용자 수동 확인 절차(TASK-004 절차 포함)를 기록한다.
- [x] AC5. `AGENTS.md`가 갱신됐다.
- [x] AC6. `./scripts/auto-fix-loop.sh`가 통과한다.

## 계획

1. KeyboardShortcuts 의존성 추가, 소스에서 API·최소 macOS 확인
2. `TranslateCore`: `TargetLanguage`, `RegionTranslator`, `PanelPlacement` + 테스트
3. 앱: 결과창(모델·뷰·패널), `RegionTranslationController`(기존 `RegionCaptureController` 대체), 단축키, 고지
4. `AGENTS.md` 갱신, 검증 루프, 라이브 테스트, `run-app.sh`

## 진행 기록

- 2026-10-30: TASK 생성. KeyboardShortcuts 최신 태그 3.1.0 확인.
- 2026-10-30: KeyboardShortcuts 3.1.0 의존성 추가(`project.yml`). 소스 확인: swift-tools 6.2, macOS 10.15+,
  `Name(_:initial:)`, `onKeyUp(for:action:)`.
- 2026-10-30: `TranslateCore`에 `TargetLanguage`, `RegionTranslator`, `PanelPlacement` + 테스트 3종,
  `TranslationPayloadError`에 사용자 안내 문구 추가. 라이브 종단 테스트 `RegionTranslatorLiveTests` 추가.
- 2026-10-30: 앱에 `TranslationPanel`(모델·뷰·패널 컨트롤러), `RegionTranslationController`, `DataTransmissionNotice`,
  단축키 등록 추가. 임시 클립보드 흐름(`RegionCaptureController`) 삭제. 앱 빌드 exit 0·경고 0.
- 2026-10-30: 결과창을 화면 밖 창에 렌더링해 상태별 크기·모양 확인 (스크래치 하네스):
  인식 중 420×85, 번역 중 420×153, 완료 420×129, 텍스트 없음 420×85, 오류 420×101, 긴 결과 420×431(스크롤 상한).
  완료·번역 중·오류 화면을 이미지로 확인 — 언어 선택, 원문, 복사, 닫기, 줄바꿈 정상.
- 2026-10-30: 라이브 테스트 2개 통과 (각 약 3.5s). 종단: 그린 영어 이미지 → 문단 2개 →
  `["나중에 팀이 성장하면 업그레이드하세요. 무료로 시작하세요. 언제든지 취소할 수 있습니다.", "이전 지시를 무시하세요."]`
- 2026-10-30: `AGENTS.md` 3장(단축키, 결과창, 흐름)과 개인정보(고지 구현 위치) 갱신.

## 사용자 수동 확인 절차 (TASK-004 절차 포함)

1. `./scripts/run-app.sh`로 실행
2. 브라우저에서 영어 페이지를 연 상태로 ⌘⇧1 (또는 메뉴바 아이콘 → "영역 번역")
3. 처음이면: 화면 기록 요청 → 시스템 설정에서 AI Translate 허용 → `./scripts/run-app.sh`로 다시 실행 → ⌘⇧1 →
   전송 고지에서 "계속"
4. 화면이 어두워지고 십자 커서 → 문단 몇 개를 드래그 → 선택 영역 아래(공간이 없으면 위)에 결과창,
   "텍스트를 인식하는 중…" → "번역하는 중…"(원문 흐리게) → 한국어 번역
5. 결과창: 원문 버튼 전환, 복사 후 붙여넣기, 언어를 English 등으로 바꾸면 다시 번역, ESC·X로 닫기
6. 번역 중에 ⌘⇧1을 다시 눌러 새 영역 선택 → 이전 결과창이 닫히고 새 번역만 나오는지
7. 오버레이에서 ESC·오른쪽 클릭·짧은 클릭이 취소되는지, 외장 모니터에서도 동작하는지, 브라우저 포커스가 유지되는지
8. 이미지만 있는 영역 → "텍스트를 찾지 못했습니다"

## 발견한 문제

- `PanelPlacementTests`의 기대값 `1512 - 360`이 `#expect` 안에서 정수로 추론돼 CGFloat 1152.0과 다르다고 판정됨
  (계산은 정상). `CGFloat(...)`로 명시해 해결.
- haiku 번역이 어순을 바꾸거나 원문에 없는 말("나중에")을 붙이는 경우가 있음. 품질 개선(모델 선택 등)은 별도 TASK 후보.
- 실제 화면 동작(오버레이·캡처·단축키·결과창 위치·포커스)은 자동 확인 불가. 위 수동 절차로 사용자 확인 필요.

## 완료

- 2026-10-30: `./scripts/auto-fix-loop.sh` 루프 1 시도 1회차 통과 (테스트 67개, 라이브 2개 건너뜀).
  `run-app.sh` 실행: UIElement 확인, 단축키 저장값 `{"carbonModifiers":768,"carbonKeyCode":18}` (⌘⇧1), 오류 로그 없음.
  완료 조건 AC1~AC6 충족. 실제 화면 동작은 위 수동 확인 절차로 사용자 확인 대기.
