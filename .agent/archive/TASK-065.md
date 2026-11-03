# TASK-065: 이 맥용 릴리즈 v0.2.0

- 상태: COMPLETED
- 생성일: 2026-11-03

## 요청

사용자: "커밋 메인머지 릴리즈 푸시해". v0.1.0(TASK-049) 뒤 TASK-050~064 기능이 쌓여 버전을 올려 릴리즈한다.
방식은 v0.1.0과 같다: Release 빌드를 개발 인증서로 서명해 /Applications에 설치, `release/v0.2.0` 머지 커밋에 v0.2.0 태그.
외부 배포(Developer ID·공증, API 키 엔진, Sparkle·DMG)는 하지 않는다.

## 설계

- `project.yml`: `MARKETING_VERSION` 0.1.0 → 0.2.0 (기능 추가라 부 버전), `CURRENT_PROJECT_VERSION` 1 → 2
- `./scripts/install-release.sh`로 설치·실행

## 완료 조건 (Acceptance Criteria)

- [x] AC1. `./scripts/auto-fix-loop.sh TASK-065` 통과.
- [x] AC2. /Applications/AITranslate.app이 0.2.0(빌드 2)이고 개발 인증서 서명이 `codesign --verify --strict`를 통과하며 실행된다.
- [x] AC3. main 머지 커밋에 v0.2.0 태그를 붙여 main과 함께 푸시.

## 진행 기록

- 2026-11-03: TASK 생성.
- 2026-11-03: 버전 0.2.0(빌드 2). 검증 루프 시도 1 통과. `install-release.sh`로 설치·실행 확인: /Applications/AITranslate.app 0.2.0(빌드 2),
  서명 "AITranslate Local Development"·요구사항이 개발 빌드와 같음, `codesign --verify --strict` 통과. 렌즈 실제 사용은 사용자 확인 필요.
  main 머지 커밋에 v0.2.0 태그 푸시
