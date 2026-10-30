# TASK-001: 프로젝트 기본 골격과 자동 검증 파이프라인

- 상태: COMPLETED
- 생성일: 2026-10-30

## 요청

`AGENTS.md`의 작업 절차가 전제로 하는 프로젝트 골격, `.agent/` 구조, `scripts/auto-fix-loop.sh`를 만든다.
자동 수정 루프 제한값은 최대 재시도 3회, 시간 제한 15분 (사용자 승인).

## 요구사항

1. `.agent/` 구조: `PROGRESS.md`, `tasks/`, `attempts/`, `archive/`
2. Xcode 프로젝트는 XcodeGen(`project.yml`)으로 생성하고, 생성된 `.xcodeproj`는 git에서 제외한다.
3. 앱 타깃 `AITranslate`
   - macOS 15.0+, Swift 6, strict concurrency, 경고를 에러로 처리
   - `LSUIElement`(Dock 아이콘 숨김), 메뉴바 아이콘과 종료 메뉴만 있는 최소 앱
   - App Sandbox 끔, Hardened Runtime 켬 (외부 배포·공증 전제)
4. 로직 패키지 `Packages/TranslateCore`
   - `TranslationProvider` 프로토콜
   - JSON 세그먼트 요청/응답 타입과 출력 스키마. 응답 세그먼트 수가 요청과 다르면 에러
   - Swift Testing으로 테스트
5. `scripts/auto-fix-loop.sh`
   - 단계: 타입 검사(`swift build`, 경고=에러) → Lint(`swift format lint --strict`) → 빌드(XcodeGen + `xcodebuild`) → 테스트(`swift test`)
   - 현재 TASK ID는 `.agent/PROGRESS.md`에서 읽는다 (인자로 지정 가능)
   - 모든 실행 결과를 `.agent/attempts/TASK-ID.jsonl`에 기록
   - 최대 재시도 3회(최초 실행 포함 총 4회), 루프 시작 후 15분 제한, 직전과 같은 오류가 반복되면 중단
   - 중단된 루프에서는 재실행을 거부한다. 사용자 승인 후 `--reset "<사유>"`로만 새 루프 시작
6. `AGENTS.md`에 XcodeGen 결정, 검증 명령, 루프 제한값과 reset 규칙을 반영한다.

## 완료 조건 (Acceptance Criteria)

- [x] AC1. `.agent/` 구조와 `PROGRESS.md`가 존재한다.
- [x] AC2. `xcodegen generate`로 `AITranslate.xcodeproj`가 생성되고 `.gitignore`에 포함된다.
- [x] AC3. 앱이 빌드되고, 빌드 설정이 요구사항 3을 만족한다 (Dock 숨김, macOS 15, Swift 6, Sandbox 끔, Hardened Runtime 켬).
- [x] AC4. `TranslateCore` 테스트가 요청 인코딩, 응답 디코딩, 세그먼트 수 불일치 에러, 잘못된 JSON 에러, 스키마 형식을 검증하고 통과한다.
- [x] AC5. `auto-fix-loop.sh`가 실패를 jsonl에 기록하고, 동일 오류 반복·재시도 초과 시 중단하며, 중단 후 재실행을 거부함을 실제로 확인했다.
- [x] AC6. `AGENTS.md`가 갱신됐다.
- [x] AC7. `./scripts/auto-fix-loop.sh`가 통과한다.

## 계획

1. `.agent/` 구조, `.gitignore`, `.swift-format` 작성
2. `Packages/TranslateCore` 작성 (프로토콜, 페이로드, 테스트)
3. `project.yml`, `App/` 작성 후 `xcodegen generate`
4. `scripts/auto-fix-loop.sh` 작성
5. 스크래치 복사본에서 실패·중단 동작 확인 (AC5)
6. `AGENTS.md` 갱신
7. `./scripts/auto-fix-loop.sh` 실행

## 진행 기록

- 2026-10-30: TASK 생성. XcodeGen 미설치 → Homebrew로 설치(2.46.0). SwiftLint 대신 Xcode 내장 `swift format`(6.3.0) 사용.
- 2026-10-30: 골격, `TranslateCore`(프로토콜·페이로드·테스트 6개), `project.yml`, `App/`, `auto-fix-loop.sh` 작성.
- 2026-10-30: 스크래치 복사본에서 검증 (실제 attempts 기록에는 남기지 않음)
  - 정상 코드 전체 통과 (typecheck 4s, lint 1s, build 10s, test 4s)
  - AC5 시나리오 11개 모두 기대대로 동작: 1회차 실패(1), 같은 오류 반복 중단(2), 중단 후 거부(3) ×2, reset(0),
    진행 중 루프 reset 거부(64), 서로 다른 오류 3회(1) 후 4회차 중단(2), 3초 제한 시간 초과 중단(2) 후 남은 하위 프로세스 0개
  - AC3: `-showBuildSettings`와 빌드된 Info.plist에서 LSUIElement=true, macOS 15.0, Swift 6.0, strict concurrency complete,
    경고=에러, Sandbox NO, Hardened Runtime YES 확인
- 2026-10-30: `AGENTS.md`에 XcodeGen·Lint 결정, 디렉터리 구조, 개발 명령어, 루프 제한값·종료 코드·reset 규칙 반영.

## 발견한 문제

- (해결) 변수 바로 뒤에 한글이 붙으면(`$TASK_ID의`) bash 3.2가 한글 바이트까지 변수 이름으로 읽어 `unbound variable`로 종료됨.
  → 해당 변수를 `${...}`로 감쌈.
- (해결) 빈 빌드 캐시에서 같은 오류인데 1·2회차 서명이 달라 반복 감지가 한 번 늦게 걸림. `swift build`의 병렬 실행으로
  드라이버 메시지(`... command failed`)와 출력 순서가 달라지는 것이 원인으로 판단.
  → 서명을 위치가 붙은 진단 줄(`파일:줄:열: error/warning`)과 테스트 실패 줄만 정렬해 만들도록 변경. 첫 빌드·이후 빌드·줄 이동·
  순서 섞임에서 같은 서명, 다른 오류에서는 다른 서명임을 확인하고 시나리오 전체 재검증.
- 번들 ID는 임시값 `com.example.AITranslate`. 배포 전 실제 값으로 변경 필요.
- 개발 중 실행(화면 기록 권한 테스트)에는 `DEVELOPMENT_TEAM` 설정이 필요. 권한을 다루는 TASK에서 처리.

## 완료

- 2026-10-30: `./scripts/auto-fix-loop.sh` 루프 1 시도 1회차 통과 (typecheck 4s, lint 1s, build 9s, test 4s, 테스트 6개).
  `.xcodeproj`와 `.build/`가 git에 잡히지 않음을 확인. 완료 조건 AC1~AC7 충족.
