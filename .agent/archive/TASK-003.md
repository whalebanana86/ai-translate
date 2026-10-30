# TASK-003: Vision OCR과 번역 세그먼트(문단) 만들기

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

캡처 이미지에서 텍스트를 줄 단위로 인식하고(위치 포함), 줄을 문단으로 묶어 번역 세그먼트로 만든다.
(사용자: "순서대로 진행" — TASK-003 OCR → TASK-004 오버레이·캡처 → TASK-005 단축키·결과창)

## 사전 확인 (Vision `RecognizeTextRequest`, macOS 26.3)

- 기본값: 정확도 우선, 언어 보정 켬, 언어 자동 감지 꺼짐, 인식 언어 `en-US` 하나 → 그대로 쓰면 한국어 인식 불가
- 자동 감지 없이 `ko-KR, en-US, ja-JP` 지정: 일본어 줄 누락
- 자동 감지 + 언어 힌트: 영어·한국어·일본어 모두 인식 (신뢰도 1.00, 0.23s / 첫 실행 0.65s)
- `boundingBox.toImageCoordinates(size, origin: .upperLeft)`: 그린 위치와 일치하는 왼쪽 위 원점 픽셀 좌표

## 요구사항

1. `TextRecognizer.recognize(CGImage) async throws -> [RecognizedLine]`
   - 정확도 우선, 언어 보정, 언어 자동 감지 + 언어 힌트(기본: en-US, ko-KR, ja-JP, zh-Hans, zh-Hant)
   - `RecognizedLine`: 텍스트, 신뢰도, 이미지 픽셀 좌표(왼쪽 위 원점)의 영역
   - 빈 줄 제외, 위→아래(같으면 왼쪽→오른쪽) 순서
2. `TextBlockGrouper.group([RecognizedLine]) -> [TextBlock]`
   - 같은 문단: 바로 위 줄과 세로 간격이 줄 높이의 0.8배 이하, 가로 범위가 겹침, 줄 높이 비율 1.5배 이하
   - 다단 구성처럼 줄이 번갈아 나와도 각 단의 문단으로 묶는다
   - 줄 잇기: 한자·가나·전각 문장부호 경계는 공백 없이, 그 밖(영어·한국어 등)은 공백 하나로
   - `TextBlock`: 줄 목록, 합친 텍스트, 전체 영역(줄 영역의 합집합)
3. 테스트
   - 코드로 그린 이미지로 OCR: 영어·한국어·일본어, 좌표, 순서, 빈 이미지
   - 합성한 줄로 문단 묶기 규칙
   - 그린 이미지 → OCR → 문단 묶기 전체 흐름
4. `AGENTS.md` 3장 OCR 규칙 갱신

범위 밖: 화면 캡처, 번역 요청 연결, 표·문서 구조 인식(`RecognizeDocumentsRequest`는 macOS 26+라 최소 버전 15에서 기본 경로로 못 씀)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 영어·한국어·일본어가 섞인 그린 이미지에서 세 줄이 정확한 텍스트로 인식된다.
- [x] AC2. 인식 영역이 그린 위치와 왼쪽 위 원점 픽셀 좌표로 일치하고(오차 ±8px), 위→아래 순서다. 빈 이미지는 빈 결과다.
- [x] AC3. 문단 묶기 규칙(간격, 다단, 크기 차이, CJK/공백 잇기, 합집합 영역, 빈 입력)이 테스트로 확인된다.
- [x] AC4. 두 줄로 줄바꿈된 문단과 별도 문단을 그린 이미지가 OCR → 묶기를 거쳐 문단 2개가 된다.
- [x] AC5. `AGENTS.md`가 갱신됐다.
- [x] AC6. `./scripts/auto-fix-loop.sh`가 통과한다.

## 계획

1. `TextRecognizer.swift`, `TextBlockGrouper.swift` 작성
2. 테스트 헬퍼(텍스트 이미지 그리기)와 테스트 3종 작성
3. `AGENTS.md` 갱신
4. `./scripts/auto-fix-loop.sh` 실행

## 진행 기록

- 2026-10-30: TASK 생성, Vision API 사전 확인.
- 2026-10-30: `TextRecognizer`, `TextBlockGrouper` 작성. 테스트 헬퍼 `TextImage`(CoreText로 그리기)와
  `TextRecognizerTests`(4개), `TextBlockGrouperTests`(8개, 잇기 규칙 5가지 포함) 작성. 사전 실행에서 새 테스트 모두 통과.
- 2026-10-30: `AGENTS.md` 3장 OCR 규칙 갱신.

## 발견한 문제

- (해결, TASK-002 테스트) OCR 테스트가 함께 돌며 부하가 커지자 `ProcessExecutorTests.returnsWhenGrandchildKeepsPipeOpen`이
  실패함. 손자 프로세스가 1초 시간 제한 안에 프로세스 그룹을 벗어나지 못해 상황이 재현되지 않았고, TASK-002에서 넣은
  `ready` 단언이 이를 잡아낸 것.
  → 시간 제한 대신 `ready` 파일이 생긴 뒤 Task를 취소하는 방식으로 바꿔 부하와 무관하게 결정적으로 만듦.
  전체 실행 3회 통과(2.8~3.2s). 복사본에서 출력 수집 대기 상한을 없애는 변형을 넣으면 8.0s로 실패함을 확인
  (테스트가 실제로 결함을 잡음).

## 완료

- 2026-10-30: `./scripts/auto-fix-loop.sh` 루프 1 시도 1회차 통과 (테스트 46개, 라이브 1개 건너뜀). 완료 조건 AC1~AC6 충족.
