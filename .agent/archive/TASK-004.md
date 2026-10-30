# TASK-004: 영역 선택 오버레이와 화면 캡처

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

스크린샷(⌘⇧4)처럼 화면 영역을 드래그로 고르고, 그 영역을 원본 해상도로 캡처한다. (사용자: "순서대로 진행")

## 전제와 제약

- 팀 ID 없음, 코드 서명 인증서 0개(`security find-identity -v -p codesigning`) → 임시 서명(ad-hoc)으로 실행.
  임시 서명은 빌드마다 서명값이 바뀌어 화면 기록 권한이 풀릴 수 있다. 무료 Personal Team(Xcode에 Apple ID 로그인)으로
  서명하면 유지된다. 외부 배포용 공증은 유료 Apple Developer Program 필요 (출시 전 조건)
- 내 터미널에는 손쉬운 사용·화면 기록 권한이 없어 오버레이 조작과 실제 캡처를 자동으로 확인할 수 없다
  → 좌표 계산은 단위 테스트로, 화면 동작은 사용자 수동 확인으로 검증한다

## 요구사항

1. `TranslateCore/ScreenGeometry` (좌표 계산은 여기서만)
   - 드래그 두 점 → 정규화된 사각형, 최소 선택 크기 8pt
   - 선택 영역을 화면 안으로 자르기 (겹치지 않으면 nil)
   - 전역 AppKit 좌표(주 화면 왼쪽 아래 원점, y 위로) → 디스플레이 로컬 좌표(왼쪽 위 원점, 포인트)
   - 포인트 → 픽셀 크기(화면 배율, 올림)
2. 앱
   - `ScreenRecordingPermission`: 권한 확인. 처음에는 시스템 요청만 띄우고, 이후에도 없으면 시스템 설정 안내
   - `SelectionOverlayController`: 모든 화면에 투명 패널(화면 보호기 레벨, 모든 Space·전체화면 위, 앱을 활성화하지 않음),
     어둡게 덮고 선택 영역만 밝게, 십자 커서, ESC·오른쪽 클릭 취소, 드래그한 화면 안으로 제한, 너무 작은 선택은 취소
   - `ScreenCapturer`: ScreenCaptureKit `SCScreenshotManager`, 이 앱의 창은 제외, 원본 픽셀 해상도, 커서 제외
   - 메뉴 "영역 번역" 활성화 → 권한 → 선택 → 캡처 → **임시로** 캡처 이미지를 클립보드에 복사 (확인용, TASK-005에서
     OCR·번역·결과창 흐름으로 교체)
3. `scripts/run-app.sh`: 임시 서명 빌드 후 실행 중인 앱을 종료하고 다시 실행
4. `ScreenGeometry` 테스트: 드래그 방향, 최소 크기, 자르기, 주 화면·위쪽 화면·왼쪽(음수 좌표) 화면 변환, 픽셀 크기
5. `AGENTS.md`: 좌표·캡처 규칙, 실행 스크립트, 임시 서명과 권한 주의사항

범위 밖: 단축키, OCR·번역 연결, 결과창 (TASK-005)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. `ScreenGeometry` 테스트가 요구사항 4를 모두 확인하고 통과한다.
- [x] AC2. 앱이 Swift 6 strict concurrency·경고=에러 설정으로 빌드된다 (오버레이·캡처·권한 코드 포함).
- [x] AC3. `scripts/run-app.sh`로 앱이 임시 서명 빌드·실행되고 메뉴바 앱(UIElement)으로 뜬다.
- [x] AC4. 사용자 수동 확인 절차를 기록한다 (실제 화면 확인 결과는 TASK-005 종단 확인 때 함께 받는다).
- [x] AC5. `AGENTS.md`가 갱신됐다.
- [x] AC6. `./scripts/auto-fix-loop.sh`가 통과한다.

## 계획

1. `ScreenGeometry` + 테스트
2. 앱: `AppDelegate`, `ScreenRecordingPermission`, `SelectionOverlayController`(패널·뷰), `ScreenCapturer`, `RegionCaptureController`
3. `scripts/run-app.sh`
4. `AGENTS.md` 갱신
5. `./scripts/auto-fix-loop.sh`, `run-app.sh` 실행

## 진행 기록

- 2026-10-30: TASK 생성.
- 2026-10-30: `ScreenGeometry` + 테스트(7개, 드래그 방향 4가지 포함) 작성. 앱에 `AppDelegate`, `RegionCaptureController`,
  `ScreenRecordingPermission`, `SelectionOverlay`(컨트롤러·패널·뷰), `ScreenCapturer` 추가. 메뉴 "영역 번역" 활성화.
  사전 확인: 패키지 테스트 53개 통과, 앱 빌드 exit 0·경고 0.
- 2026-10-30: `scripts/run-app.sh` 실행 → 임시 서명(`Signature=adhoc`) 빌드, 앱 실행, `UIElement` 확인, 오류 로그 없음.
- 2026-10-30: `AGENTS.md` 갱신 (영역 선택·캡처 구현 위치와 규칙, 임시 서명·권한 주의, 실행 스크립트, 공증 조건).

## 사용자 수동 확인 절차 (TASK-005 종단 확인 때 함께 진행)

1. `./scripts/run-app.sh`로 실행 → 메뉴바 아이콘 → "영역 번역"
2. 처음이면 시스템의 화면 기록 요청 → 시스템 설정에서 AI Translate 허용 → `./scripts/run-app.sh`로 다시 실행
3. "영역 번역" → 화면이 어두워지고 십자 커서 → 웹페이지 일부를 드래그 → "팅" 소리
4. 미리보기 앱 → 파일 > 클립보드에서 새로 만들기 → 드래그한 영역과 같은지, Retina 해상도(선택 크기의 2배 픽셀)인지 확인
5. 다시 "영역 번역" → ESC, 오른쪽 클릭, 짧은 클릭이 모두 취소되는지 확인
6. 외장 모니터에서도 3~4 확인. 원래 앱(브라우저)의 포커스가 유지되는지 확인

## 발견한 문제

- 오버레이 조작과 실제 캡처는 자동 확인 불가 (내 터미널에 손쉬운 사용·화면 기록 권한 없음). 위 수동 절차로 확인 필요.

## 완료

- 2026-10-30: `./scripts/auto-fix-loop.sh` 루프 1 — 시도 1 lint 실패(`ReplaceForEachWithForLoop`, `SelectionOverlay.swift`
  의 `panels.forEach`) → for-in으로 수정 → 시도 2 통과 (테스트 53개). 완료 조건 AC1~AC6 충족.
- 실제 화면에서의 선택·캡처 확인은 아직 하지 않았다 (위 수동 확인 절차, TASK-005 종단 확인 때 함께 진행).
