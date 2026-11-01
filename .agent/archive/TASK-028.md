# TASK-028: 렌즈를 만든 데스크톱(Space)에만 두기

- 상태: COMPLETED
- 생성일: 2026-11-02

## 요청

사용자: "렌즈를 키면 해당 데스크탑 화면에 남아야 하는데 움직일때마다 따라와"

## 원인

`LensPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` → 렌즈 창 세 개가 모든 데스크톱에 나타난다.
또 렌즈가 따라오므로 다른 데스크톱에서도 그 화면을 캡처·인식·번역했다.

## 설계

- 렌즈 창은 기본(managed) 동작 + `.fullScreenAuxiliary`: 띄운 데스크톱(전체 화면 앱 포함)에만 있다.
  영역 선택 오버레이는 지금처럼 모든 데스크톱에 뜬다
- 렌즈가 지금 데스크톱에 없으면(`isOnActiveSpace` false) 캡처하지 않고, 렌즈 자리의 스크롤도 무시한다.
  돌아오면 떠나기 전 화면과 비교해 그대로면 번역을 그대로 보여준다
- 설정 창: 앱을 활성화하면 macOS가 앱 창이 있는 데스크톱(렌즈)으로 넘어갈 수 있으므로, 창을 먼저 지금 데스크톱에 띄운 뒤 활성화한다

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 렌즈 창이 모든 데스크톱에 나타나지 않는다 (창 설정).
- [x] AC2. 렌즈가 없는 데스크톱을 보는 동안 캡처·인식하지 않는다.
- [x] AC3. `AGENTS.md` 갱신, `./scripts/auto-fix-loop.sh` 통과.
- 실제 데스크톱 전환 확인은 사용자 실사용으로 한다 (자동으로 데스크톱을 바꿀 수 없음)

## 진행 기록

- 2026-11-02: TASK 생성.
- 2026-11-02: `LensPanel.collectionBehavior`를 `[.fullScreenAuxiliary]`로(기본 managed: 띄운 데스크톱에만). `tick()`은 캡처 전후에
  `bodyPanel.isOnActiveSpace`를 확인해 다른 데스크톱에서는 캡처·인식하지 않고, `didScroll()`도 무시. 설정 창은
  `makeKeyAndOrderFront` 뒤 `NSApp.activate()`. `AGENTS.md` 3장 갱신. 검증 루프 시도 1 통과.
  실제 데스크톱 전환·전체 화면 앱에서의 표시는 사용자 확인 필요.
