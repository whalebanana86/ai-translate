# TASK-071: 이 맥용 릴리즈 v0.2.2

- 상태: COMPLETED
- 생성일: 2026-11-04

## 요청

사용자: TASK-070 보고 뒤 "커밋, 푸시, 릴리즈(v0.2.2)까지 진행할까요?" → "어 진행해". v0.2.1(TASK-069)과 같은 방식.
바뀐 기능은 X 머리줄 번역 제외(버그 수정)뿐이라 수 버전을 올린다.

## 설계

- `project.yml`: `MARKETING_VERSION` 0.2.1 → 0.2.2, `CURRENT_PROJECT_VERSION` 3 → 4
- `./scripts/install-release.sh`로 설치·실행, `release/v0.2.2` 머지 커밋에 v0.2.2 태그

## 완료 조건 (Acceptance Criteria)

- [x] AC1. `./scripts/auto-fix-loop.sh TASK-071` 통과.
- [x] AC2. /Applications/AITranslate.app이 0.2.2(빌드 4)이고 개발 인증서 서명이 `codesign --verify --strict`를 통과하며 실행된다.
- [x] AC3. main 머지 커밋에 v0.2.2 태그를 붙여 main과 함께 푸시.

## 진행 기록

- 2026-11-04: TASK 생성.
- 2026-11-04: 버전 0.2.2(빌드 4). 검증 루프 시도 1 통과. 설치·실행 확인: 0.2.2(빌드 4), 서명 "AITranslate Local Development",
  `codesign --verify --strict` 통과. main 머지 커밋에 v0.2.2 태그 푸시
