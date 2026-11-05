# TASK-079: 같은 화면은 늘 같은 색·크기로 읽기 (동점 고르기를 정하기)

- 상태: COMPLETED
- 생성일: 2026-11-05

## 요청

TASK-078 보고의 남은 것("바탕색 고르기가 실행마다 달라짐")에 "남은것 진행해" (2026-11-05).

TASK-078 회귀 비교에서 같은 OCR 결과를 같은 코드로 두 번 돌려도 글자 크기가 달랐다(119장 중 12장). `SWIFT_DETERMINISTIC_HASHING=1`로
해시를 고정하면 같아졌다. 개수가 같은 후보 중 하나를 사전 순회 순서로 골랐기 때문이다. Swift 사전은 같은 프로세스에서도 사전마다 순서가
달라(같은 키를 같은 순서로 넣은 사전 200개의 동점 max가 4~5가지로 갈림, 스크래치 `hash-order`), 앱에서 같은 화면을 다시 인식해도
바탕색·글자색·잰 크기가 바뀔 수 있다.

## 고칠 곳

- `TextStyleMeter.Pixels.dominantColor`: 줄 바탕색(글자 크기 재기). 동점이면 먼저 나온(위·왼쪽) 색
- `BlockColors.dominant`: 렌즈가 그리는 문단 바탕색·글자색. 동점이면 먼저 나온 색
- `TextStyleMeter.script(of:)`: 글자 수가 같은 문자(예: "AI 번역")는 라틴 → 한글 → 한자·가나 순
- `OccludedParagraphs`: 가려진 원래 문단 목록을 조각 위치 순으로

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 개수가 같은 두 색이면 늘 먼저 나온 색을 바탕으로 고른다 (테스트: 여러 번 뽑아도 같음)
- [x] AC2. 문단 색(`BlockColors.sample`)도 같다 (테스트)
- [x] AC3. 글자 수가 같은 문자는 늘 같은 문자로 본다 (테스트)
- [x] AC4. 가려진 원래 문단 목록 순서가 조각 위치 순이다 (테스트)
- [x] AC5. 저장한 화면 119장을 같은 OCR로 해시를 고정하지 않고 두 번 돌려 결과가 같다 (스크래치 확인)
- [x] AC6. 새 테스트를 일부러 깨뜨려 실패를 확인한다 (AGENTS.md 5.2-3)
- [x] AC7. `./scripts/auto-fix-loop.sh TASK-079` 통과, 설계 문서 갱신

## 진행 기록

- 2026-11-05: TASK 생성.
- 2026-11-05: 구현. 색 고르기 두 곳은 묶음마다 처음 나온 순서를 기억해 동점이면 먼저 나온 것, `script(of:)`는 정한 순서 중 가장 많은 것,
  `OccludedParagraphs.sources(of:)`는 조각 위치 순. 테스트 4개(인자 포함 7경우).
- 2026-11-05: 깨뜨려 확인(`swift test --filter`, 옛 사전 순서 코드로 되돌림): `BlockColors` → `picksFirstColorWhenTwoColorsTie` 실패,
  `script` → `picksSameScriptWhenLetterCountsTie` 실패, `sources` → `listsOccludedParagraphsInFragmentOrder` 실패. `dominantColor`는
  처음 테스트(두 색)가 옛 코드에서도 통과했다(두 색의 사전 순서가 우연히 처음 나온 순서와 맞음) → 네 색 띠를 돌려 가며 보는 테스트로 고쳐
  4경우 모두 실패 확인. 매번 백업으로 되돌리고 `cmp`·`git status`로 확인.
- 2026-11-05: 저장한 화면 119장을 같은 OCR로 해시를 고정하지 않고 세 번 돌려 모두 같음(옛 코드는 두 번 돌려 다름). TASK-078 비교 결과
  (해시 고정)와 다른 화면 14장은 동점에서 고른 색이 바뀐 것: 문단 묶기는 그대로, 글자 크기만 조금(작성자 줄 "@abc 5시간 전" 21.5 →
  23.7px로 같은 화면의 다른 작성자 줄 23.7~23.8과 같아짐, 버튼·좋아요 줄 ±1px).
- 2026-11-05: 검증 루프 시도 1 통과. COMPLETED.
