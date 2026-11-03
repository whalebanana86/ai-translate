# TASK-067: AGENTS.md 줄이기 (영역별 설계 문서로 나누기)

- 상태: COMPLETED
- 생성일: 2026-11-03

## 요청

사용자: "agents.md파일이 점점 커지는데 대책이 필요해"

## 현황

- AGENTS.md 51.7KB·455줄 (2026-10-30 20.7KB → 4일 만에 2.5배). 3장(기술 스택과 구현 규칙)이 37KB로 72%,
  대부분 기능별 동작·측정값·경위. CLAUDE.md가 통째로 가져와 모든 작업의 컨텍스트에 실린다

## 설계

- 3장의 기능별 상세를 `docs/design/<영역>.md` 7개로 옮긴다(문장은 고치지 않고 옮기기만, 옮긴 줄이 빠지지 않았는지 스크립트로 확인):
  capture, recognition, lens, video, translation, localization, signing
- AGENTS.md 3장: 꼭 지킬 규칙(한두 줄씩)과 영역 문서 목록(영역·주요 코드)만
- 작업 절차: 작업할 영역 문서를 읽고, 바꾼 동작·이유는 영역 문서에 적는다. AGENTS.md 크기 상한
- README의 "결정과 근거" 안내 갱신

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 3장에서 옮긴 줄이 모두 영역 문서에 있다 (스크립트 확인, 빠진 줄 0).
- [x] AC2. AGENTS.md가 절반 이하로 줄고, 꼭 지킬 규칙(캡처 API, OCR 설정, 단축키, 포커스, 동시 요청 하나, 권한, 모델 자동 받기 금지,
  화면 글 카탈로그, 개발 서명)은 AGENTS.md에 남는다.
- [x] AC3. 작업 절차에 영역 문서 읽기·갱신과 크기 상한이 있다.
- [x] AC4. `./scripts/auto-fix-loop.sh TASK-067` 통과.

## 진행 기록

- 2026-11-03: TASK 생성.
- 2026-11-03: 3장 33~265줄 중 225줄을 `docs/design/` 7개(capture 3.7KB, recognition 6.7KB, lens 10.6KB, video 5.7KB,
  translation 5.6KB, localization 2.4KB, signing 2.3KB)로 옮김. 스크립트 확인: 빠진 줄 0, 겹친 줄 0. 남긴 줄(메뉴바 앱, 흐름, 단축키,
  로그인, 권한)과 꼭 지킬 규칙 10개, 영역 문서 표. 작업 절차 5.1(영역 문서 읽기)·5.2(영역 문서 갱신)·5.6(24KB 상한, 적을 곳),
  디렉터리 구조·개발 명령어(시간 로그 보기). AGENTS.md 51.7KB·455줄 → 21.8KB·269줄. README 두 개 안내 갱신. 검증 루프 시도 1 통과
