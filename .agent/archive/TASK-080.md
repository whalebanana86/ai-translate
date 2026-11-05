# TASK-080: 이 맥용 릴리즈 v0.2.4

- 상태: COMPLETED
- 생성일: 2026-11-05

## 요청

TASK-078 보고의 남은 것("설치된 앱(0.2.3)에는 아직 들어가지 않음, install-release.sh로 다시 빌드해야 함")에 "커밋하고 메인머지해 그리고
남은것 진행해" (2026-11-05). v0.2.3(TASK-074)과 같은 방식. 푸시는 요청하지 않아 하지 않는다(태그도 로컬에만).
바뀐 기능은 그래프 번역이 깨지던 문제(TASK-078)와 같은 화면을 읽을 때마다 색·크기가 바뀔 수 있던 문제(TASK-079), 버그 수정뿐이라 수 버전을 올린다.

## 설계

- `project.yml`: `MARKETING_VERSION` 0.2.3 → 0.2.4, `CURRENT_PROJECT_VERSION` 5 → 6
- `./scripts/install-release.sh`로 설치·실행, `release/v0.2.4` 머지 커밋에 v0.2.4 태그(로컬)

## 완료 조건 (Acceptance Criteria)

- [x] AC1. `./scripts/auto-fix-loop.sh TASK-080` 통과.
- [x] AC2. /Applications/AITranslate.app이 0.2.4(빌드 6)이고 개발 인증서 서명이 `codesign --verify --strict`를 통과하며 실행된다.
- [x] AC3. main 머지 커밋에 v0.2.4 태그를 붙인다(푸시하지 않음).

## 진행 기록

- 2026-11-05: TASK 생성.
- 2026-11-05: 버전 0.2.4(빌드 6). 검증 루프 시도 1 통과. 설치·실행 확인: 0.2.4(빌드 6), 서명 "AITranslate Local Development",
  `codesign --verify --strict` 통과. main 머지 커밋에 v0.2.4 태그(로컬, 푸시하지 않음)
