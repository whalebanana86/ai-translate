# 화면 고르기·캡처·변화 감시

다루는 범위: 영역 선택 오버레이, 화면 캡처, 바뀐 화면을 찾아 다시 인식하는 주기, 계속 바뀌는 화면(영상), 스크롤 뒤 지난 번역 숨김, 단계별 시간 로그.

이 영역의 코드를 바꾸기 전에 읽고, 바꾼 동작과 그 이유(사용자 요청·측정값·실패한 방법)를 여기에 적는다.
모든 작업에 공통인 규칙은 [AGENTS.md](../../AGENTS.md)에 있다.

- 영역 선택: 모니터마다 투명 오버레이 창을 직접 구현한다. 모든 Space와 전체화면 앱 위에 표시하고, ESC로 취소한다. 멀티 모니터, Retina 배율, 좌표계 변환(AppKit 왼쪽 아래 원점 ↔ CG 왼쪽 위 원점)을 처리한다
  - 구현: `App/SelectionOverlay.swift`. 오버레이는 `.nonactivatingPanel`이라 원래 앱의 포커스를 빼앗지 않는다
  - 좌표 변환은 `TranslateCore/ScreenGeometry`에서만 하고 테스트한다. 선택은 드래그를 시작한 화면 안으로 자른다
- 캡처: ScreenCaptureKit(`SCScreenshotManager`). `CGWindowListCreateImage`는 쓰지 않는다 (macOS 15부터 사용 불가)
  - 구현: `App/ScreenCapturer.swift`. 이 앱의 창은 `excludingApplications`로 빼고, 크기는 `backingScaleFactor`로 원본 픽셀
  - 창 목록 조회(`SCShareableContent`)와 필터는 화면별로 5초 재사용하고, 캡처가 실패하면 다시 조회한다
- 감시: 캡처 → `ImageFingerprint`/`ChangeTracker`로 바뀐 뒤 멈췄을 때만 OCR (기준값은 측정으로 정함). 간격은
  `CaptureSchedule`: 평소 0.5초, 화면이 바뀌는 중 0.15초, 스크롤 중이면 마지막 스크롤 0.15초 뒤 바로.
  포인터가 렌즈 위에서 움직이거나 누른 뒤 1초 동안도 0.15초(전역 `mouseMoved`·클릭 모니터, 권한 불필요. TASK-072: 0.5초
  간격이면 메뉴가 열린 뒤 그만큼 지난 번역이 메뉴를 덮었고, 닫힌 뒤 메뉴 번역이 페이지 위에 남았다)
- 계속 바뀌는 화면(재생 중인 영상, 움직이는 광고): 멈추기만 기다리면 인식하지 않는다(2026-11-02 사용자 보고). 사용자 동작
  없이 0.6초 동안 계속 바뀌면 바뀌는 중에도 인식하고(`ChangeTracker.Change.keepsChanging`), 그 뒤 0.25초마다 다시 인식한다.
  이때는 화면이 바뀌어도 번역을 숨기지 않고 다음 인식이 문단을 바꾼다. 영상 장면이 멈췄다 다시 움직여도 이 판단을 유지하고
  (멈추면 평소 동작으로 돌아가게 했더니 자막이 바뀔 때 번역을 숨겨 원문이 보였다, TASK-031), 렌즈 아래가 다른 내용으로 바뀌었을
  수 있는 사용자 동작(스크롤·마우스 클릭·앱 전환·렌즈 이동) 뒤에만 평소 동작으로 돌아간다. 클릭은 전역 마우스 모니터(권한 불필요),
  앱 전환은 `NSWorkspace.didActivateApplicationNotification`
- 지난 번역 숨김(`LensModel.isOutdated`): 렌즈 아래 내용을 움직이는 스크롤(전역 스크롤 모니터, 마우스 이벤트라 권한 불필요.
  포인터가 렌즈 안이거나 렌즈 가운데 아래와 같은 창 위면(`WindowStack`, `CGWindowListCopyWindowInfo` 일반 층, 이 앱 창 제외,
  스크롤 묶음의 첫 이벤트에서만 조회) 바로 숨긴다. 렌즈 안만 보면 렌즈가 페이지 일부만 덮을 때 번역이 남았다, TASK-041), 처리한 화면에서
  크게 벗어난 화면(`ChangeTracker.movedAwayThreshold`, 단어 하나 변경은 제외), 이동·크기 조절 중에는 번역을 그리지 않는다.
  다시 인식하면 보이고, 화면이 그대로면 스크롤이 멈춘 뒤 보인다. 인식 중에 또 스크롤했으면 다음 화면을 기다린다
  - 스크롤 이벤트 없이 크게 벗어난 화면은 바뀐 곳에 걸친 문단만 숨긴다(`ChangedArea`, `LensModel.hiddenParagraphIDs`.
    TASK-072 사용자 보고: 웹페이지 메뉴에 포인터를 올릴 때마다 렌즈 전체가 원문으로 깜빡였다가 다시 그려졌다. 드롭다운도 전체 평균
    차이가 기준을 넘는다). 지문 픽셀(렌즈의 1/64)마다 밝기 차이가 5 이상이면 바뀐 곳이고(같은 화면은 0, 흰 메뉴가 연한 바탕을
    덮으면 약 9), 문단 OCR 영역이 걸치면 숨긴다. 숨긴 문단은 화면이 처리한 화면으로 돌아오거나 다시 인식하면 보인다.
    키보드 스크롤·페이지 이동은 글이 모두 움직여 모든 문단이 숨는다. 전체 평균 기준은 그대로라 작은 변화(호버 강조)는 숨기지 않는다.
    번역이 원문 영역보다 크게 그려진 부분만 바뀐 곳에 걸치면 그 문단은 숨기지 않는다
- 단계별 시간 기록(`Logger` subsystem `com.example.AITranslate`, category `pipeline`, info 단계, 숫자·엔진 이름만).
  보기: `/usr/bin/log stream --level info --predicate 'subsystem == "com.example.AITranslate"'` (zsh는 `log`가 내장 명령)
