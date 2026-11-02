# TASK-049: 이 맥에서 쓸 릴리즈 빌드 (v0.1.0)

- 상태: COMPLETED
- 생성일: 2026-11-02

## 요청

사용자: "릴리즈" → 확인 질문 답: "내 맥용 릴리즈" (Release 빌드를 개발 인증서로 서명해 /Applications에 설치, v0.1.0 태그 푸시).
외부 배포는 출시 전 필수 조건(Developer ID·공증, API 키 엔진, Sparkle·DMG)이 없어 하지 않는다.

## 설계

- `scripts/install-release.sh`: XcodeGen → Release 빌드(이 맥 아키텍처만) → 개발 인증서로 서명(화면 기록 권한이 개발 빌드와 같은
  인증서 기준이라 유지) → 실행 중인 앱(개발 빌드 포함, 번들 ID가 같아 둘이 함께 뜨면 단축키가 겹침) 종료 → /Applications에 복사 → 실행
- 개발 인증서가 없으면 멈춘다 (임시 서명은 설치할 때마다 권한이 풀린다)
- 버전은 project.yml의 0.1.0(빌드 1). 태그 v0.1.0

## 완료 조건 (Acceptance Criteria)

- [x] AC1. 스크립트로 Release 빌드가 /Applications/AITranslate.app에 설치되고 실행된다. 서명이 개발 인증서이고 검증을 통과한다.
- [x] AC2. `AGENTS.md` 명령어 갱신, `./scripts/auto-fix-loop.sh` 통과.
- [x] AC3. v0.1.0 태그를 붙여 푸시.

## 진행 기록

- 2026-11-02: TASK 생성.
- 2026-11-02: `scripts/install-release.sh`. Release 빌드 약 4분(경고는 MLX Metal 소스뿐), 안쪽 코드는 Frameworks의
  libswiftCompatibilitySpan.dylib 하나. 설치·실행 확인: /Applications/AITranslate.app 0.1.0(빌드 1), 서명 개발 인증서·요구사항이 개발
  빌드와 같음, `codesign --verify --strict` 통과, 실행 뒤 로컬 모델 적재(GPU 메모리 약 1GB). 검증 루프 시도 1 통과.
  렌즈 실제 사용(화면 기록 권한 유지)은 사용자 확인 필요. v0.1.0 태그 푸시
