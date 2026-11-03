# TASK-069: 이 맥용 릴리즈 v0.2.1

- 상태: COMPLETED
- 생성일: 2026-11-03

## 요청

사용자: TASK-066~068 보고 뒤 "커밋, 푸시, 릴리즈까지 진행할까요?" → "어 진행해". v0.2.0(TASK-065)과 같은 방식.
바뀐 기능은 "AI" 오인식 고치기(버그 수정)뿐이라 수 버전을 올린다.

## 설계

- `project.yml`: `MARKETING_VERSION` 0.2.0 → 0.2.1, `CURRENT_PROJECT_VERSION` 2 → 3
- `./scripts/install-release.sh`로 설치·실행, `release/v0.2.1` 머지 커밋에 v0.2.1 태그

## 완료 조건 (Acceptance Criteria)

- [x] AC1. `./scripts/auto-fix-loop.sh TASK-069` 통과.
- [x] AC2. /Applications/AITranslate.app이 0.2.1(빌드 3)이고 개발 인증서 서명이 `codesign --verify --strict`를 통과하며 실행된다.
- [x] AC3. main 머지 커밋에 v0.2.1 태그를 붙여 main과 함께 푸시.

## 진행 기록

- 2026-11-03: TASK 생성.
- 2026-11-03: 버전 0.2.1(빌드 3). 검증 루프 시도 1 통과. 설치·실행 확인: 0.2.1(빌드 3), 서명 "AITranslate Local Development",
  `codesign --verify --strict` 통과. main 머지 커밋에 v0.2.1 태그 푸시
