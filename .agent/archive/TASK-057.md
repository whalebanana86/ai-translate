# TASK-057: 렌즈 도구 막대 툴팁이 보이게

- 상태: COMPLETED
- 생성일: 2026-11-03

## 요청

"렌즈 실행하면 렌즈바에 있는 기능들에 마우스오버하면 툴팁 넣어줘" (2026-11-03)

## 원인

도구 막대 버튼에는 이미 툴팁(`.help`)이 있지만 보이지 않는다. 렌즈는 앱을 활성화하지 않는 패널(`.nonactivatingPanel`, 메뉴바 앱)이라
렌즈를 쓰는 동안 앱이 비활성 상태이고, AppKit은 비활성 앱의 창에서 툴팁을 띄우지 않는다.
시험 앱(저장소 밖)으로 확인: 비활성 상태에서 마우스를 올리면 hover는 오지만 툴팁 창(`NSToolTipPanel`)이 생기지 않고,
`NSWindow.allowsToolTipsWhenApplicationIsInactive = true`면 생긴다.

## 설계

- `LensPanel`에서 `allowsToolTipsWhenApplicationIsInactive = true` (도구 막대·크기 조절 손잡이·번역 기록 패널)
- 툴팁이 없는 도구 막대 항목에 더한다: 번역 언어 고르기, 진행 표시(인식 중·번역 중)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 렌즈를 띄운 뒤 다른 앱이 활성인 상태에서 도구 막대 버튼에 마우스를 올리면 툴팁이 보인다 (실제 앱에서 확인).
- [x] AC2. 도구 막대의 모든 항목(옮기기 손잡이, 상태, 언어, 일시정지, 원문 함께, 번역 기록, 원문, 복사, 닫기)에 툴팁이 있다.
- [x] AC3. `AGENTS.md` 갱신, `./scripts/auto-fix-loop.sh` 통과.

## 진행 기록

- 2026-11-03: TASK 생성. 원인 확인(시험 앱).
- 2026-11-03: `LensPanel.allowsToolTipsWhenApplicationIsInactive`, 툴팁 더함(번역할 언어, 인식하는 중, 번역하는 중).
  실제 앱(개발 빌드)에서 확인: Finder를 활성화한 채 ⌘⇧1·드래그로 렌즈를 띄우고 도구 막대 항목 8개에 마우스를 올리니 8개 모두 툴팁 창이 떴다
  (CGEvent로 마우스 이동, 손쉬운 사용 API로 항목 위치·도움말 읽음, 하네스는 저장소 밖. "원문 함께"는 영상을 볼 때만 보여 확인하지 못함).
  검증 루프 시도 1 통과
