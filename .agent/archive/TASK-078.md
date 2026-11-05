# TASK-078: 그래프 막대를 이모지로 보지 않기

- 상태: COMPLETED
- 생성일: 2026-11-05

## 요청

사용자 보고(2026-11-05, 화면 두 장): 그래프가 있는 페이지를 번역하면 깨진다. 사이트: https://github.com/Generated-Computers/Locals
README의 막대그래프(`docs/assets/charts/models.svg`, `servers.svg`). 번역 화면에서 모델 이름이 다음 줄 수치와 한 문단으로 이어지고
("3.1x 188 → 576 토큰/s MiniCPM5-2B"), 파란 큰 상자가 여러 막대를 덮었다.

## 원인 (재현: SVG를 Chrome 2배로 그린 화면, 스크래치 `chart-probe`)

- `EmojiFinder`가 파란 막대(글줄 높이 띠의 색 있는 덩어리, 너비 ÷ 높이 15~31)를 이모지로 봤다. 막대 양 끝이 왼쪽 이름과 오른쪽 수치에서
  줄 높이 1.5배 안이라 "두 줄 사이 이모지"로 두 줄을 이었다("Qwen3.5-2B 🟦 3.1x 188 → 576 tokens/s", 너비 210~1593)
- 이은 줄은 막대까지 덮는 상자라 글자 크기를 막대로 쟀고(40.8px bold, 실제 약 26px) 다음 막대 줄과 기준선 간격이 크기 2배 안이 되어
  5줄이 한 문단이 됐다. 문단 상자가 막대를 덮어 바탕색이 막대 파랑으로 뽑혔다
- 수치를 OCR이 못 읽은 줄("Qwen3.5-9B")은 막대에 이어 파란 수치 글자 덩어리까지 이모지로 붙었다("Qwen3.5-9B 🟦 🟦 🟦")
- 둘째 그래프(`servers.svg`): OCR이 행을 세로 축·짧은 막대를 넘어 한 줄로 읽었다("llama.cpp ▮ 2.1 s"). 축이 줄 상자를 지나
  잉크가 축 끝까지 이어져 이름 줄 24.6px를 33~40px로 쟀고, 아래 행과 기준선 간격이 크기 2배 안이 되어 한 문단이 됐다
  ("Locals 🟦 1.6s llama.cpp 21s", 사용자 화면의 큰 "llama.cpp| 2.1초")

## 요구사항

- 줄 높이보다 훨씬 긴, 꽉 찬 색 띠(막대·상자)는 이모지로 보지 않는다
- 이어 붙은 이모지(😂🔥), 한 가지 색으로 꽉 찬 이모지(👍), 네모 이모지는 지금처럼 이모지로 본다
- 글자 크기를 잴 때 줄을 지나는 세로 선(그래프 축, 표 테두리)은 잉크로 세지 않는다. 글자 획과 넓은 색 영역은 그대로 둔다

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 글줄 사이의 긴 색 막대는 이모지가 아니고 양쪽 줄을 잇지 않는다 (테스트 `doesNotTakeChartBarForEmoji`)
- [x] AC2. 이어 붙은 이모지 여러 개, 꽉 찬 이모지는 그대로 이모지다 (기존 테스트 + `keepsRowOfSquareEmoji`)
- [x] AC3. 실제 OCR: 막대그래프 이미지에서 이름과 수치가 따로 줄·문단으로 남는다 (테스트 `keepsBarChartLabelsAndValuesApart`)
- [x] AC4. 세로 축이 지나는 줄도 축 없을 때와 같은 크기로 잰다. 가늘고 긴 선만 지우고 넓은 영역·글자 획 길이 선은 둔다
  (테스트 `ignoresChartAxisCrossingLine`, `removesOnlyThinLongVerticalLines`)
- [x] AC5. 재현 화면(README 그래프 두 개)에서 막대가 이모지로 잡히지 않고 이름·수치가 행마다 따로 문단이 된다 (스크래치 확인)
- [x] AC6. 새 테스트를 일부러 깨뜨려 실패를 확인한다 (AGENTS.md 5.2-3)
- [x] AC7. `./scripts/auto-fix-loop.sh TASK-078` 통과, `docs/design/recognition.md`·`lens.md` 갱신

## 진행 기록

- 2026-11-05: TASK 생성. 재현과 원인 확인.
- 2026-11-05: 구현. `EmojiFinder.Pixels.isBar`(꽉 찬 열이 덩어리 높이 2배보다 길면 막대), `TextStyleMeter.Pixels.removingVerticalRules`
  (범위 끝에서 범위 밖까지 줄 상자 3배보다 길고 폭이 줄 상자 ¼ 안인 열의 잉크를 지움). 테스트 5개, `TextImage`에 색 상자·줄마다 색.
- 2026-11-05: 세로 선 지우기에서 실패한 방법 두 가지(설계 문서 lens.md): 범위 안에서만 끝에 닿는지 보기(Arial 문단 끝 줄 "l" 획을 지워
  문단이 갈라짐), 폭 제한 없음(자막 상자 밖 흰 페이지를 열마다 지워 자막 25px → 44px).
- 2026-11-05: 회귀 비교: 저장해 둔 화면 119장(이전 TASK 스크래치)의 OCR을 한 번 적어 두고 바꾸기 전·뒤 코드로 같은 OCR을 돌림.
  처음에는 실행마다 결과가 달랐다: Vision 결과가 실행마다 조금 다르고, 같은 OCR이어도 `TextStyleMeter.Pixels.dominantColor`가 개수가
  같은 색 중 하나를 사전 순회 순서(프로세스마다 다른 해시 시드)로 골랐다. `SWIFT_DETERMINISTIC_HASHING=1`로 고정해 비교했다(기존
  동작, 이 TASK에서 고치지 않음). 바뀐 화면 10장: 그래프(고침), 영상 프레임 묶음 6장(경계선에 닿은 제목 33px → 20px, 다른 사본과 같아지고
  자막과 한 문단이 되던 것이 갈라짐), 썸네일 위 글 2장·잡음 1장(조금씩 바뀜). 웹 글 측정 화면(Chrome 글꼴 10개, 간격 측정)은 그대로.
- 2026-11-05: 재현 화면 확인: models.svg 행마다 이름·수치가 따로 문단(24.0~28.6px), servers.svg "Locals 1.6s"·"llama.cpp 2.1s"가
  따로 문단(24.3px·27.8px, 막대가 줄 상자 안에 있어 조금 큼). 남은 것: OCR이 읽지 못한 파란 수치("Qwen3.5-9B" 행 3.0x)는 번역되지
  않고 원문이 보인다. 실제 앱 렌즈로는 확인하지 못했다.
- 2026-11-05: 깨뜨려 확인(`swift test --filter`): ① `isBar` 빼기 → `doesNotTakeChartBarForEmoji`·`keepsBarChartLabelsAndValuesApart`
  실패 ② 막대 기준 0.5배 → `keepsRowOfSquareEmoji` 실패 ③ 세로 선 지우기 빼기 → `ignoresChartAxisCrossingLine`(42% 크게)·
  `removesOnlyThinLongVerticalLines` 실패 ④ 폭 제한 빼기 → `removesOnlyThinLongVerticalLines`(넓은 영역 지움) 실패 ⑤ 길이 제한 빼기 →
  같은 테스트(짧은 획 지움) 실패. 매번 백업으로 되돌리고 `cmp`·`git status`로 확인.
- 2026-11-05: 검증 루프 시도 1 Lint 실패(테스트 줄 길이) → `swift format`으로 고침 → 시도 2 통과. COMPLETED.
- 2026-11-06: 사용자가 실제 앱 렌즈로 README 막대그래프를 보고 "막대그래프 정상"이라고 확인했다.
