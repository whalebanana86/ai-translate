# TASK-037: 번역 기록 패널 크기·위치 조절

- 상태: COMPLETED
- 생성일: 2026-11-02

## 요청

사용자: "번역기록패널 조절할 수 있게 해줘"

## 설계

- 패널 머리글(제목 줄)을 끌면 옮겨지고, 오른쪽 아래 모서리 손잡이를 끌면 크기가 바뀐다(왼쪽 위 고정, 최소 220×160).
  렌즈와 같은 방식(전역 마우스 위치로 끈 거리 계산)
- 옮기거나 크기를 바꾼 뒤에는 렌즈를 기준으로 한 그 자리를 지킨다: 렌즈를 옮기면 같은 간격으로 따라간다. 렌즈를 새로 만들면
  기본 자리(렌즈 옆)로
- 크기는 다음 렌즈에도 쓴다 (UserDefaults `TranscriptSize`)
- `LensGeometry.transcriptFrame(for:in:size:)`: 기억한 크기가 있으면 그 크기(화면 안으로 자름),
  `LensGeometry.resized(_:by:minimum:)`: 최소 크기를 받는다

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 기억한 크기로 패널 자리 계산, 최소 크기를 지키는 크기 조절 (테스트).
- [x] AC2. 머리글 끌기로 이동, 손잡이 끌기로 크기 조절, 렌즈를 옮기면 같은 간격으로 따라감 (코드), 손잡이 모양 확인 (렌더링).
- [x] AC3. `AGENTS.md` 갱신, `./scripts/auto-fix-loop.sh` 통과.
- 실제 끌기 동작은 사용자 실사용으로 확인

## 진행 기록

- 2026-11-02: TASK 생성.
- 2026-11-02: `transcriptFrame(for:in:size:)`, `minimumTranscriptSize`, `resized(_:by:minimum:)`(+ 테스트 2개). 화면: 머리글 끌기,
  오른쪽 아래 손잡이. 렌즈: `dragTranscript`(끝나면 렌즈 기준 자리 기억, 크기 조절일 때만 크기 기억·저장 — 처음에는 옮기기만 해도
  기본 크기를 저장해 다음 렌즈에서 높이가 고정되는 문제가 있어 고침), `layoutPanels`가 기억한 자리·크기 사용, 크기는
  UserDefaults `TranscriptSize`. 렌더링: 손잡이 보임. 기록이 적을 때 아래에 붙어 위가 비어 보임(TASK-036의
  `defaultScrollAnchor(.bottom)`이 정렬까지 바꿈) → 처음 위치에만 적용(`for: .initialOffset`), 하네스로 따라가기 다시 확인(17~25번 보임).
  `AGENTS.md` 갱신. 검증 루프 시도 1 통과. 실제 끌기는 사용자 확인 필요.
